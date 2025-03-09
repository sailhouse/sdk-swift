import Foundation
import AsyncHTTPClient
import NIOCore
import NIOWebSocket
import NIOHTTP1
import NIOFoundationCompat
import NIOPosix
import Logging

/// Client for interacting with the Sailhouse API
public class SailhouseClient {
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

    /// Creates a new instance of SailhouseClient
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
            eventLoopGroupProvider: .createNew,
            configuration: httpClientConfig
        )

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.logger = Logger(label: "dev.sailhouse.swift")
    }

    /// Publishes an event to a topic
    /// - Parameters:
    ///   - topic: The topic to publish to
    ///   - event: The event data to publish
    ///   - options: The options for publishing the event
    /// - Returns: The response from the API
    public func publish<T: Encodable>(
        topic: String,
        event: T,
        options: PublishEventOptions? = nil
    ) async throws -> String {
        var requestBody: [String: Any] = ["data": event]

        if let metadata = options?.metadata {
            requestBody["metadata"] = metadata
        }

        if let sendAt = options?.sendAt {
            let formatter = ISO8601DateFormatter()
            requestBody["send_at"] = formatter.string(from: sendAt)
        }

        let requestData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = try HTTPClient.Request(
            url: "\(config.baseUrl)/topics/\(topic)/events",
            method: .POST
        )

        request.headers.add(name: "Authorization", value: apiKey)
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "x-source", value: "sailhouse-swift")
        request.body = .data(requestData)

        let response = try await httpClient.execute(request: request).get()

        guard response.status == .ok || response.status == .created else {
            throw SailhouseError.requestFailed(
                statusCode: response.status.code,
                message: "Failed to publish event"
            )
        }

        guard let body = response.body else {
            throw SailhouseError.invalidResponse("Empty response body")
        }

        let publishResponse = try decoder.decode(
            PublishEventResponse.self,
            from: body.getData(at: 0, length: body.readableBytes) ?? Data()
        )

        return publishResponse.id
    }

    /// Publishes an event to a topic with a scheduled time
    /// - Parameters:
    ///   - topic: The topic to publish to
    ///   - event: The event data to publish
    ///   - sendAt: The time to send the event
    ///   - metadata: Additional metadata for the event
    /// - Returns: The response from the API
    public func publish<T: Encodable>(
        topic: String,
        event: T,
        sendAt: Date,
        metadata: [String: String]? = nil
    ) async throws -> String {
        return try await publish(
            topic: topic,
            event: event,
            options: PublishEventOptions(metadata: metadata, sendAt: sendAt)
        )
    }

    /// Gets events from a subscription
    /// - Parameters:
    ///   - topic: The topic to get events from
    ///   - subscription: The subscription to get events from
    ///   - options: The options for getting events
    /// - Returns: The response from the API
    public func getEvents<T: Decodable>(
        topic: String,
        subscription: String,
        options: GetEventOptions? = nil
    ) async throws -> EventsResponse<T> {
        var queryItems: [URLQueryItem] = []

        if let timeWindow = options?.timeWindow {
            queryItems.append(URLQueryItem(name: "time_window", value: timeWindow))
        }

        if let queryablePath = options?.queryablePath {
            queryItems.append(URLQueryItem(name: "queryable_path", value: queryablePath))
        }

        var urlComponents = URLComponents(string: "\(config.baseUrl)/topics/\(topic)/subscriptions/\(subscription)/events")
        urlComponents?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = urlComponents?.url?.absoluteString else {
            throw SailhouseError.invalidURL
        }

        var request = try HTTPClient.Request(url: url, method: .GET)
        request.headers.add(name: "Authorization", value: apiKey)
        request.headers.add(name: "x-source", value: "sailhouse-swift")

        let response = try await httpClient.execute(request: request).get()

        guard response.status == .ok else {
            throw SailhouseError.requestFailed(
                statusCode: response.status.code,
                message: "Failed to get events"
            )
        }

        guard let body = response.body else {
            throw SailhouseError.invalidResponse("Empty response body")
        }

        let eventsResponse = try decoder.decode(
            EventsResponseDTO<T>.self,
            from: body.getData(at: 0, length: body.readableBytes) ?? Data()
        )

        return EventsResponse(
            dto: eventsResponse,
            topic: topic,
            subscription: subscription,
            client: self
        )
    }

    /// Streams events from a subscription using a callback
    /// - Parameters:
    ///   - topic: The topic to stream events from
    ///   - subscription: The subscription to stream events from
    ///   - options: The options for streaming events
    ///   - handler: The handler for processing events
    /// - Returns: A cancellable object that can be used to stop streaming
    public func streamEvents<T: Decodable>(
        topic: String,
        subscription: String,
        options: GetEventOptions? = nil,
        handler: @escaping (Event<T>) async throws -> Void
    ) -> Cancellable {
        let clientId = generateClientId()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let promise = group.next().makePromise(of: Void.self)

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                let websocketUpgrader = NIOWebSocketClientUpgrader(
                    requestKey: "sailhouse-swift-\(clientId)",
                    maxFrameSize: 1 << 24,
                    automaticErrorHandling: true
                ) { channel, _ in
                    channel.pipeline.addHandler(WebSocketHandler(
                        topic: topic,
                        subscription: subscription,
                        apiKey: self.apiKey,
                        clientId: clientId,
                        options: options,
                        handler: handler,
                        decoder: self.decoder,
                        logger: self.logger,
                        client: self
                    ))
                }

                return channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(websocketUpgrader)
                }
            }

        let url = URL(string: "wss://api.sailhouse.dev/events/stream")!
        let port = url.port ?? 443

        bootstrap.connect(host: url.host!, port: port).whenComplete { result in
            switch result {
            case .success(let channel):
                var request = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/events/stream")
                request.headers.add(name: "Host", value: url.host!)
                request.headers.add(name: "Connection", value: "upgrade")
                request.headers.add(name: "Upgrade", value: "websocket")
                request.headers.add(name: "Sec-WebSocket-Version", value: "13")
                request.headers.add(name: "Sec-WebSocket-Key", value: "sailhouse-swift-\(clientId)")
                request.headers.add(name: "Authorization", value: self.apiKey)

                channel.writeAndFlush(HTTPClientRequestPart.head(request)).whenComplete { _ in
                    channel.writeAndFlush(HTTPClientRequestPart.end(nil)).whenComplete { _ in
                        // Wait for the WebSocket connection to be established
                    }
                }
            case .failure(let error):
                promise.fail(error)
            }
        }

        return WebSocketCancellable(group: group, promise: promise)
    }

    /// Streams events from a subscription using an AsyncStream
    /// - Parameters:
    ///   - topic: The topic to stream events from
    ///   - subscription: The subscription to stream events from
    ///   - options: The options for streaming events
    /// - Returns: An AsyncStream of events
    public func streamEvents<T: Decodable>(
        topic: String,
        subscription: String,
        options: GetEventOptions? = nil
    ) -> AsyncStream<Event<T>> {
        var cancellable: Cancellable?

        return AsyncStream { continuation in
            cancellable = self.streamEvents(
                topic: topic,
                subscription: subscription,
                options: options
            ) { event in
                continuation.yield(event)
            }

            continuation.onTermination = { _ in
                cancellable?.cancel()
            }
        }
    }

    /// Acknowledges an event
    /// - Parameters:
    ///   - topic: The topic the event belongs to
    ///   - subscription: The subscription the event was retrieved from
    ///   - eventId: The ID of the event to acknowledge
    internal func ackEvent(
        topic: String,
        subscription: String,
        eventId: String
    ) async throws {
        var request = try HTTPClient.Request(
            url: "\(config.baseUrl)/topics/\(topic)/subscriptions/\(subscription)/events/\(eventId)",
            method: .POST
        )

        request.headers.add(name: "Authorization", value: apiKey)
        request.headers.add(name: "x-source", value: "sailhouse-swift")

        let response = try await httpClient.execute(request: request).get()

        guard response.status == .ok || response.status == .noContent else {
            throw SailhouseError.requestFailed(
                statusCode: response.status.code,
                message: "Failed to acknowledge event"
            )
        }
    }

    /// Closes the client and releases resources
    public func close() {
        try? httpClient.syncShutdown()
    }

    /// Generates a unique client ID
    private func generateClientId() -> String {
        return "swift-sdk-\(Date().timeIntervalSince1970)-\(Int.random(in: 0...999999))"
    }

    deinit {
        close()
    }
}

/// WebSocket handler for streaming events
private class WebSocketHandler<T: Decodable>: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame

    private let topic: String
    private let subscription: String
    private let apiKey: String
    private let clientId: String
    private let options: GetEventOptions?
    private let handler: (Event<T>) async throws -> Void
    private let decoder: JSONDecoder
    private let logger: Logger
    private let client: SailhouseClient

    init(
        topic: String,
        subscription: String,
        apiKey: String,
        clientId: String,
        options: GetEventOptions?,
        handler: @escaping (Event<T>) async throws -> Void,
        decoder: JSONDecoder,
        logger: Logger,
        client: SailhouseClient
    ) {
        self.topic = topic
        self.subscription = subscription
        self.apiKey = apiKey
        self.clientId = clientId
        self.options = options
        self.handler = handler
        self.decoder = decoder
        self.logger = logger
        self.client = client
    }

    func channelActive(context: ChannelHandlerContext) {
        var connectionMessage: [String: Any] = [
            "topic_slug": topic,
            "subscription_slug": subscription,
            "token": apiKey,
            "client_id": clientId
        ]

        if let timeWindow = options?.timeWindow {
            connectionMessage["time_window"] = timeWindow
        }

        if let queryablePath = options?.queryablePath {
            connectionMessage["queryable_path"] = queryablePath
        }

        guard let data = try? JSONSerialization.data(withJSONObject: connectionMessage),
              let text = String(data: data, encoding: .utf8) else {
            logger.error("Failed to serialize connection message")
            context.close(promise: nil)
            return
        }

        var buffer = context.channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)

        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        context.writeAndFlush(self.wrapOutboundOut(frame), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)

        switch frame.opcode {
        case .text:
            guard let data = frame.unmaskedData,
                  let text = data.getString(at: 0, length: data.readableBytes) else {
                logger.warning("Received invalid text frame")
                return
            }

            do {
                let eventDto = try decoder.decode(EventDTO<T>.self, from: Data(text.utf8))
                let event = Event(
                    dto: eventDto,
                    topic: topic,
                    subscription: subscription,
                    client: client
                )

                Task {
                    try await handler(event)
                }
            } catch {
                logger.error("Failed to decode event: \(error)")
            }
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.data)
            context.writeAndFlush(self.wrapOutboundOut(pong), promise: nil)
        case .connectionClose:
            context.close(promise: nil)
        default:
            logger.warning("Received unexpected frame type: \(frame.opcode)")
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("WebSocket error: \(error)")
        context.close(promise: nil)
    }
}

/// Protocol for cancellable operations
public protocol Cancellable {
    /// Cancels the operation
    func cancel()
}

/// WebSocket cancellable for streaming events
private class WebSocketCancellable: Cancellable {
    private let group: EventLoopGroup
    private let promise: EventLoopPromise<Void>

    init(group: EventLoopGroup, promise: EventLoopPromise<Void>) {
        self.group = group
        self.promise = promise
    }

    func cancel() {
        promise.fail(SailhouseError.cancelled)
        try? group.syncShutdownGracefully()
    }
}

/// Errors that can occur when using the Sailhouse client
public enum SailhouseError: Error {
    /// The request failed with the given status code and message
    case requestFailed(statusCode: UInt, message: String)

    /// The response was invalid
    case invalidResponse(String)

    /// The URL was invalid
    case invalidURL

    /// The operation was cancelled
    case cancelled
}
