import Foundation
import AsyncHTTPClient
import NIOCore
import Logging

/// Admin client for managing push subscriptions and other administrative tasks
public class AdminClient {
    /// The API key for authentication
    private let apiKey: String
    
    /// The configuration for the client
    private let config: SailhouseClientConfig
    
    /// The HTTP client for making requests
    private let httpClient: HTTPClient
    
    /// The JSON encoder for encoding requests
    private let encoder: JSONEncoder
    
    /// The JSON decoder for decoding responses
    private let decoder: JSONDecoder
    
    /// The logger for logging messages
    private let logger: Logger
    
    /// Creates a new instance of AdminClient
    /// - Parameters:
    ///   - apiKey: The API key for authentication
    ///   - config: The configuration for the client
    public init(apiKey: String, config: SailhouseClientConfig = SailhouseClientConfig()) {
        self.apiKey = apiKey
        self.config = config
        
        let httpClientConfig = HTTPClient.Configuration(
            timeout: config.timeout,
            connectionPool: .init(
                idleTimeout: .seconds(60)
            )
        )
        
        self.httpClient = HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: httpClientConfig
        )
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        self.logger = Logger(label: "dev.sailhouse.swift.admin")
    }
    
    /// Creates a push subscription
    /// - Parameters:
    ///   - topicSlug: The topic slug to create the subscription for
    ///   - subscriptionSlug: The subscription slug to create
    ///   - endpoint: The endpoint URL for push notifications
    ///   - p256dh: The p256dh key for encryption
    ///   - auth: The auth key for encryption
    /// - Returns: The created push subscription
    public func createPushSubscription(
        topicSlug: String,
        subscriptionSlug: String,
        endpoint: String,
        p256dh: String? = nil,
        auth: String? = nil
    ) async throws -> PushSubscription {
        var requestBody: [String: Any] = [
            "endpoint": endpoint
        ]
        
        if let p256dh = p256dh {
            requestBody["p256dh"] = p256dh
        }
        
        if let auth = auth {
            requestBody["auth"] = auth
        }
        
        let requestData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = try HTTPClient.Request(
            url: "\(config.baseUrl)/topics/\(topicSlug)/subscriptions/\(subscriptionSlug)/push",
            method: .POST
        )
        
        request.headers.add(name: "Authorization", value: apiKey)
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "x-source", value: "sailhouse-swift-admin")
        request.body = .data(requestData)
        
        let response = try await httpClient.execute(request: request).get()
        
        guard response.status == .ok || response.status == .created else {
            throw SailhouseError.requestFailed(
                statusCode: response.status.code,
                message: "Failed to create push subscription"
            )
        }
        
        guard let body = response.body else {
            throw SailhouseError.invalidResponse("Empty response body")
        }
        
        return try decoder.decode(
            PushSubscription.self,
            from: body.getData(at: 0, length: body.readableBytes) ?? Data()
        )
    }
    
    /// Gets a push subscription
    /// - Parameters:
    ///   - topicSlug: The topic slug
    ///   - subscriptionSlug: The subscription slug
    /// - Returns: The push subscription
    public func getPushSubscription(
        topicSlug: String,
        subscriptionSlug: String
    ) async throws -> PushSubscription {
        var request = try HTTPClient.Request(
            url: "\(config.baseUrl)/topics/\(topicSlug)/subscriptions/\(subscriptionSlug)/push",
            method: .GET
        )
        
        request.headers.add(name: "Authorization", value: apiKey)
        request.headers.add(name: "x-source", value: "sailhouse-swift-admin")
        
        let response = try await httpClient.execute(request: request).get()
        
        guard response.status == .ok else {
            throw SailhouseError.requestFailed(
                statusCode: response.status.code,
                message: "Failed to get push subscription"
            )
        }
        
        guard let body = response.body else {
            throw SailhouseError.invalidResponse("Empty response body")
        }
        
        return try decoder.decode(
            PushSubscription.self,
            from: body.getData(at: 0, length: body.readableBytes) ?? Data()
        )
    }
    
    /// Updates a push subscription
    /// - Parameters:
    ///   - topicSlug: The topic slug
    ///   - subscriptionSlug: The subscription slug
    ///   - endpoint: The new endpoint URL for push notifications
    ///   - p256dh: The new p256dh key for encryption
    ///   - auth: The new auth key for encryption
    /// - Returns: The updated push subscription
    public func updatePushSubscription(
        topicSlug: String,
        subscriptionSlug: String,
        endpoint: String? = nil,
        p256dh: String? = nil,
        auth: String? = nil
    ) async throws -> PushSubscription {
        var requestBody: [String: Any] = [:]
        
        if let endpoint = endpoint {
            requestBody["endpoint"] = endpoint
        }
        
        if let p256dh = p256dh {
            requestBody["p256dh"] = p256dh
        }
        
        if let auth = auth {
            requestBody["auth"] = auth
        }
        
        let requestData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = try HTTPClient.Request(
            url: "\(config.baseUrl)/topics/\(topicSlug)/subscriptions/\(subscriptionSlug)/push",
            method: .PUT
        )
        
        request.headers.add(name: "Authorization", value: apiKey)
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "x-source", value: "sailhouse-swift-admin")
        request.body = .data(requestData)
        
        let response = try await httpClient.execute(request: request).get()
        
        guard response.status == .ok else {
            throw SailhouseError.requestFailed(
                statusCode: response.status.code,
                message: "Failed to update push subscription"
            )
        }
        
        guard let body = response.body else {
            throw SailhouseError.invalidResponse("Empty response body")
        }
        
        return try decoder.decode(
            PushSubscription.self,
            from: body.getData(at: 0, length: body.readableBytes) ?? Data()
        )
    }
    
    /// Deletes a push subscription
    /// - Parameters:
    ///   - topicSlug: The topic slug
    ///   - subscriptionSlug: The subscription slug
    public func deletePushSubscription(
        topicSlug: String,
        subscriptionSlug: String
    ) async throws {
        var request = try HTTPClient.Request(
            url: "\(config.baseUrl)/topics/\(topicSlug)/subscriptions/\(subscriptionSlug)/push",
            method: .DELETE
        )
        
        request.headers.add(name: "Authorization", value: apiKey)
        request.headers.add(name: "x-source", value: "sailhouse-swift-admin")
        
        let response = try await httpClient.execute(request: request).get()
        
        guard response.status == .ok || response.status == .noContent else {
            throw SailhouseError.requestFailed(
                statusCode: response.status.code,
                message: "Failed to delete push subscription"
            )
        }
    }
    
    /// Closes the admin client and releases resources
    public func close() {
        try? httpClient.syncShutdown()
    }
    
    deinit {
        close()
    }
}