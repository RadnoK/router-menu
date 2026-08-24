import Foundation

/// Driver for stock Asuswrt routers (and Asuswrt-Merlin): authenticates via
/// `login.cgi` (base64 credentials → `asus_token`), then reads state through
/// `appGet.cgi` hooks. Field shapes vary between firmware builds, so every
/// parse is defensive — an unknown shape degrades to nil, never crashes.
struct AsusClient: ModemDriving {
    let baseURL: URL
    let username: String
    let password: String?
    let http: any HTTPFetching
    /// Injected so tests don't sleep; production waits between the two
    /// traffic-counter samples that yield the transfer speeds.
    let pause: @Sendable (_ seconds: Double) async -> Void

    static let speedSampleInterval: Double = 1.0

    init(baseURL: URL,
         username: String,
         password: String?,
         http: any HTTPFetching = URLSession.shared,
         pause: @escaping @Sendable (_ seconds: Double) async -> Void = { seconds in
             try? await Task.sleep(for: .seconds(seconds))
         }) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.http = http
        self.pause = pause
    }

    func fetch() async throws -> ModemData {
        let token = try await login()
        let first = try await appGet(
            "nvram_get(wan0_state_t);nvram_get(wan0_proto);uptime();netdev(appobj)",
            token: token)
        await pause(Self.speedSampleInterval)
        let second = try await appGet("netdev(appobj)", token: token)
        return Self.parse(first: first, second: second, interval: Self.speedSampleInterval)
    }

    /// Fingerprint, not mere reachability: only a device serving the ASUS
    /// login page counts as "this profile's router".
    func probe() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("Main_Login.asp"))
        request.timeoutInterval = 3
        guard let data = try? await http.data(for: request),
              let body = String(data: data, encoding: .utf8) else { return false }
        return body.contains("ASUS")
    }

    // MARK: Protocol steps

    /// Newer Asuswrt firmware gates the JSON login/data API on an
    /// asusrouter-style user agent — with a browser-like UA, `login.cgi`
    /// answers with the HTML redirect instead of JSON (verified live:
    /// default UA → `<script>parent.location.href='/Main_Login.asp'…`,
    /// this UA → `{"error_status":…}`). Same value the asusrouter /
    /// Home Assistant integrations ship.
    static let userAgent = "asusrouter--DUTUtil-"

    private func login() async throws -> String {
        guard let password else { throw ModemError.loginFailed }
        var request = URLRequest(url: baseURL.appendingPathComponent("login.cgi"))
        request.httpMethod = "POST"
        // The firmware rejects login.cgi calls that don't come "from" its
        // own login page.
        request.setValue(baseURL.absoluteString + "/Main_Login.asp",
                         forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
        request.httpBody = Data("login_authorization=\(credentials)".utf8)
        let data = try await http.data(for: request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["asus_token"] as? String, !token.isEmpty else {
            throw ModemError.loginFailed
        }
        return token
    }

    private func appGet(_ hooks: String, token: String) async throws -> [String: Any] {
        var components = URLComponents(url: baseURL.appendingPathComponent("appGet.cgi"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "hook", value: hooks)]
        var request = URLRequest(url: components.url!)
        // Sent explicitly rather than relying on cookie storage, so the
        // driver works with any HTTPFetching.
        request.setValue("asus_token=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let data = try await http.data(for: request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // An expired session answers with the login-redirect HTML.
            throw ModemError.appGetNotJSON
        }
        return object
    }

    // MARK: Mapping

    /// Internal so the fixture tests can drive it directly if needed.
    static func parse(first: [String: Any], second: [String: Any],
                      interval: Double) -> ModemData {
        func hex(_ object: [String: Any], _ key: String) -> Int? {
            guard let netdev = object["netdev"] as? [String: Any],
                  let raw = netdev[key] as? String,
                  raw.lowercased().hasPrefix("0x"),
                  let value = Int(raw.dropFirst(2), radix: 16) else { return nil }
            return value
        }
        func speed(_ old: Int?, _ new: Int?) -> Int? {
            guard let old, let new, new >= old, interval > 0 else { return nil }
            return Int(Double(new - old) / interval)
        }

        let uptime: Int? = (first["uptime"] as? String).flatMap { raw in
            // "Mon, 24 Aug 2026 21:40:12 +0200(1234567 secs since boot)"
            guard let range = raw.range(of: " secs", options: []) else { return nil }
            let head = raw[..<range.lowerBound]
            let digits = head.reversed().prefix { $0.isNumber }
            guard !digits.isEmpty else { return nil }
            return Int(String(digits.reversed()))
        }

        let proto = (first["wan0_proto"] as? String) ?? ""
        return ModemData(
            batteryPercent: nil,
            isCharging: false,
            signalBars: 0,
            networkType: proto.uppercased(),
            provider: nil,
            rsrp: nil,
            sinr: nil,
            isOnline: (first["wan0_state_t"] as? String) == "2",
            rxSpeed: speed(hex(first, "INTERNET_rx"), hex(second, "INTERNET_rx")),
            txSpeed: speed(hex(first, "INTERNET_tx"), hex(second, "INTERNET_tx")),
            sessionRx: nil,
            sessionTx: nil,
            totalRx: hex(second, "INTERNET_rx"),
            totalTx: hex(second, "INTERNET_tx"),
            monthlyRx: nil,
            monthlyTx: nil,
            sessionUptime: uptime,
            monthlyUptime: nil
        )
    }
}

extension ModemError {
    /// The session died between login and appGet — surfaces as
    /// `.unreachable` in the store, which is accurate: the panel stopped
    /// answering usefully mid-conversation.
    static var appGetNotJSON: Error { NSError(domain: "AsusClient.appGet", code: 1) }
}
