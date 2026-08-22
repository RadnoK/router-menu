import Foundation

/// HTTPFetching with an isolated cookie session — required for ZTE login,
/// because the `stok` cookie from LOGIN must be sent back on later requests.
public struct SessionHTTP: HTTPFetching {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = HTTPCookieStorage()
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
    }

    public func data(for request: URLRequest) async throws -> Data {
        let (data, _) = try await session.data(for: request, delegate: nil)
        return data
    }
}
