import XCTest
@testable import ZteMenu

private struct StubHTTP: HTTPFetching {
    let payload: Data
    var capturedURL: URLBox = URLBox()
    final class URLBox: @unchecked Sendable { var url: URL? }
    func data(from url: URL) async throws -> Data {
        capturedURL.url = url
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

        let url = try XCTUnwrap(stub.capturedURL.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("http://192.168.0.1/goform/goform_get_cmd_process"))
        XCTAssertTrue(url.absoluteString.contains("multi_data=1"))
        XCTAssertTrue(url.absoluteString.contains("battery_value"))
        XCTAssertTrue(url.absoluteString.contains("Z5g_rsrp"))
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
