# Gin + Kafka

> Gin-specific patterns for Kafka using `segmentio/kafka-go`.
> Generic Kafka patterns are in `modules/frameworks/go-stdlib/messaging/kafka.md`.

## Integration Setup

```go
// go.mod
require (
    github.com/gin-gonic/gin v1.10.0
    github.com/segmentio/kafka-go v0.4.47
)
```

## Async Producer Alongside HTTP Server

```go
type Server struct {
    router   *gin.Engine
    producer *kafka.Writer
}

func main() {
    producer := messaging.NewProducer(
        strings.Split(os.Getenv("KAFKA_BROKERS"), ","),
        "orders",
    )

    srv := &Server{
        router:   setupRouter(producer),
        producer: producer,
    }

    ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM)
    defer cancel()

    go srv.router.Run(":8080")

    <-ctx.Done()
    producer.Close()
}
```

## Publishing in a Gin Handler

```go
func CreateOrderHandler(producer *kafka.Writer) gin.HandlerFunc {
    return func(c *gin.Context) {
        var req CreateOrderRequest
        if err := c.ShouldBindJSON(&req); err != nil {
            c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
            return
        }

        order, err := createOrder(c.Request.Context(), req)
        if err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": "create failed"})
            return
        }

        event, _ := json.Marshal(OrderCreatedEvent{ID: order.ID, Items: req.Items})
        if err := producer.WriteMessages(c.Request.Context(), kafka.Message{
            Key:   []byte(order.ID),
            Value: event,
        }); err != nil {
            // Log and continue — don't fail the HTTP response for publish errors
            slog.Error("publish order.created failed", "err", err, "order_id", order.ID)
        }

        c.JSON(http.StatusCreated, order)
    }
}
```

## Consumer in Background goroutine

```go
func StartConsumer(ctx context.Context, brokers []string, topic, groupID string, svc OrderService) {
    reader := messaging.NewConsumer(brokers, topic, groupID)
    go func() {
        defer reader.Close()
        messaging.Consume(ctx, reader, func(msg kafka.Message) error {
            var event PaymentEvent
            if err := json.Unmarshal(msg.Value, &event); err != nil {
                return err // non-retryable: bad schema → log + skip
            }
            return svc.HandlePayment(ctx, event)
        })
    }()
}
```

## Scaffolder Patterns

```yaml
patterns:
  producer_setup: "internal/messaging/producer.go"
  consumer_setup: "internal/messaging/consumer.go"
  event_types: "internal/messaging/events.go"
  handler: "internal/handler/{resource}_handler.go"  # injects producer via closure
```

## Additional Dos/Don'ts

- DO inject the producer as a constructor argument to handlers — never as a Gin context key
- DO start the consumer goroutine before `router.Run` and cancel its context on shutdown
- DO log publish failures and continue the HTTP response — event publishing is best-effort in fire-and-forget flows; use outbox pattern when at-least-once delivery is required
- DON'T block the HTTP handler on synchronous Kafka publish for non-critical events — use `Async: true` with a monitored error channel
- DON'T use `c.Request.Context()` for the consumer loop — use a dedicated shutdown context, not the HTTP request context
