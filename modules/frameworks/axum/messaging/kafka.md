# Axum + Kafka (rdkafka)

> Axum-specific Kafka patterns using `rdkafka` and `tokio::spawn`.
> Extends generic Axum conventions.

## Integration Setup

```toml
# Cargo.toml
[dependencies]
axum = "0.8"
rdkafka = { version = "0.37", features = ["tokio"] }
tokio = { version = "1", features = ["full"] }
serde_json = "1"
tracing = "0.1"
```

## Producer Setup

```rust
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;

pub fn create_producer(brokers: &str) -> FutureProducer {
    ClientConfig::new()
        .set("bootstrap.servers", brokers)
        .set("message.timeout.ms", "5000")
        .set("acks", "all")
        .create()
        .expect("Failed to create Kafka producer")
}
```

## Publishing from an Axum Handler

```rust
use std::time::Duration;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub kafka: FutureProducer,
}

async fn create_order(
    State(state): State<AppState>,
    Json(payload): Json<CreateOrderRequest>,
) -> Result<Json<Order>, AppError> {
    let order = state.db_create_order(&payload).await?;

    let event = serde_json::to_string(&OrderCreatedEvent::from(&order))?;
    state.kafka
        .send(
            FutureRecord::to("orders.created")
                .key(order.id.to_string().as_str())
                .payload(&event),
            Duration::from_secs(5),
        )
        .await
        .map_err(|(err, _msg)| {
            tracing::error!("kafka publish failed: {err}");
            AppError::Internal // don't fail the HTTP response for publish errors in fire-and-forget
        })
        .ok(); // log and continue

    Ok(Json(order))
}
```

## Consumer in Background Task

```rust
use rdkafka::consumer::{CommitMode, Consumer, StreamConsumer};
use rdkafka::Message;

pub fn create_consumer(brokers: &str, group_id: &str, topics: &[&str]) -> StreamConsumer {
    let consumer: StreamConsumer = ClientConfig::new()
        .set("bootstrap.servers", brokers)
        .set("group.id", group_id)
        .set("enable.auto.commit", "false")
        .set("auto.offset.reset", "earliest")
        .create()
        .expect("Failed to create Kafka consumer");

    consumer.subscribe(topics).expect("Subscribe failed");
    consumer
}

pub async fn run_consumer(consumer: StreamConsumer, handler: impl Fn(String) -> anyhow::Result<()>) {
    loop {
        match consumer.recv().await {
            Err(e) => tracing::error!("Kafka recv error: {e}"),
            Ok(msg) => {
                let payload = msg.payload_view::<str>().unwrap_or(Ok("")).unwrap_or("");
                if let Err(e) = handler(payload.to_string()) {
                    tracing::error!("Handler error: {e}");
                    // decide: skip vs DLQ
                }
                consumer.commit_message(&msg, CommitMode::Async).unwrap();
            }
        }
    }
}
```

## Wire Consumer as Tokio Background Task

```rust
#[tokio::main]
async fn main() {
    let consumer = create_consumer(&brokers, "my-service", &["payments.completed"]);
    let svc = payment_service.clone();

    tokio::spawn(async move {
        run_consumer(consumer, move |payload| {
            svc.handle_payment_event(&payload)
        }).await;
    });

    // Start Axum server
    axum::serve(listener, app).await.unwrap();
}
```

## Scaffolder Patterns

```yaml
patterns:
  producer_setup: "src/messaging/producer.rs"
  consumer_setup: "src/messaging/consumer.rs"
  event_types: "src/messaging/events.rs"
  state: "src/state.rs"   # FutureProducer added to AppState
```

## Additional Dos/Don'ts

- DO use `enable.auto.commit = false` and commit manually after successful processing
- DO spawn the consumer with `tokio::spawn` and drive it independently from the HTTP server
- DO log Kafka publish failures and continue returning the HTTP response for fire-and-forget events
- DO set `acks = all` on the producer for durability
- DON'T use `Duration::from_secs(0)` as the send timeout — it disables the timeout and can block forever
- DON'T run blocking handler logic inside `run_consumer` — spawn a new task per message for CPU-intensive work
- DON'T share the `StreamConsumer` across threads — it is not `Send + Sync` in all rdkafka configurations
