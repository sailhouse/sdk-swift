import Foundation

/// Options for publishing an event
public struct PublishEventOptions {
    /// Additional metadata for the event
    public let metadata: [String: String]?

    /// The time to send the event
    public let sendAt: Date?

    /// Creates a new instance of PublishEventOptions
    /// - Parameters:
    ///   - metadata: Additional metadata for the event
    ///   - sendAt: The time to send the event
    public init(metadata: [String: String]? = nil, sendAt: Date? = nil) {
        self.metadata = metadata
        self.sendAt = sendAt
    }
}

/// Options for retrieving events
public struct GetEventOptions {
    /// The time window to retrieve events from
    public let timeWindow: String?

    /// The path to query events by
    public let queryablePath: String?

    /// Creates a new instance of GetEventOptions
    /// - Parameters:
    ///   - timeWindow: The time window to retrieve events from (e.g. "30s", "5m", "1h")
    ///   - queryablePath: The path to query events by
    public init(timeWindow: String? = nil, queryablePath: String? = nil) {
        self.timeWindow = timeWindow
        self.queryablePath = queryablePath
    }
}

/// Response from the Sailhouse API when publishing an event
internal struct PublishEventResponse: Decodable {
    /// The unique identifier of the published event
    let id: String
}

/// Internal representation of an event from the API
internal struct EventDTO<T: Decodable>: Decodable {
    /// The unique identifier of the event
    let id: String

    /// The data payload of the event
    let data: T

    /// The value that can be queried
    let queryableValue: String

    /// The timestamp when the event was created
    let timestamp: String
}

/// Internal representation of events response from the API
internal struct EventsResponseDTO<T: Decodable>: Decodable {
    /// The list of events
    let events: [EventDTO<T>]

    /// The offset for pagination
    let offset: Int

    /// The limit for pagination
    let limit: Int
}

/// Response from the Sailhouse API when retrieving events
public struct EventsResponse<T: Decodable> {
    /// The list of events
    public let events: [Event<T>]

    /// The offset for pagination
    public let offset: Int

    /// The limit for pagination
    public let limit: Int

    /// Creates a new instance of EventsResponse from a DTO
    /// - Parameters:
    ///   - dto: The DTO to create the response from
    ///   - topic: The topic the events belong to
    ///   - subscription: The subscription the events were retrieved from
    ///   - client: The Sailhouse client instance
    internal init(
        dto: EventsResponseDTO<T>,
        topic: String,
        subscription: String,
        client: SailhouseClient
    ) {
        self.events = dto.events.map { eventDto in
            Event(
                dto: eventDto,
                topic: topic,
                subscription: subscription,
                client: client
            )
        }
        self.offset = dto.offset
        self.limit = dto.limit
    }
}

/// Represents an event in the Sailhouse system
public struct Event<T: Decodable> {
    /// The unique identifier of the event
    public let id: String

    /// The data payload of the event
    public let data: T

    /// The value that can be queried
    public let queryableValue: String

    /// The timestamp when the event was created
    public let timestamp: String

    /// The topic the event belongs to
    private let topic: String

    /// The subscription the event was retrieved from
    private let subscription: String

    /// The Sailhouse client instance
    private let client: SailhouseClient

    /// Creates a new instance of Event from a DTO
    /// - Parameters:
    ///   - dto: The DTO to create the event from
    ///   - topic: The topic the event belongs to
    ///   - subscription: The subscription the event was retrieved from
    ///   - client: The Sailhouse client instance
    internal init(
        dto: EventDTO<T>,
        topic: String,
        subscription: String,
        client: SailhouseClient
    ) {
        self.id = dto.id
        self.data = dto.data
        self.queryableValue = dto.queryableValue
        self.timestamp = dto.timestamp
        self.topic = topic
        self.subscription = subscription
        self.client = client
    }

    /// Acknowledges the event
    /// - Throws: An error if the acknowledgement fails
    public func ack() async throws {
        try await client.ackEvent(topic: topic, subscription: subscription, eventId: id)
    }
}
