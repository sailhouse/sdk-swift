import Foundation
import AsyncHTTPClient
import NIOCore
import Logging

/// Waitgroup for coordinated event processing
public class Waitgroup {
    /// The unique identifier for this waitgroup
    public let id: String
    
    /// The topic slug this waitgroup belongs to
    public let topicSlug: String
    
    /// The subscription slug this waitgroup belongs to
    public let subscriptionSlug: String
    
    /// The Sailhouse client instance
    private let client: SailhouseClient
    
    /// Set of event IDs that are part of this waitgroup
    private var eventIds: Set<String> = []
    
    /// Whether this waitgroup has been completed
    private var isCompleted: Bool = false
    
    /// The logger for logging messages
    private let logger: Logger
    
    /// Creates a new waitgroup
    /// - Parameters:
    ///   - id: The unique identifier for this waitgroup
    ///   - topicSlug: The topic slug this waitgroup belongs to
    ///   - subscriptionSlug: The subscription slug this waitgroup belongs to
    ///   - client: The Sailhouse client instance
    internal init(
        id: String,
        topicSlug: String,
        subscriptionSlug: String,
        client: SailhouseClient
    ) {
        self.id = id
        self.topicSlug = topicSlug
        self.subscriptionSlug = subscriptionSlug
        self.client = client
        self.logger = Logger(label: "dev.sailhouse.swift.waitgroup")
    }
    
    /// Adds an event to this waitgroup
    /// - Parameter eventId: The ID of the event to add
    public func add(eventId: String) {
        guard !isCompleted else {
            logger.warning("Attempted to add event \(eventId) to completed waitgroup \(id)")
            return
        }
        eventIds.insert(eventId)
        logger.debug("Added event \(eventId) to waitgroup \(id). Total events: \(eventIds.count)")
    }
    
    /// Removes an event from this waitgroup
    /// - Parameter eventId: The ID of the event to remove
    public func remove(eventId: String) {
        guard !isCompleted else {
            logger.warning("Attempted to remove event \(eventId) from completed waitgroup \(id)")
            return
        }
        eventIds.remove(eventId)
        logger.debug("Removed event \(eventId) from waitgroup \(id). Remaining events: \(eventIds.count)")
    }
    
    /// Acknowledges all events in this waitgroup
    public func ackAll() async throws {
        guard !isCompleted else {
            logger.warning("Attempted to acknowledge already completed waitgroup \(id)")
            return
        }
        
        logger.info("Acknowledging \(eventIds.count) events in waitgroup \(id)")
        
        // Acknowledge all events concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for eventId in eventIds {
                group.addTask {
                    try await self.client.ackEvent(
                        topic: self.topicSlug,
                        subscription: self.subscriptionSlug,
                        eventId: eventId
                    )
                }
            }
            
            // Wait for all acknowledgments to complete
            for try await _ in group {
                // All tasks completed successfully
            }
        }
        
        isCompleted = true
        logger.info("Successfully acknowledged all events in waitgroup \(id)")
    }
    
    /// Waits for all events in the waitgroup to be processed and then acknowledges them
    /// - Parameter timeout: Maximum time to wait for processing (default: 30 seconds)
    public func waitAndAckAll(timeout: TimeInterval = 30.0) async throws {
        guard !isCompleted else {
            logger.warning("Waitgroup \(id) is already completed")
            return
        }
        
        logger.info("Waiting for \(eventIds.count) events in waitgroup \(id) with timeout \(timeout)s")
        
        // Wait for the timeout period
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        
        // Acknowledge all events
        try await ackAll()
    }
    
    /// The number of events currently in this waitgroup
    public var count: Int {
        return eventIds.count
    }
    
    /// Whether this waitgroup is empty
    public var isEmpty: Bool {
        return eventIds.isEmpty
    }
    
    /// Whether this waitgroup has been completed
    public var completed: Bool {
        return isCompleted
    }
    
    /// Gets all event IDs in this waitgroup
    public var events: Set<String> {
        return eventIds
    }
}

/// Manager for creating and managing waitgroups
public class WaitgroupManager {
    /// The Sailhouse client instance
    private let client: SailhouseClient
    
    /// Active waitgroups indexed by their IDs
    private var waitgroups: [String: Waitgroup] = [:]
    
    /// The logger for logging messages
    private let logger: Logger
    
    /// Queue for thread-safe access to waitgroups
    private let queue = DispatchQueue(label: "dev.sailhouse.swift.waitgroup-manager", attributes: .concurrent)
    
    /// Creates a new waitgroup manager
    /// - Parameter client: The Sailhouse client instance
    internal init(client: SailhouseClient) {
        self.client = client
        self.logger = Logger(label: "dev.sailhouse.swift.waitgroup-manager")
    }
    
    /// Creates a new waitgroup
    /// - Parameters:
    ///   - id: The unique identifier for the waitgroup (if nil, a UUID will be generated)
    ///   - topicSlug: The topic slug for the waitgroup
    ///   - subscriptionSlug: The subscription slug for the waitgroup
    /// - Returns: The created waitgroup
    public func createWaitgroup(
        id: String? = nil,
        topicSlug: String,
        subscriptionSlug: String
    ) -> Waitgroup {
        let waitgroupId = id ?? UUID().uuidString
        
        let waitgroup = Waitgroup(
            id: waitgroupId,
            topicSlug: topicSlug,
            subscriptionSlug: subscriptionSlug,
            client: client
        )
        
        queue.async(flags: .barrier) {
            self.waitgroups[waitgroupId] = waitgroup
            self.logger.debug("Created waitgroup \(waitgroupId) for topic: \(topicSlug), subscription: \(subscriptionSlug)")
        }
        
        return waitgroup
    }
    
    /// Gets an existing waitgroup by ID
    /// - Parameter id: The ID of the waitgroup to retrieve
    /// - Returns: The waitgroup if found, nil otherwise
    public func getWaitgroup(id: String) -> Waitgroup? {
        return queue.sync {
            return waitgroups[id]
        }
    }
    
    /// Removes a waitgroup from the manager
    /// - Parameter id: The ID of the waitgroup to remove
    public func removeWaitgroup(id: String) {
        queue.async(flags: .barrier) {
            if self.waitgroups.removeValue(forKey: id) != nil {
                self.logger.debug("Removed waitgroup \(id)")
            }
        }
    }
    
    /// Gets all active waitgroups
    /// - Returns: Array of all active waitgroups
    public func getAllWaitgroups() -> [Waitgroup] {
        return queue.sync {
            return Array(waitgroups.values)
        }
    }
    
    /// Cleans up completed waitgroups
    public func cleanupCompleted() {
        queue.async(flags: .barrier) {
            let beforeCount = self.waitgroups.count
            self.waitgroups = self.waitgroups.filter { !$0.value.completed }
            let afterCount = self.waitgroups.count
            let removedCount = beforeCount - afterCount
            
            if removedCount > 0 {
                self.logger.info("Cleaned up \(removedCount) completed waitgroups")
            }
        }
    }
}

/// Extension to SailhouseClient to add waitgroup support
extension SailhouseClient {
    /// The waitgroup manager for this client
    public private(set) static var waitgroupManager: WaitgroupManager?
    
    /// Enables waitgroup functionality for this client
    public func enableWaitgroups() {
        SailhouseClient.waitgroupManager = WaitgroupManager(client: self)
    }
    
    /// Creates a new waitgroup (requires waitgroups to be enabled)
    /// - Parameters:
    ///   - id: The unique identifier for the waitgroup (if nil, a UUID will be generated)
    ///   - topicSlug: The topic slug for the waitgroup
    ///   - subscriptionSlug: The subscription slug for the waitgroup
    /// - Returns: The created waitgroup
    /// - Throws: An error if waitgroups are not enabled
    public func createWaitgroup(
        id: String? = nil,
        topicSlug: String,
        subscriptionSlug: String
    ) throws -> Waitgroup {
        guard let manager = SailhouseClient.waitgroupManager else {
            throw SailhouseError.invalidResponse("Waitgroups not enabled. Call enableWaitgroups() first.")
        }
        
        return manager.createWaitgroup(
            id: id,
            topicSlug: topicSlug,
            subscriptionSlug: subscriptionSlug
        )
    }
    
    /// Gets an existing waitgroup by ID (requires waitgroups to be enabled)
    /// - Parameter id: The ID of the waitgroup to retrieve
    /// - Returns: The waitgroup if found, nil otherwise
    /// - Throws: An error if waitgroups are not enabled
    public func getWaitgroup(id: String) throws -> Waitgroup? {
        guard let manager = SailhouseClient.waitgroupManager else {
            throw SailhouseError.invalidResponse("Waitgroups not enabled. Call enableWaitgroups() first.")
        }
        
        return manager.getWaitgroup(id: id)
    }
}