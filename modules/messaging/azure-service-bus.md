# Azure Service Bus — Messaging Conventions

## Overview

Azure Service Bus is a fully managed enterprise message broker supporting queues (point-to-point)
and topics/subscriptions (pub/sub) with AMQP 1.0 protocol. Use it for Azure-native architectures
needing guaranteed delivery, FIFO ordering, dead-letter handling, and transaction support. Avoid it
for simple notification fanout (use Azure Event Grid), high-throughput event streaming (use Azure
Event Hubs/Kafka), or multi-cloud portability.

## Architecture Patterns

### Queue (Point-to-Point)
```csharp
var client = new ServiceBusClient(connectionString);
var sender = client.CreateSender("orders-queue");

await sender.SendMessageAsync(new ServiceBusMessage(JsonSerializer.Serialize(order)) {
    ContentType = "application/json",
    MessageId = order.Id.ToString(),
    SessionId = order.UserId.ToString(),  // enables FIFO per user
    Subject = "order.created"
});
```

### Topic/Subscription (Pub/Sub)
```csharp
var sender = client.CreateSender("order-events");
await sender.SendMessageAsync(new ServiceBusMessage(payload) {
    Subject = "order.created",
    ApplicationProperties = { ["eventType"] = "OrderCreated", ["version"] = "1.0" }
});

// Subscriber with SQL filter
var processor = client.CreateProcessor("order-events", "notification-sub");
processor.ProcessMessageAsync += async args => {
    var order = JsonSerializer.Deserialize<Order>(args.Message.Body);
    await SendNotification(order);
    await args.CompleteMessageAsync(args.Message);
};
await processor.StartProcessingAsync();
```

### Dead-Letter Queue
```csharp
var dlqReceiver = client.CreateReceiver("orders-queue", new ServiceBusReceiverOptions {
    SubQueue = SubQueue.DeadLetter
});
var messages = await dlqReceiver.ReceiveMessagesAsync(maxMessages: 10);
```

### Anti-pattern — using Service Bus for high-throughput event streaming: Service Bus is optimized for transactional messaging (< 10K msg/sec). For millions of events per second, use Azure Event Hubs.

## Configuration

```bicep
resource namespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: 'my-sb-ns'
  location: 'eastus'
  sku: { name: 'Standard', tier: 'Standard' }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: namespace
  name: 'orders-queue'
  properties: {
    maxDeliveryCount: 5
    lockDuration: 'PT5M'
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P14D'
    enablePartitioning: false
    requiresSession: false
  }
}
```

## Dos
- Use dead-letter queues for all queues/subscriptions — poison messages need a destination.
- Use sessions for FIFO ordering — Service Bus doesn't guarantee order without sessions.
- Use `CompleteMessageAsync` explicitly — auto-complete can acknowledge before processing finishes.
- Use SQL filters on subscriptions to route messages to the right consumers.
- Set `MaxDeliveryCount` to a reasonable value (3-10) — infinite retries waste resources.
- Use managed identity (DefaultAzureCredential) instead of connection strings.
- Use batch send/receive for higher throughput.

## Don'ts
- Don't use Service Bus for high-throughput streaming (> 10K msg/sec) — use Event Hubs.
- Don't set `LockDuration` too short — messages redelivered before processing completes cause duplicates.
- Don't use connection strings in production — use managed identity.
- Don't skip dead-letter queue monitoring — unprocessed DLQ messages indicate application bugs.
- Don't send messages > 256 KB (Standard) or 100 MB (Premium) — use claim-check pattern with Blob Storage.
- Don't create too many subscriptions per topic — each has independent state and costs resources.
- Don't ignore Service Bus quotas — Premium tier provides dedicated resources; Standard shares.
