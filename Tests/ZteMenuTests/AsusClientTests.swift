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
private let dataOK = #"""
{"wan0_state_t":"2","wan0_proto":"dhcp",
 "uptime":"Mon, 24 Aug 2026 21:40:12 +0200(1234567 secs since boot)",
 "netdev":{"INTERNET_rx":"0x0000000000001000","INTERNET_tx":"0x0000000000000800"}}
"""#
private let dataSecond = #"{"netdev":{"INTERNET_rx":"0x0000000000002000","INTERNET_tx":"0x0000000000000C00"}}"#

private func makeClient(_ http: any HTTPFetching, password: String? = "haslo") -> AsusClient {
    AsusClient(baseURL: asusURL, username: "admin", password: password,
               http: http, pause: { _ in })   // tests never sleep
}

final class AsusClientLoginTests: XCTestCase {
    func testLoginRequestShape() async throws {
        let http = SequenceHTTP([loginOK, dataOK, dataSecond])
        _ = try await makeClient(http).fetch()

        let login = http.requests[0]
        XCTAssertEqual(login.url?.absoluteString, "http://192.168.50.1/login.cgi")
        XCTAssertEqual(login.httpMethod, "POST")
        XCTAssertEqual(login.value(forHTTPHeaderField: "Referer"),
                       "http://192.168.50.1/Main_Login.asp")
        XCTAssertEqual(login.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        let body = String(data: login.httpBody ?? Data(), encoding: .utf8) ?? ""
        // base64("admin:haslo") — the credential pair, never logged elsewhere.
        XCTAssertEqual(body, "login_authorization=YWRtaW46aGFzbG8=")
    }

    func testTokenEchoedAsCookieOnDataRequests() async throws {
        let http = SequenceHTTP([loginOK, dataOK, dataSecond])
        _ = try await makeClient(http).fetch()

        XCTAssertEqual(http.requests.count, 3, "login + two samples")
        for request in http.requests.dropFirst() {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"),
                           "asus_token=AbCdEf123456")
        }
        let hooks = http.requests[1].url?.absoluteString ?? ""
        XCTAssertTrue(hooks.hasPrefix("http://192.168.50.1/appGet.cgi?hook="))
        for hook in ["nvram_get(wan0_state_t)", "nvram_get(wan0_proto)",
                     "uptime()", "netdev(appobj)"] {
            XCTAssertTrue(hooks.contains(hook), "missing hook \(hook)")
        }
        XCTAssertTrue(http.requests[2].url!.absoluteString.contains("netdev(appobj)"))
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
    private func fetch(first: String = dataOK, second: String = dataSecond) async throws -> ModemData {
        let http = SequenceHTTP([loginOK, first, second])
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

    func testCounterResetBetweenSamplesYieldsNilSpeeds() async throws {
        let rebooted = #"{"netdev":{"INTERNET_rx":"0x10","INTERNET_tx":"0x10"}}"#
        let d = try await fetch(second: rebooted)
        XCTAssertNil(d.rxSpeed)
        XCTAssertNil(d.txSpeed)
    }

    func testOfflineAndUnknownFieldsDegradeGracefully() async throws {
        let sparse = #"{"wan0_state_t":"0","netdev":{"INTERNET_rx":"junk","INTERNET_tx":"0xZZ"}}"#
        let d = try await fetch(first: sparse, second: sparse)
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
