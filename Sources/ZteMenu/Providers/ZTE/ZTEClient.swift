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

public struct ZTEClient: ModemDriving {
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
        return Self.parse(raw)
    }

    /// v1 probe: plain reachability. A HEAD against the panel with the same
    /// 3-second budget the old `URLReachability` used.
    func probe() async -> Bool {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        return (try? await http.data(for: request)) != nil
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
        // The ZTE U50 modem returns empty strings without a Referer header
        // pointing at its own panel (a simple anti-CSRF guard).
        var request = URLRequest(url: comps.url!)
        request.setValue(baseURL.absoluteString + "/", forHTTPHeaderField: "Referer")
        return try await http.data(for: request)
    }
}

enum ModemError: Error { case loginFailed }

extension ZTEClient {
    /// Maps the modem's goform key/value response onto the neutral model.
    /// Empty strings mean "field absent" on this firmware.
    static func parse(_ raw: [String: String]) -> ModemData {
        func str(_ key: String) -> String? {
            guard let v = raw[key], !v.isEmpty else { return nil }
            return v
        }
        return ModemData(
            batteryPercent: str("battery_value").flatMap { Int($0) },
            isCharging: raw["battery_charging"] == "1",
            signalBars: str("signalbar").flatMap { Int($0) } ?? 0,
            networkType: str("network_type") ?? "",
            provider: str("network_provider"),
            rsrp: str("Z5g_rsrp").flatMap { Int($0) },
            sinr: str("Z5g_SINR").flatMap { Double($0) },
            isOnline: raw["ppp_status"] == "ppp_connected",
            rxSpeed: str("realtime_rx_thrpt").flatMap { Int($0) },
            txSpeed: str("realtime_tx_thrpt").flatMap { Int($0) },
            sessionRx: str("realtime_rx_bytes").flatMap { Int($0) },
            sessionTx: str("realtime_tx_bytes").flatMap { Int($0) },
            totalRx: str("total_rx_bytes").flatMap { Int($0) },
            totalTx: str("total_tx_bytes").flatMap { Int($0) },
            monthlyRx: str("monthly_rx_bytes").flatMap { Int($0) },
            monthlyTx: str("monthly_tx_bytes").flatMap { Int($0) },
            sessionUptime: str("realtime_time").flatMap { Int($0) },
            monthlyUptime: str("monthly_time").flatMap { Int($0) }
        )
    }
}
