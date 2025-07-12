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
            options: PublishEventOptions(metadata: [
                "source": "swift-sdk-example",
                "version": "1.0",
                "userId": 12345,
                "isTest": true
            ])
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
            if let metadata = event.metadata {
                print("Event metadata: \(metadata)")
            }
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
                if let metadata = event.metadata {
                    print("Event metadata: \(metadata)")
                }
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
            if let metadata = event.metadata {
                print("Event metadata: \(metadata)")
            }
            try await event.ack()
        }

        // Cancel streaming after some time
        try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
        cancellable.cancel()

        // Close the client when done
        client.close()
    }

    /// Example of using the AdminClient for push subscriptions
    public static func adminClientExample() async throws {
        // Create an admin client
        let adminClient = AdminClient(apiKey: "your-admin-api-key")
        
        // Create a push subscription
        let pushSubscription = try await adminClient.createPushSubscription(
            topicSlug: "my-topic",
            subscriptionSlug: "my-subscription",
            endpoint: "https://fcm.googleapis.com/fcm/send/...",
            p256dh: "your-p256dh-key",
            auth: "your-auth-key"
        )
        print("Created push subscription with ID: \(pushSubscription.id)")
        
        // Get the push subscription
        let retrievedSubscription = try await adminClient.getPushSubscription(
            topicSlug: "my-topic",
            subscriptionSlug: "my-subscription"
        )
        print("Retrieved push subscription: \(retrievedSubscription.endpoint)")
        
        // Update the push subscription
        let updatedSubscription = try await adminClient.updatePushSubscription(
            topicSlug: "my-topic",
            subscriptionSlug: "my-subscription",
            endpoint: "https://fcm.googleapis.com/fcm/send/updated-endpoint"
        )
        print("Updated push subscription endpoint: \(updatedSubscription.endpoint)")
        
        // Delete the push subscription
        try await adminClient.deletePushSubscription(
            topicSlug: "my-topic",
            subscriptionSlug: "my-subscription"
        )
        print("Deleted push subscription")
        
        // Close the admin client when done
        adminClient.close()
    }

    /// Example of using waitgroups for coordinated event processing
    public static func waitgroupExample() async throws {
        // Create a client
        let client = SailhouseClient(apiKey: "your-api-key")
        
        // Enable waitgroups functionality
        client.enableWaitgroups()
        
        // Define an event type
        struct MyEvent: Codable {
            let message: String
            let timestamp: Date
        }
        
        // Create a waitgroup for coordinated processing
        let waitgroup = try client.createWaitgroup(
            id: "processing-batch-1",
            topicSlug: "my-topic",
            subscriptionSlug: "my-subscription"
        )
        
        // Get events and add them to the waitgroup
        let events = try await client.getEvents(
            topic: "my-topic",
            subscription: "my-subscription"
        ) as EventsResponse<MyEvent>
        
        print("Processing \(events.events.count) events in waitgroup")
        
        // Add all events to the waitgroup
        for event in events.events {
            waitgroup.add(eventId: event.id)
            
            // Process the event
            print("Processing event: \(event.data.message)")
            if let metadata = event.metadata {
                print("Event metadata: \(metadata)")
            }
        }
        
        print("Added \(waitgroup.count) events to waitgroup \(waitgroup.id)")
        
        // Wait for processing to complete and acknowledge all events at once
        try await waitgroup.waitAndAckAll(timeout: 30.0)
        
        print("All events in waitgroup \(waitgroup.id) have been processed and acknowledged")
        
        // Alternative: manually acknowledge all events
        let anotherWaitgroup = try client.createWaitgroup(
            topicSlug: "my-topic",
            subscriptionSlug: "my-subscription"
        )
        
        // Add some events
        anotherWaitgroup.add(eventId: "event-1")
        anotherWaitgroup.add(eventId: "event-2")
        anotherWaitgroup.add(eventId: "event-3")
        
        // Acknowledge all events immediately
        try await anotherWaitgroup.ackAll()
        
        // Close the client when done
        client.close()
    }

    /// Example of using a long-running subscriber for continuous event processing
    public static func subscriberExample() async throws {
        // Create a client
        let client = SailhouseClient(apiKey: "your-api-key")
        
        // Define an event type
        struct MyEvent: Codable {
            let message: String
            let timestamp: Date
        }
        
        // Configure subscriber options
        let options = SubscriberOptions(
            pollingInterval: 2.0,  // Poll every 2 seconds
            batchSize: 5,          // Process up to 5 events per batch
            autoAck: true,         // Automatically acknowledge events
            processingTimeout: 10.0, // 10 second timeout per event
            maxRetries: 2,         // Retry failed events twice
            retryDelay: 1.0        // Wait 1 second between retries
        )
        
        // Create a subscriber with event and error handlers
        let subscriber: Subscriber<MyEvent> = client.createSubscriber(
            topicSlug: "my-topic",
            subscriptionSlug: "my-subscription",
            options: options,
            eventHandler: { event in
                // Process the event
                print("Processing event: \(event.id) - \(event.data.message)")
                
                if let metadata = event.metadata {
                    print("Event metadata: \(metadata)")
                }
                
                // Simulate some processing work
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                print("Finished processing event: \(event.id)")
            },
            errorHandler: { error in
                print("Subscriber error: \(error)")
            }
        )
        
        // Start the subscriber
        subscriber.start()
        print("Subscriber started. Running for 30 seconds...")
        
        // Let it run for a while
        try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
        
        // Print statistics
        print("Subscriber statistics:")
        print(subscriber.stats)
        
        // Stop the subscriber
        subscriber.stop()
        
        // Example of a fire-and-forget subscriber
        let backgroundSubscriber: Subscriber<MyEvent> = client.createSubscriber(
            topicSlug: "background-topic",
            subscriptionSlug: "background-subscription",
            options: SubscriberOptions(pollingInterval: 5.0),
            eventHandler: { event in
                print("Background processing: \(event.data.message)")
            },
            errorHandler: nil
        )
        
        // Start background subscriber
        backgroundSubscriber.start()
        
        // In a real application, you might keep this running indefinitely
        // For the example, we'll stop it after a brief period
        try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
        backgroundSubscriber.stop()
        
        // Close the client when done
        client.close()
    }

    /// Example of using HMAC push subscription verification
    public static func pushVerificationExample() throws {
        // Create a push verification instance with a secret key
        let verification = PushVerification(secretKey: "your-webhook-secret-key")
        
        // Example 1: Verify a webhook payload directly
        let payload = """
        {
            "event": {
                "id": "event-123",
                "topic": "my-topic",
                "data": {"message": "Hello, World!"},
                "timestamp": "2023-10-01T12:00:00Z"
            }
        }
        """
        
        // Compute the expected signature
        let expectedSignature = try verification.computeSignature(payload: payload)
        print("Expected signature: \(expectedSignature)")
        
        // Verify the signature
        let isValid = verification.verifySignature(payload: payload, signature: expectedSignature)
        print("Signature is valid: \(isValid)")
        
        // Example 2: Verify a webhook request with headers
        let headers = [
            "x-sailhouse-signature": "sha256=\(expectedSignature)",
            "content-type": "application/json"
        ]
        
        let webhookIsValid = verification.verifyWebhook(
            headers: headers,
            body: payload
        )
        print("Webhook is valid: \(webhookIsValid)")
        
        // Example 3: Using environment variable
        if let envVerification = PushVerification.fromEnvironment() {
            print("Loaded verification from environment variable")
            
            let envIsValid = envVerification.verifySignature(
                payload: payload,
                signature: expectedSignature
            )
            print("Environment verification result: \(envIsValid)")
        } else {
            print("No webhook secret found in environment variables")
        }
        
        // Example 4: Using middleware for webhook handling
        let middleware = WebhookVerificationMiddleware(verification: verification)
        
        let handlerCalled = middleware.verifyAndHandle(
            headers: headers,
            body: payload
        ) { verifiedPayload in
            print("Webhook verified and handling payload: \(verifiedPayload)")
            
            // Parse the webhook payload
            if let data = verifiedPayload.data(using: .utf8) {
                // Process the webhook data here
                print("Processing webhook data of \(data.count) bytes")
            }
        }
        
        print("Middleware handler was called: \(handlerCalled)")
        
        // Example 5: Demonstrate signature verification failure
        let invalidSignature = "invalid-signature"
        let invalidResult = verification.verifySignature(
            payload: payload,
            signature: invalidSignature
        )
        print("Invalid signature verification result: \(invalidResult)")
    }
}
