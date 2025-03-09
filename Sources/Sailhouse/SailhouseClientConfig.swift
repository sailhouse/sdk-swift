import Foundation
import AsyncHTTPClient

/// Configuration for the Sailhouse client
public struct SailhouseClientConfig {
    /// The base URL of the Sailhouse API
    public let baseUrl: String

    /// The timeout for HTTP requests
    public let timeout: HTTPClient.Configuration.Timeout

    /// Creates a new instance of SailhouseClientConfig
    /// - Parameters:
    ///   - baseUrl: The base URL of the Sailhouse API
    ///   - timeout: The timeout for HTTP requests
    public init(
        baseUrl: String = "https://api.sailhouse.dev",
        timeout: HTTPClient.Configuration.Timeout = .seconds(30)
    ) {
        self.baseUrl = baseUrl
        self.timeout = timeout
    }
}
