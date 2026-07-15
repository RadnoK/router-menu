import Foundation

public protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> Data
}

extension URLSession: HTTPFetching {
    public func data(for request: URLRequest) async throws -> Data {
        let (data, _) = try await self.data(for: request, delegate: nil)
        return data
    }
}

public struct ModemClient: Sendable {
    let baseURL: URL
    let http: HTTPFetching
    let password: String?

    static let statusFields = [
        "network_type", "signalbar",
        "battery_value", "battery_charging",
        "ppp_status", "network_provider",
        "Z5g_rsrp", "Z5g_SINR",
        "realtime_rx_thrpt", "realtime_tx_thrpt",
    ]

    static let trafficFields = [
        "realtime_rx_bytes", "realtime_tx_bytes",
        "total_rx_bytes", "total_tx_bytes",
        "monthly_rx_bytes", "monthly_tx_bytes",
        "realtime_time", "monthly_time",
    ]

    public init(baseURL: URL = Config.modemBaseURL,
                http: HTTPFetching = URLSession.shared,
                password: String? = nil) {
        self.baseURL = baseURL
        self.http = http
        self.password = password
    }

    func fetch() async throws -> ModemData {
        var fields = Self.statusFields
        if password != nil {
            try await login()
            fields += Self.trafficFields
        }
        let data = try await getCmd(fields)
        let raw = try JSONDecoder().decode([String: String].self, from: data)
        return ModemData.parse(raw)
    }

    private func login() async throws {
        guard let password else { return }
        let ldData = try await getCmd(["LD"])
        let ldRaw = try JSONDecoder().decode([String: String].self, from: ldData)
        guard let ld = ldRaw["LD"], !ld.isEmpty else {
            throw ModemError.loginFailed
        }
        let hash = ZTEAuth.loginHash(password: password, ld: ld)
        var req = URLRequest(url: baseURL.appendingPathComponent("goform/goform_set_cmd_process"))
        req.httpMethod = "POST"
        req.setValue(baseURL.absoluteString + "/", forHTTPHeaderField: "Referer")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "isTest", value: "false"),
            URLQueryItem(name: "goformId", value: "LOGIN"),
            URLQueryItem(name: "password", value: hash),
        ]
        req.httpBody = body.query?.data(using: .utf8)
        let resp = try await http.data(for: req)
        let respRaw = try JSONDecoder().decode([String: String].self, from: resp)
        guard respRaw["result"] == "0" else { throw ModemError.loginFailed }
    }

    private func getCmd(_ fields: [String]) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent("goform/goform_get_cmd_process"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "isTest", value: "false"),
            URLQueryItem(name: "cmd", value: fields.joined(separator: ",")),
            URLQueryItem(name: "multi_data", value: "1"),
        ]
        // Modem ZTE U50 zwraca puste stringi bez nagłówka Referer wskazującego
        // na jego panel (prosta ochrona anty-CSRF).
        var request = URLRequest(url: comps.url!)
        request.setValue(baseURL.absoluteString + "/", forHTTPHeaderField: "Referer")
        return try await http.data(for: request)
    }
}

enum ModemError: Error { case loginFailed }
