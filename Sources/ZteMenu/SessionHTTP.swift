import Foundation

/// HTTPFetching z izolowaną sesją cookie — konieczne dla logowania ZTE,
/// bo cookie `stok` z LOGIN musi wracać w kolejnych żądaniach.
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
