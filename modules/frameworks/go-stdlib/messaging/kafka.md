# Go stdlib + Kafka

> Go stdlib Kafka patterns using `segmentio/kafka-go` or `confluent-kafka-go`.
> Generic Go conventions are NOT repeated here.

## Integration Setup

```go
// Option A: segmentio/kafka-go (pure Go, no CGO)
require github.com/segmentio/kafka-go v0.4.47

// Option B: confluent-kafka-go (librdkafka binding, higher throughput)
require github.com/confluentinc/confluent-kafka-go/v2 v2.5.0
```

## Producer Setup (segmentio/kafka-go)

```go
func NewProducer(brokers []string, topic string) *kafka.Writer {
    return &kafka.Writer{
        Addr:         kafka.TCP(brokers...),
        Topic:        topic,
        Balancer:     &kafka.LeastBytes{},
        RequiredAcks: kafka.RequireAll, // wait for all ISR acknowledgment
        Async:        false,            // synchronous for at-least-once guarantees
        BatchTimeout: 10 * time.Millisecond,
        MaxAttempts:  5,
    }
}

func Publish(ctx context.Context, w *kafka.Writer, key string, value []byte) error {
    return w.WriteMessages(ctx, kafka.Message{
        Key:   []byte(key),
        Value: value,
        Headers: []kafka.Header{
            {Key: "content-type", Value: []byte("application/json")},
        },
    })
}
```

## Consumer Group Setup

```go
func NewConsumer(brokers []string, topic, groupID string) *kafka.Reader {
    return kafka.NewReader(kafka.ReaderConfig{
        Brokers:        brokers,
        Topic:          topic,
        GroupID:        groupID,
        MinBytes:       10e3,  // 10KB
        MaxBytes:       10e6,  // 10MB
        CommitInterval: time.Second,
        StartOffset:    kafka.LastOffset,
    })
}

func Consume(ctx context.Context, r *kafka.Reader, handler func(kafka.Message) error) error {
    for {
        msg, err := r.FetchMessage(ctx) // does NOT auto-commit
        if err != nil {
            if errors.Is(err, context.Canceled) {
                return nil
            }
            return fmt.Errorf("fetch: %w", err)
        }

        if err := handler(msg); err != nil {
            slog.Error("message handler failed", "err", err, "offset", msg.Offset)
            // Decide: skip (commit anyway) vs. stop vs. DLQ
            continue
        }

        if err := r.CommitMessages(ctx, msg); err != nil {
            return fmt.Errorf("commit: %w", err)
        }
    }
}
```

## Graceful Shutdown

```go
ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
defer cancel()

go func() { _ = Consume(ctx, reader, processMessage) }()

<-ctx.Done()
slog.Info("shutting down consumer")
if err := reader.Close(); err != nil {
    slog.Error("close reader", "err", err)
}
if err := writer.Close(); err != nil {
    slog.Error("close writer", "err", err)
}
```

## Scaffolder Patterns

```yaml
patterns:
  producer: "internal/messaging/producer.go"
  consumer: "internal/messaging/consumer.go"
  handler: "internal/messaging/{topic}_handler.go"
  config: "internal/messaging/config.go"
```

## Additional Dos/Don'ts

- DO use `FetchMessage` + `CommitMessages` for manual offset control; never `ReadMessage` (auto-commits on fetch)
- DO set `RequiredAcks: kafka.RequireAll` on the writer for durability
- DO implement dead-letter queue (DLQ) publishing for messages that fail handler processing repeatedly
- DO close both reader and writer in shutdown to flush buffers and release connections
- DON'T share a single `*kafka.Writer` across goroutines without synchronization — use one writer per goroutine or make writes thread-safe
- DON'T use `Async: true` on the writer unless you explicitly handle the error channel
- DON'T commit offsets before the handler completes — this risks message loss on crash
