import Foundation

public protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

extension URLSession: HTTPFetching {
    public func data(from url: URL) async throws -> Data {
        let (data, _) = try await self.data(from: url, delegate: nil)
        return data
    }
}

public struct ModemClient: Sendable {
    let baseURL: URL
    let http: HTTPFetching

    static let commandFields = [
        "network_type", "signalbar",
        "battery_value", "battery_charging",
        "ppp_status", "network_provider",
        "Z5g_rsrp", "Z5g_SINR",
    ]

    public init(baseURL: URL = Config.modemBaseURL, http: HTTPFetching = URLSession.shared) {
        self.baseURL = baseURL
        self.http = http
    }

    func fetch() async throws -> ModemData {
        var comps = URLComponents(url: baseURL.appendingPathComponent("goform/goform_get_cmd_process"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "isTest", value: "false"),
            URLQueryItem(name: "cmd", value: Self.commandFields.joined(separator: ",")),
            URLQueryItem(name: "multi_data", value: "1"),
        ]
        let data = try await http.data(from: comps.url!)
        let raw = try JSONDecoder().decode([String: String].self, from: data)
        return ModemData.parse(raw)
    }
}
