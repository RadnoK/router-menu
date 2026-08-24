import XCTest
@testable import ZteMenu

/// Records every request and replays canned responses in order.
private final class SequenceHTTP: HTTPFetching, @unchecked Sendable {
    private let responses: [Data]
    private(set) var requests: [URLRequest] = []
    private var i = 0
    init(_ responses: [String]) { self.responses = responses.map { Data($0.utf8) } }
    func data(for request: URLRequest) async throws -> Data {
        requests.append(request)
        defer { i += 1 }
        return responses[min(i, responses.count - 1)]
    }
}

private struct ThrowingHTTP: HTTPFetching {
    struct Boom: Error {}
    func data(for request: URLRequest) async throws -> Data { throw Boom() }
}

private let asusURL = URL(string: "http://192.168.50.1")!
private let loginOK = #"{"asus_token":"AbCdEf123456"}"#
// One response per hook: chained semicolon hooks return empty fields on
// some firmware builds, so the driver asks one hook at a time.
private let rState = #"{"wan0_state_t":"2"}"#
private let rProto = #"{"wan0_proto":"dhcp"}"#
private let rUptime = #"{"uptime":"Mon, 24 Aug 2026 21:40:12 +0200(1234567 secs since boot)"}"#
private let rNetdev1 = #"{"netdev":{"INTERNET_rx":"0x0000000000001000","INTERNET_tx":"0x0000000000000800"}}"#
private let rNetdev2 = #"{"netdev":{"INTERNET_rx":"0x0000000000002000","INTERNET_tx":"0x0000000000000C00"}}"#
private let happySequence = [loginOK, rState, rProto, rUptime, rNetdev1, rNetdev2]

private func makeClient(_ http: any HTTPFetching, password: String? = "haslo") -> AsusClient {
    AsusClient(baseURL: asusURL, username: "admin", password: password,
               http: http, pause: { _ in })   // tests never sleep
}

final class AsusClientLoginTests: XCTestCase {
    func testLoginRequestShape() async throws {
        let http = SequenceHTTP(happySequence)
        _ = try await makeClient(http).fetch()

        let login = http.requests[0]
        XCTAssertEqual(login.url?.absoluteString, "http://192.168.50.1/login.cgi")
        XCTAssertEqual(login.httpMethod, "POST")
        XCTAssertEqual(login.value(forHTTPHeaderField: "Referer"),
                       "http://192.168.50.1/Main_Login.asp")
        XCTAssertEqual(login.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        // Newer Asuswrt firmware only engages the JSON login API for an
        // asusrouter-style user agent — a default UA gets the HTML redirect
        // (verified live against the target router).
        XCTAssertEqual(login.value(forHTTPHeaderField: "User-Agent"),
                       "asusrouter--DUTUtil-")
        let body = String(data: login.httpBody ?? Data(), encoding: .utf8) ?? ""
        // base64("admin:haslo") — the credential pair, never logged elsewhere.
        XCTAssertEqual(body, "login_authorization=YWRtaW46aGFzbG8=")
    }

    func testTokenEchoedAsCookieOnDataRequests() async throws {
        let http = SequenceHTTP(happySequence)
        _ = try await makeClient(http).fetch()

        XCTAssertEqual(http.requests.count, 6, "login + four hook reads + the speed sample")
        for request in http.requests.dropFirst() {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"),
                           "asus_token=AbCdEf123456")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"),
                           "asusrouter--DUTUtil-")
            XCTAssertTrue(request.url!.absoluteString
                            .hasPrefix("http://192.168.50.1/appGet.cgi?hook="))
        }
        // One hook per request — chained hooks return empty fields on some
        // firmware builds (observed live on the target router).
        let expected = ["nvram_get(wan0_state_t)", "nvram_get(wan0_proto)",
                        "uptime()", "netdev(appobj)", "netdev(appobj)"]
        for (offset, hook) in expected.enumerated() {
            XCTAssertTrue(http.requests[offset + 1].url!.absoluteString.contains(hook),
                          "request \(offset + 1) should carry \(hook)")
        }
    }

    func testMissingPasswordFailsBeforeAnyRequest() async {
        let http = SequenceHTTP([loginOK])
        do {
            _ = try await makeClient(http, password: nil).fetch()
            XCTFail("expected loginFailed")
        } catch ModemError.loginFailed {
            XCTAssertTrue(http.requests.isEmpty)
        } catch { XCTFail("unexpected \(error)") }
    }

    func testTokenlessLoginResponseIsLoginFailed() async {
        // What the firmware returns for bad credentials (an error page /
        // JSON without asus_token).
        let http = SequenceHTTP([#"{"error_status":"3"}"#])
        do {
            _ = try await makeClient(http).fetch()
            XCTFail("expected loginFailed")
        } catch ModemError.loginFailed {
        } catch { XCTFail("unexpected \(error)") }
    }

    func testHTMLInsteadOfDataIsUnreachable() async {
        // Session expired mid-flight: appGet answers with the login redirect.
        let html = "<HTML><HEAD><script>window.top.location.href='/Main_Login.asp';</script></HEAD></HTML>"
        let http = SequenceHTTP([loginOK, html])
        do {
            _ = try await makeClient(http).fetch()
            XCTFail("expected unreachable")
        } catch ModemError.loginFailed {
            XCTFail("HTML after a good login is not a credential problem")
        } catch {
            // ok — any non-login error maps to .unreachable at the store
        }
    }
}

final class AsusClientParseTests: XCTestCase {
    private func fetch(_ sequence: [String] = happySequence) async throws -> ModemData {
        let http = SequenceHTTP(sequence)
        return try await makeClient(http).fetch()
    }

    func testMapsOnlineUptimeAndCounters() async throws {
        let d = try await fetch()
        XCTAssertTrue(d.isOnline)
        XCTAssertEqual(d.networkType, "DHCP")
        XCTAssertEqual(d.sessionUptime, 1234567)
        XCTAssertEqual(d.totalRx, 0x2000, "totals come from the fresher second sample")
        XCTAssertEqual(d.totalTx, 0xC00)
        XCTAssertNil(d.batteryPercent)
        XCTAssertFalse(d.isCharging)
        XCTAssertEqual(d.signalBars, 0)
        XCTAssertNil(d.rsrp)
        XCTAssertNil(d.monthlyRx)
    }

    func testSpeedsAreTheSampleDeltaPerSecond() async throws {
        let d = try await fetch()
        // rx: 0x2000-0x1000 = 4096 B over 1 s; tx: 0xC00-0x800 = 1024 B.
        XCTAssertEqual(d.rxSpeed, 4096)
        XCTAssertEqual(d.txSpeed, 1024)
    }

    func testASingleFailedHookDegradesInsteadOfFailing() async throws {
        // The uptime hook answers with the login-redirect HTML; everything
        // else is healthy — the reading survives with that one field nil.
        let html = "<HTML><HEAD><script>window.top.location.href='/Main_Login.asp';</script></HEAD></HTML>"
        let d = try await fetch([loginOK, rState, rProto, html, rNetdev1, rNetdev2])
        XCTAssertTrue(d.isOnline)
        XCTAssertNil(d.sessionUptime)
        XCTAssertEqual(d.rxSpeed, 4096)
    }

    func testCounterResetBetweenSamplesYieldsNilSpeeds() async throws {
        let rebooted = #"{"netdev":{"INTERNET_rx":"0x10","INTERNET_tx":"0x10"}}"#
        let d = try await fetch([loginOK, rState, rProto, rUptime, rNetdev1, rebooted])
        XCTAssertNil(d.rxSpeed)
        XCTAssertNil(d.txSpeed)
    }

    func testOfflineAndUnknownFieldsDegradeGracefully() async throws {
        let junkNetdev = #"{"netdev":{"INTERNET_rx":"junk","INTERNET_tx":"0xZZ"}}"#
        let d = try await fetch([loginOK, #"{"wan0_state_t":"0"}"#, "{}", "{}",
                                 junkNetdev, junkNetdev])
        XCTAssertFalse(d.isOnline)
        XCTAssertEqual(d.networkType, "")
        XCTAssertNil(d.sessionUptime)
        XCTAssertNil(d.totalRx)
        XCTAssertNil(d.rxSpeed)
    }
}

final class AsusClientProbeTests: XCTestCase {
    private final class OneShotHTTP: HTTPFetching, @unchecked Sendable {
        let payload: String
        private(set) var request: URLRequest?
        init(_ payload: String) { self.payload = payload }
        func data(for request: URLRequest) async throws -> Data {
            self.request = request
            return Data(payload.utf8)
        }
    }

    func testProbeRecognisesTheAsusLoginPage() async {
        let http = OneShotHTTP("<title>ASUS Login</title>")
        let client = makeClient(http)
        let hit = await client.probe()
        XCTAssertTrue(hit)
        XCTAssertEqual(http.request?.url?.absoluteString,
                       "http://192.168.50.1/Main_Login.asp")
        XCTAssertEqual(http.request?.timeoutInterval, 3)
    }

    func testProbeRejectsForeignDevices() async {
        let hit = await makeClient(OneShotHTTP("<title>TP-Link</title>")).probe()
        XCTAssertFalse(hit, "an answering non-Asus device must not match")
    }

    func testProbeFailsOnError() async {
        let hit = await makeClient(ThrowingHTTP()).probe()
        XCTAssertFalse(hit)
    }
}
