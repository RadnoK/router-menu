import XCTest
@testable import ZteMenu

private let zteURL = URL(string: "http://192.168.0.1")!

private struct StubHTTP: HTTPFetching {
    let payload: Data
    var capturedRequest: RequestBox = RequestBox()
    final class RequestBox: @unchecked Sendable { var request: URLRequest? }
    func data(for request: URLRequest) async throws -> Data {
        capturedRequest.request = request
        return payload
    }
}

final class ZTEClientTests: XCTestCase {
    func testBuildsQueryAndParses() async throws {
        let json = #"{"network_type":"ENDC","signalbar":"5","battery_value":"60","battery_charging":"0","ppp_status":"ppp_connected","network_provider":"T-Mobile.pl","Z5g_rsrp":"-81","Z5g_SINR":"33.0"}"#
        let stub = StubHTTP(payload: Data(json.utf8))
        let client = ZTEClient(baseURL: zteURL, http: stub)

        let data = try await client.fetch()

        XCTAssertEqual(data.batteryPercent, 60)
        XCTAssertEqual(data.networkLabel, "5G")

        let request = try XCTUnwrap(stub.capturedRequest.request)
        let url = try XCTUnwrap(request.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("http://192.168.0.1/goform/goform_get_cmd_process"))
        XCTAssertTrue(url.absoluteString.contains("multi_data=1"))
        XCTAssertTrue(url.absoluteString.contains("battery_value"))
        XCTAssertTrue(url.absoluteString.contains("Z5g_rsrp"))
        XCTAssertTrue(url.absoluteString.contains("realtime_rx_thrpt"))
    }

    // The ZTE U50 modem only returns data with a Referer header pointing at
    // its panel (a simple anti-CSRF guard). Without it, it returns empty strings.
    func testSendsRefererHeader() async throws {
        let json = #"{"battery_value":"41"}"#
        let stub = StubHTTP(payload: Data(json.utf8))
        let client = ZTEClient(baseURL: zteURL, http: stub)

        _ = try await client.fetch()

        let request = try XCTUnwrap(stub.capturedRequest.request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "http://192.168.0.1/")
    }

    func testInvalidJSONThrows() async {
        let stub = StubHTTP(payload: Data("not json".utf8))
        let client = ZTEClient(baseURL: zteURL, http: stub)
        do {
            _ = try await client.fetch()
            XCTFail("Expected an error")
        } catch {
            // ok
        }
    }
}

private final class SequenceHTTP: HTTPFetching, @unchecked Sendable {
    private let responses: [Data]
    private(set) var requests: [URLRequest] = []
    private var i = 0
    init(_ responses: [Data]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> Data {
        requests.append(request)
        defer { i += 1 }
        return responses[min(i, responses.count - 1)]
    }
}

final class ZTEClientLoginTests: XCTestCase {
    func testWithPasswordLogsInThenFetches() async throws {
        let ld = #"{"LD":"ABC123"}"#
        let loginOK = #"{"result":"0"}"#
        let data = #"{"battery_value":"50","signalbar":"5","network_type":"ENDC","total_rx_bytes":"1000","total_tx_bytes":"500"}"#
        let http = SequenceHTTP([Data(ld.utf8), Data(loginOK.utf8), Data(data.utf8)])
        let client = ZTEClient(baseURL: zteURL, http: http, password: "secret")

        let result = try await client.fetch()

        XCTAssertEqual(result.totalRx, 1000)
        // 3 requests: GET LD, POST LOGIN, GET data
        XCTAssertEqual(http.requests.count, 3)
        XCTAssertTrue(http.requests[0].url!.absoluteString.contains("cmd=LD"))
        XCTAssertEqual(http.requests[1].httpMethod, "POST")
        XCTAssertTrue(http.requests[2].url!.absoluteString.contains("total_rx_bytes"))
    }

    func testWithoutPasswordSkipsLogin() async throws {
        let data = #"{"battery_value":"50","signalbar":"5","network_type":"ENDC"}"#
        let http = SequenceHTTP([Data(data.utf8)])
        let client = ZTEClient(baseURL: zteURL, http: http, password: nil)

        _ = try await client.fetch()

        // 1 request: just GET data, no login
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(http.requests[0].httpMethod ?? "GET", "GET")
    }
}

final class ZTEClientProbeTests: XCTestCase {
    func testProbeSucceedsWhenTheDeviceAnswers() async throws {
        let stub = StubHTTP(payload: Data("<html>".utf8))
        let client = ZTEClient(baseURL: zteURL, http: stub)

        let reachable = await client.probe()

        XCTAssertTrue(reachable)
        let request = try XCTUnwrap(stub.capturedRequest.request)
        XCTAssertEqual(request.httpMethod, "HEAD")
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.0.1")
        XCTAssertEqual(request.timeoutInterval, 3)
    }

    func testProbeFailsWhenTheRequestThrows() async {
        struct Boom: Error {}
        struct ThrowingHTTP: HTTPFetching {
            func data(for request: URLRequest) async throws -> Data { throw Boom() }
        }
        let client = ZTEClient(baseURL: zteURL, http: ThrowingHTTP())
        let reachable = await client.probe()
        XCTAssertFalse(reachable)
    }
}
