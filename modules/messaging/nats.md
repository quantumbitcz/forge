# NATS — Messaging Conventions

## Overview

NATS is a lightweight, cloud-native messaging system with a sub-millisecond core and optional JetStream
persistence. Use NATS core for ephemeral pub/sub and request-reply; use JetStream when you need durability,
consumer replay, or at-least-once delivery. Its operational simplicity makes it attractive for microservices
and edge/IoT deployments.

## Architecture Patterns

### Subject-Based Messaging with Wildcards

```
# Hierarchy: {domain}.{entity}.{action}
orders.order.created
orders.order.updated
payments.transaction.completed
telemetry.sensor.*.temperature     # * matches exactly one token
audit.>                            # > matches one or more tokens (tail wildcard)
```

```go
// Subscribe with wildcards
nc.Subscribe("orders.*.*", func(msg *nats.Msg) {
    // Receives: orders.order.created, orders.item.added, etc.
})

nc.Subscribe("telemetry.>", func(msg *nats.Msg) {
    // Receives everything under telemetry
})
```

### JetStream — Streams and Consumers

```go
js, _ := nc.JetStream()

// Create a stream (persists messages matching subjects)
js.AddStream(&nats.StreamConfig{
    Name:       "ORDERS",
    Subjects:   []string{"orders.*.*"},
    MaxAge:     7 * 24 * time.Hour,     // 7-day retention
    Storage:    nats.FileStorage,       // Durable; use MemoryStorage only for caches
    Replicas:   3,                      // HA — must match cluster size or be <= it
    Retention:  nats.LimitsPolicy,      // LimitsPolicy | WorkQueuePolicy | InterestPolicy
})

// Push consumer (broker delivers to subject)
js.Subscribe("orders.*.*", handler, nats.Durable("orders-processor"), nats.AckExplicit())

// Pull consumer (application asks for batches — preferred for throughput control)
sub, _ := js.PullSubscribe("orders.*.*", "orders-processor")
msgs, _ := sub.Fetch(50, nats.MaxWait(5*time.Second))
for _, msg := range msgs {
    process(msg)
    msg.Ack()
}
```

### At-Least-Once vs Exactly-Once

```go
// At-least-once: ack after processing; redelivered on crash before ack
msg.Ack()

// Exactly-once: double-ack with MsgID deduplication (JetStream dedup window)
js.AddStream(&nats.StreamConfig{
    Name:    "PAYMENTS",
    Duplicates: 2 * time.Minute,  // Dedup window
})

// Publisher sets message ID; JetStream drops duplicates within the window
js.Publish("payments.transaction.completed", data,
    nats.MsgId(idempotencyKey))

// Consumer double-ack (in-progress + terminal)
msg.InProgress()   // extend ack timeout while processing
// ... do work ...
msg.Term()         // or msg.Ack() on success, msg.Nak() on retryable failure
```

### Request-Reply Pattern

```go
// Replier — subscribe on a fixed subject
nc.Subscribe("math.double", func(msg *nats.Msg) {
    val := parseDouble(msg.Data)
    msg.Respond(encodeDouble(val * 2))
})

// Requester — sends to subject, NATS generates a reply-to inbox
response, err := nc.Request("math.double", encode(21.0), 2*time.Second)
if errors.Is(err, nats.ErrNoResponders) {
    // No service registered — handle gracefully (no blocking wait)
}
```

### Queue Groups for Load Balancing

```go
// All subscribers in the same queue group receive each message once (round-robin)
nc.QueueSubscribe("orders.order.created", "order-processors", func(msg *nats.Msg) {
    processOrder(msg)
})
// Scale horizontally: run N instances with the same group name
```

### Key-Value Store

```go
kv, _ := js.CreateKeyValue(&nats.KeyValueConfig{
    Bucket:  "feature-flags",
    TTL:     24 * time.Hour,
    History: 5,              // Keep last 5 revisions per key
    Storage: nats.FileStorage,
})

kv.Put("dark-mode", []byte("true"))
entry, _ := kv.Get("dark-mode")

// Watch for changes (real-time config push)
watcher, _ := kv.Watch("*")
for entry := range watcher.Updates() { applyConfig(entry) }
```

### Object Store

```go
obs, _ := js.CreateObjectStore(&nats.ObjectStoreConfig{
    Bucket:  "model-artifacts",
    MaxAge:  30 * 24 * time.Hour,
})
obs.PutFile("model-v3.bin", "/tmp/model-v3.bin")
obs.GetFile("model-v3.bin", "/tmp/model-v3.bin")
```

### No-Responders Detection

NATS server sends a no-responders status header (status 503) when `nc.Request` or `nc.PublishRequest` finds
no active subscribers. This is synchronous — callers get `nats.ErrNoResponders` immediately rather than
waiting for a timeout. Always handle this case when using request-reply in production.

## Configuration

```conf
# nats-server.conf — JetStream cluster baseline
jetstream {
    store_dir: /data/jetstream
    max_memory_store: 4GB
    max_file_store: 100GB
}
cluster {
    name: prod-cluster
    routes: ["nats://node1:6222", "nats://node2:6222", "nats://node3:6222"]
}
max_payload: 8MB       # Default 1 MB; increase only if needed (prefer chunked for large objects)
ping_interval: "20s"
max_pings_outstanding: 3
```

## Performance

- Core NATS (no JetStream) has sub-millisecond latency — use it for ephemeral events where loss is acceptable.
- For JetStream pull consumers, tune `Fetch` batch size to match downstream throughput (start at 50, adjust).
- Use `MemoryStorage` streams only for short-lived caches where durability is not required.
- Avoid large messages in core NATS subjects — use Object Store + a reference message for payloads > 512 KB.

## Security

```conf
authorization {
    users: [
        { user: "orders-svc", password: "$2a$...", permissions: {
            publish:   ["orders.*.*"]
            subscribe: ["orders.*.*", "_INBOX.>"]
        }}
    ]
}
tls { cert_file: "/etc/nats/tls/server.crt", key_file: "/etc/nats/tls/server.key" }
```

- Use NKeys or JWT-based auth (decentralized auth) in larger deployments.
- Scope each service to the minimum set of subjects it must publish and subscribe.

## Testing

```go
// In-process NATS server for unit tests
import "github.com/nats-io/nats-server/v2/server"

opts := &server.Options{JetStream: true, StoreDir: t.TempDir()}
s, _ := server.NewServer(opts)
go s.Start()
defer s.Shutdown()

nc, _ := nats.Connect(s.ClientURL())
// test against real NATS without containers
```

## Dos

- Use JetStream for any message that must survive a subscriber crash or restart.
- Prefer pull consumers over push consumers for predictable backpressure control.
- Set `nats.Durable()` on all production consumers so the server tracks delivery state.
- Use queue groups to scale consumers horizontally without duplicating work.
- Handle `ErrNoResponders` in every request-reply callsite — fail fast, don't time out.

## Don'ts

- Don't use NATS core (no JetStream) for work queues — undelivered messages are silently dropped.
- Don't set `Replicas > cluster node count` — stream creation will fail.
- Don't store large binaries in stream subjects — use Object Store and publish a reference.
- Don't use push consumers with `AckNone` in production — you lose delivery guarantees.
- Don't share a single NATS connection across goroutines with blocking operations — use `nats.Connect` per service and share the `*nats.Conn` safely (it is concurrency-safe), but avoid blocking on the connection in tight loops.
