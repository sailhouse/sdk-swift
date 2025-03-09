import Foundation

/// Examples of how to use the Sailhouse Swift SDK
public enum Examples {
    /// Example of publishing an event
    public static func publishExample() async throws {
        // Create a client
        let client = SailhouseClient(apiKey: "your-api-key")

        // Define an event type
        struct MyEvent: Codable {
            let message: String
            let timestamp: Date
        }

        // Publish an event
        let eventId = try await client.publish(
            topic: "my-topic",
            event: MyEvent(message: "Hello, World!", timestamp: Date())
        )
        print("Published event with ID: \(eventId)")

        // Publish with metadata
        let eventWithMetadataId = try await client.publish(
            topic: "my-topic",
            event: MyEvent(message: "Hello with metadata", timestamp: Date()),
            options: PublishEventOptions(metadata: ["source": "swift-sdk-example"])
        )
        print("Published event with metadata, ID: \(eventWithMetadataId)")

        // Publish a scheduled event
        let scheduledTime = Date().addingTimeInterval(3600) // 1 hour from now
        let scheduledEventId = try await client.publish(
            topic: "my-topic",
            event: MyEvent(message: "Scheduled message", timestamp: Date()),
            sendAt: scheduledTime
        )
        print("Scheduled event with ID: \(scheduledEventId)")

        // Close the client when done
        client.close()
    }

    /// Example of retrieving events
    public static func getEventsExample() async throws {
        // Create a client
        let client = SailhouseClient(apiKey: "your-api-key")

        // Define an event type
        struct MyEvent: Codable {
            let message: String
            let timestamp: Date
        }

        // Get events
        let events = try await client.getEvents(
            topic: "my-topic",
            subscription: "my-subscription"
        ) as EventsResponse<MyEvent>

        print("Retrieved \(events.events.count) events")

        for event in events.events {
            print("Event ID: \(event.id), Message: \(event.data.message)")
            try await event.ack()
        }

        // Get events with options
        let eventsWithOptions = try await client.getEvents(
            topic: "my-topic",
            subscription: "my-subscription",
            options: GetEventOptions(timeWindow: "5m", queryablePath: "message")
        ) as EventsResponse<MyEvent>

        print("Retrieved \(eventsWithOptions.events.count) events with options")

        // Close the client when done
        client.close()
    }

    /// Example of streaming events
    public static func streamEventsExample() async throws {
        // Create a client
        let client = SailhouseClient(apiKey: "your-api-key")

        // Define an event type
        struct MyEvent: Codable {
            let message: String
            let timestamp: Date
        }

        // Stream events with AsyncStream
        let stream = client.streamEvents(
            topic: "my-topic",
            subscription: "my-subscription"
        ) as AsyncStream<Event<MyEvent>>

        // Process events with a task
        let task = Task {
            for await event in stream {
                print("Received event: \(event.data.message)")
                try await event.ack()
            }
        }

        // Cancel the task after some time
        try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
        task.cancel()

        // Stream events with callback
        let cancellable = client.streamEvents(
            topic: "my-topic",
            subscription: "my-subscription"
        ) { (event: Event<MyEvent>) in
            print("Received event via callback: \(event.data.message)")
            try await event.ack()
        }

        // Cancel streaming after some time
        try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
        cancellable.cancel()

        // Close the client when done
        client.close()
    }
}
