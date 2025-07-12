import XCTest
import AsyncHTTPClient
@testable import Sailhouse

final class SailhouseTests: XCTestCase {
    func testClientInitialization() {
        let client = SailhouseClient(apiKey: "test-api-key")
        XCTAssertNotNil(client)
    }

    func testClientWithCustomConfig() {
        let customConfig = SailhouseClientConfig(
            baseUrl: "https://test.sailhouse.dev",
            timeout: HTTPClient.Configuration.Timeout(connect: .seconds(10), read: .seconds(20))
        )
        let client = SailhouseClient(apiKey: "test-api-key", config: customConfig)
        XCTAssertNotNil(client)
    }

    // Example of how to use the SDK (not actually run in tests)
    func exampleUsage() async throws {
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

        // Publish a scheduled event
        let scheduledTime = Date().addingTimeInterval(3600) // 1 hour from now
        let scheduledEventId = try await client.publish(
            topic: "my-topic",
            event: MyEvent(message: "Scheduled message", timestamp: Date()),
            sendAt: scheduledTime
        )
        print("Scheduled event with ID: \(scheduledEventId)")

        // Get events
        let events = try await client.getEvents(
            topic: "my-topic",
            subscription: "my-subscription"
        ) as EventsResponse<MyEvent>

        for event in events.events {
            print("Event ID: \(event.id), Message: \(event.data.message)")
            if let metadata = event.metadata {
                print("Event metadata: \(metadata)")
            }
            try await event.ack()
        }

        // Stream events with AsyncStream
        let stream = client.streamEvents(
            topic: "my-topic",
            subscription: "my-subscription"
        ) as AsyncStream<Event<MyEvent>>

        for await event in stream {
            print("Received event: \(event.data.message)")
            if let metadata = event.metadata {
                print("Event metadata: \(metadata)")
            }
            try await event.ack()
        }

        // Stream events with callback
        let cancellable = client.streamEvents(
            topic: "my-topic",
            subscription: "my-subscription"
        ) { (event: Event<MyEvent>) in
            print("Received event: \(event.data.message)")
            if let metadata = event.metadata {
                print("Event metadata: \(metadata)")
            }
            try await event.ack()
        }

        // Cancel streaming after some time
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            cancellable.cancel()
        }

        // Close the client when done
        client.close()
    }
}
