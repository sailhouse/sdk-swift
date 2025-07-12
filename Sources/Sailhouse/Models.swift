import Foundation

/// Options for publishing an event
public struct PublishEventOptions {
    /// Additional metadata for the event
    public let metadata: [String: Any]?

    /// The time to send the event
    public let sendAt: Date?

    /// Creates a new instance of PublishEventOptions
    /// - Parameters:
    ///   - metadata: Additional metadata for the event
    ///   - sendAt: The time to send the event
    public init(metadata: [String: Any]? = nil, sendAt: Date? = nil) {
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

    /// Additional metadata for the event
    let metadata: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case id, data, queryableValue, timestamp, metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        data = try container.decode(T.self, forKey: .data)
        queryableValue = try container.decode(String.self, forKey: .queryableValue)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        
        // Decode metadata as optional dictionary
        if container.contains(.metadata) {
            do {
                if try !container.decodeNil(forKey: .metadata) {
                    // Decode metadata as a nested container and extract values
                    let metadataContainer = try container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .metadata)
                    var metadataDict: [String: Any] = [:]
                    
                    for key in metadataContainer.allKeys {
                        if let stringValue = try? metadataContainer.decode(String.self, forKey: key) {
                            metadataDict[key.stringValue] = stringValue
                        } else if let intValue = try? metadataContainer.decode(Int.self, forKey: key) {
                            metadataDict[key.stringValue] = intValue
                        } else if let doubleValue = try? metadataContainer.decode(Double.self, forKey: key) {
                            metadataDict[key.stringValue] = doubleValue
                        } else if let boolValue = try? metadataContainer.decode(Bool.self, forKey: key) {
                            metadataDict[key.stringValue] = boolValue
                        }
                    }
                    metadata = metadataDict.isEmpty ? nil : metadataDict
                } else {
                    metadata = nil
                }
            } catch {
                metadata = nil
            }
        } else {
            metadata = nil
        }
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
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

    /// Additional metadata for the event
    public let metadata: [String: Any]?

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
        self.metadata = dto.metadata
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
