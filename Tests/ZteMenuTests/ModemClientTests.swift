import XCTest
@testable import ZteMenu

private struct StubHTTP: HTTPFetching {
    let payload: Data
    var capturedRequest: RequestBox = RequestBox()
    final class RequestBox: @unchecked Sendable { var request: URLRequest? }
    func data(for request: URLRequest) async throws -> Data {
        capturedRequest.request = request
        return payload
    }
}

final class ModemClientTests: XCTestCase {
    func testBuildsQueryAndParses() async throws {
        let json = #"{"network_type":"ENDC","signalbar":"5","battery_value":"60","battery_charging":"0","ppp_status":"ppp_connected","network_provider":"T-Mobile.pl","Z5g_rsrp":"-81","Z5g_SINR":"33.0"}"#
        let stub = StubHTTP(payload: Data(json.utf8))
        let client = ModemClient(baseURL: Config.modemBaseURL, http: stub)

        let data = try await client.fetch()

        XCTAssertEqual(data.batteryPercent, 60)
        XCTAssertEqual(data.networkLabel, "5G")

        let request = try XCTUnwrap(stub.capturedRequest.request)
        let url = try XCTUnwrap(request.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("http://192.168.0.1/goform/goform_get_cmd_process"))
        XCTAssertTrue(url.absoluteString.contains("multi_data=1"))
        XCTAssertTrue(url.absoluteString.contains("battery_value"))
        XCTAssertTrue(url.absoluteString.contains("Z5g_rsrp"))
    }

    // Modem ZTE U50 oddaje dane tylko przy nagłówku Referer wskazującym na panel
    // (prosta ochrona anty-CSRF). Bez niego zwraca puste stringi.
    func testSendsRefererHeader() async throws {
        let json = #"{"battery_value":"41"}"#
        let stub = StubHTTP(payload: Data(json.utf8))
        let client = ModemClient(baseURL: Config.modemBaseURL, http: stub)

        _ = try await client.fetch()

        let request = try XCTUnwrap(stub.capturedRequest.request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "http://192.168.0.1/")
    }

    func testInvalidJSONThrows() async {
        let stub = StubHTTP(payload: Data("not json".utf8))
        let client = ModemClient(baseURL: Config.modemBaseURL, http: stub)
        do {
            _ = try await client.fetch()
            XCTFail("Oczekiwano błędu")
        } catch {
            // ok
        }
    }
}
