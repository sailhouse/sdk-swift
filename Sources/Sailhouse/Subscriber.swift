import Foundation
import AsyncHTTPClient
import NIOCore
import Logging

/// Options for configuring a subscriber
public struct SubscriberOptions {
    /// The interval between polling for events (in seconds)
    public let pollingInterval: TimeInterval
    
    /// The maximum number of events to fetch per poll
    public let batchSize: Int
    
    /// Whether to automatically acknowledge events after successful processing
    public let autoAck: Bool
    
    /// The timeout for processing each event (in seconds)
    public let processingTimeout: TimeInterval
    
    /// The maximum number of retry attempts for failed event processing
    public let maxRetries: Int
    
    /// The delay between retry attempts (in seconds)
    public let retryDelay: TimeInterval
    
    /// Creates new subscriber options
    /// - Parameters:
    ///   - pollingInterval: The interval between polling for events (default: 1.0 second)
    ///   - batchSize: The maximum number of events to fetch per poll (default: 10)
    ///   - autoAck: Whether to automatically acknowledge events after successful processing (default: true)
    ///   - processingTimeout: The timeout for processing each event (default: 30.0 seconds)
    ///   - maxRetries: The maximum number of retry attempts for failed event processing (default: 3)
    ///   - retryDelay: The delay between retry attempts (default: 1.0 second)
    public init(
        pollingInterval: TimeInterval = 1.0,
        batchSize: Int = 10,
        autoAck: Bool = true,
        processingTimeout: TimeInterval = 30.0,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0
    ) {
        self.pollingInterval = pollingInterval
        self.batchSize = batchSize
        self.autoAck = autoAck
        self.processingTimeout = processingTimeout
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
}

/// A long-running subscriber for processing events continuously
public class Subscriber<T: Decodable> {
    /// The topic to subscribe to
    public let topicSlug: String
    
    /// The subscription to use
    public let subscriptionSlug: String
    
    /// The Sailhouse client instance
    private let client: SailhouseClient
    
    /// The options for this subscriber
    private let options: SubscriberOptions
    
    /// The event handler function
    private let eventHandler: (Event<T>) async throws -> Void
    
    /// The error handler function
    private let errorHandler: ((Error) -> Void)?
    
    /// Whether the subscriber is currently running
    private var isRunning: Bool = false
    
    /// The task running the subscription loop
    private var subscriptionTask: Task<Void, Never>?
    
    /// The logger for logging messages
    private let logger: Logger
    
    /// Statistics for this subscriber
    public private(set) var stats = SubscriberStats()
    
    /// Creates a new subscriber
    /// - Parameters:
    ///   - topicSlug: The topic to subscribe to
    ///   - subscriptionSlug: The subscription to use
    ///   - client: The Sailhouse client instance
    ///   - options: The options for this subscriber
    ///   - eventHandler: The function to call for each event
    ///   - errorHandler: The function to call when errors occur (optional)
    public init(
        topicSlug: String,
        subscriptionSlug: String,
        client: SailhouseClient,
        options: SubscriberOptions = SubscriberOptions(),
        eventHandler: @escaping (Event<T>) async throws -> Void,
        errorHandler: ((Error) -> Void)? = nil
    ) {
        self.topicSlug = topicSlug
        self.subscriptionSlug = subscriptionSlug
        self.client = client
        self.options = options
        self.eventHandler = eventHandler
        self.errorHandler = errorHandler
        self.logger = Logger(label: "dev.sailhouse.swift.subscriber")
    }
    
    /// Starts the subscriber
    public func start() {
        guard !isRunning else {
            logger.warning("Subscriber is already running")
            return
        }
        
        isRunning = true
        stats.startTime = Date()
        logger.info("Starting subscriber for topic: \(topicSlug), subscription: \(subscriptionSlug)")
        
        subscriptionTask = Task {
            await runSubscriptionLoop()
        }
    }
    
    /// Stops the subscriber
    public func stop() {
        guard isRunning else {
            logger.warning("Subscriber is not running")
            return
        }
        
        isRunning = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
        
        logger.info("Stopped subscriber for topic: \(topicSlug), subscription: \(subscriptionSlug)")
        logger.info("Subscriber stats: \(stats)")
    }
    
    /// The main subscription loop
    private func runSubscriptionLoop() async {
        while isRunning {
            do {
                // Get events from the subscription
                let events = try await client.getEvents(
                    topic: topicSlug,
                    subscription: subscriptionSlug
                ) as EventsResponse<T>
                
                stats.totalPolls += 1
                
                if !events.events.isEmpty {
                    logger.debug("Fetched \(events.events.count) events")
                    stats.totalEventsReceived += events.events.count
                    
                    // Process events concurrently with limited concurrency
                    await withTaskGroup(of: Void.self) { group in
                        for event in events.events {
                            group.addTask {
                                await self.processEvent(event)
                            }
                        }
                    }
                }
                
                // Wait for the polling interval before next poll
                try await Task.sleep(nanoseconds: UInt64(options.pollingInterval * 1_000_000_000))
                
            } catch {
                stats.totalErrors += 1
                logger.error("Error in subscription loop: \(error)")
                
                if let errorHandler = self.errorHandler {
                    errorHandler(error)
                }
                
                // Wait before retrying
                try? await Task.sleep(nanoseconds: UInt64(options.pollingInterval * 1_000_000_000))
            }
        }
    }
    
    /// Processes a single event with retry logic
    private func processEvent(_ event: Event<T>) async {
        var retryCount = 0
        
        while retryCount <= options.maxRetries {
            do {
                // Process the event with timeout
                try await withTimeout(options.processingTimeout) {
                    try await self.eventHandler(event)
                }
                
                // Auto-acknowledge if enabled
                if options.autoAck {
                    try await event.ack()
                    stats.totalEventsAcknowledged += 1
                }
                
                stats.totalEventsProcessed += 1
                logger.debug("Successfully processed event: \(event.id)")
                return
                
            } catch {
                retryCount += 1
                stats.totalProcessingErrors += 1
                
                logger.warning("Error processing event \(event.id) (attempt \(retryCount)/\(options.maxRetries + 1)): \(error)")
                
                if retryCount <= options.maxRetries {
                    // Wait before retrying
                    try? await Task.sleep(nanoseconds: UInt64(options.retryDelay * 1_000_000_000))
                } else {
                    logger.error("Failed to process event \(event.id) after \(options.maxRetries + 1) attempts")
                    stats.totalFailedEvents += 1
                    
                    if let errorHandler = self.errorHandler {
                        errorHandler(error)
                    }
                }
            }
        }
    }
    
    /// Whether the subscriber is currently running
    public var running: Bool {
        return isRunning
    }
}

/// Statistics for a subscriber
public struct SubscriberStats: CustomStringConvertible {
    /// When the subscriber was started
    public var startTime: Date?
    
    /// Total number of polling operations
    public var totalPolls: Int = 0
    
    /// Total number of events received
    public var totalEventsReceived: Int = 0
    
    /// Total number of events successfully processed
    public var totalEventsProcessed: Int = 0
    
    /// Total number of events acknowledged
    public var totalEventsAcknowledged: Int = 0
    
    /// Total number of events that failed processing
    public var totalFailedEvents: Int = 0
    
    /// Total number of processing errors (including retries)
    public var totalProcessingErrors: Int = 0
    
    /// Total number of general errors
    public var totalErrors: Int = 0
    
    /// The uptime of the subscriber
    public var uptime: TimeInterval? {
        guard let startTime = startTime else { return nil }
        return Date().timeIntervalSince(startTime)
    }
    
    /// Events processed per second
    public var eventsPerSecond: Double? {
        guard let uptime = uptime, uptime > 0 else { return nil }
        return Double(totalEventsProcessed) / uptime
    }
    
    public var description: String {
        let uptimeStr = uptime.map { String(format: "%.1fs", $0) } ?? "N/A"
        let epsStr = eventsPerSecond.map { String(format: "%.2f", $0) } ?? "N/A"
        
        return """
        SubscriberStats(
          uptime: \(uptimeStr),
          polls: \(totalPolls),
          received: \(totalEventsReceived),
          processed: \(totalEventsProcessed),
          acknowledged: \(totalEventsAcknowledged),
          failed: \(totalFailedEvents),
          processing_errors: \(totalProcessingErrors),
          general_errors: \(totalErrors),
          events_per_second: \(epsStr)
        )
        """
    }
}

/// Helper function to run a task with a timeout
private func withTimeout<T>(
    _ timeout: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            return try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw SubscriberError.timeout
        }
        
        guard let result = try await group.next() else {
            throw SubscriberError.timeout
        }
        
        group.cancelAll()
        return result
    }
}

/// Errors that can occur in a subscriber
public enum SubscriberError: Error {
    /// The operation timed out
    case timeout
    
    /// The subscriber is not running
    case notRunning
}

/// Extension to SailhouseClient to create subscribers
extension SailhouseClient {
    /// Creates a new subscriber for the given topic and subscription
    /// - Parameters:
    ///   - topicSlug: The topic to subscribe to
    ///   - subscriptionSlug: The subscription to use
    ///   - options: The options for the subscriber
    ///   - eventHandler: The function to call for each event
    ///   - errorHandler: The function to call when errors occur (optional)
    /// - Returns: A new subscriber instance
    public func createSubscriber<T: Decodable>(
        topicSlug: String,
        subscriptionSlug: String,
        options: SubscriberOptions = SubscriberOptions(),
        eventHandler: @escaping (Event<T>) async throws -> Void,
        errorHandler: ((Error) -> Void)? = nil
    ) -> Subscriber<T> {
        return Subscriber(
            topicSlug: topicSlug,
            subscriptionSlug: subscriptionSlug,
            client: self,
            options: options,
            eventHandler: eventHandler,
            errorHandler: errorHandler
        )
    }
}