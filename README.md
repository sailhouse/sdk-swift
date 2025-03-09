# Sailhouse Swift SDK ⛵

The [Sailhouse](https://sailhouse.dev) Swift SDK provides an idiomatic Swift abstraction over the Sailhouse HTTP API for iOS, macOS, tvOS, and watchOS applications.

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/sailhouse/sdk-swift.git", from: "0.1.0")
]
```

Or add it directly in Xcode using File > Add Packages...

## Basic Usage

### Initialization

```swift
import Sailhouse

// Create a client with your API key
let client = SailhouseClient(apiKey: "your_api_key")
```

### Publishing Events

```swift
// Simple event publishing
try await client.publish(topic: "topic-name", event: ["message": "Hello World!"])

// With a Codable struct
struct MyEvent: Codable {
    let message: String
    let timestamp: Date = Date()
}

try await client.publish(topic: "topic-name", event: MyEvent(message: "Hello World!"))

// With scheduling
import Foundation

let scheduledTime = Date().addingTimeInterval(3600) // 1 hour from now
try await client.publish(
    topic: "topic-name", 
    event: MyEvent(message: "Scheduled message"), 
    sendAt: scheduledTime
)
```

### Retrieving Events

```swift
// Get events from a subscription
let events = try await client.getEvents(
    topic: "topic-name", 
    subscription: "subscription-name"
) as [Event<MyEvent>]

// Process events
for event in events {
    print("Event ID: \(event.id), Data: \(event.data)")
    
    // Acknowledge the event
    try await event.ack()
}
```

### Streaming Events

```swift
// Stream events with async sequence
let stream = client.streamEvents(
    topic: "topic-name", 
    subscription: "subscription-name"
) as AsyncStream<Event<MyEvent>>

// Process events
for await event in stream {
    print("Received event: \(event.data)")
    try await event.ack()
}

// Or with a callback
let cancellable = client.streamEvents(
    topic: "topic-name", 
    subscription: "subscription-name"
) { (event: Event<MyEvent>) in
    print("Received event: \(event.data)")
    try await event.ack()
}

// Cancel streaming when done
cancellable.cancel()
```

## Advanced Usage

### Configuring the Client

```swift
import Sailhouse
import AsyncHTTPClient

let config = SailhouseClientConfig(
    baseUrl: "https://custom-api.sailhouse.dev",
    timeout: .seconds(30)
)

let client = SailhouseClient(apiKey: "your_api_key", config: config)
```

## License

[MIT License](LICENSE) 
