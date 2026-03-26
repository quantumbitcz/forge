# Google Pub/Sub — Messaging Conventions

## Overview

Google Cloud Pub/Sub is a managed, serverless messaging service providing at-least-once delivery,
exactly-once processing (with ordering keys), and automatic scaling. Use it for event-driven
architectures on GCP, decoupling microservices, streaming data to BigQuery/Dataflow, and
cross-region message delivery. Pub/Sub excels at zero-ops messaging with built-in dead-letter
support. Avoid it for low-latency (<10ms) messaging (use NATS), strict message ordering across
all messages (use Kafka), or multi-cloud portability requirements.

## Architecture Patterns

### Topic and Subscription Design
```
Topic: orders.created
  ├── Subscription: order-processor     (pull, exactly-once)
  ├── Subscription: notification-sender (pull, at-least-once)
  ├── Subscription: analytics-pipeline  (BigQuery subscription)
  └── Subscription: audit-log           (Cloud Storage subscription)
```

### Publishing Messages
```python
from google.cloud import pubsub_v1
import json

publisher = pubsub_v1.PublisherClient(
    publisher_options=pubsub_v1.types.PublisherOptions(
        flow_control=pubsub_v1.types.PublishFlowControl(
            message_limit=1000,
            byte_limit=10 * 1024 * 1024
        )
    )
)

topic_path = publisher.topic_path("my-project", "orders.created")

def publish_order_event(order):
    data = json.dumps({"orderId": order.id, "total": str(order.total)}).encode("utf-8")
    future = publisher.publish(
        topic_path,
        data,
        ordering_key=str(order.user_id),  # preserves order per user
        event_type="order.created",
        version="1.0"
    )
    return future.result()  # blocks until published
```

### Subscribing (Pull — Recommended)
```python
from google.cloud import pubsub_v1
from concurrent.futures import TimeoutError

subscriber = pubsub_v1.SubscriberClient()
subscription_path = subscriber.subscription_path("my-project", "order-processor")

def callback(message):
    try:
        data = json.loads(message.data.decode("utf-8"))
        process_order(data)
        message.ack()
    except Exception as e:
        logger.error(f"Processing failed: {e}")
        message.nack()  # redelivered after ack_deadline

streaming_pull = subscriber.subscribe(subscription_path, callback=callback)
try:
    streaming_pull.result(timeout=None)
except TimeoutError:
    streaming_pull.cancel()
    streaming_pull.result()
```

### Dead Letter Topic
```hcl
resource "google_pubsub_subscription" "order_processor" {
  name  = "order-processor"
  topic = google_pubsub_topic.orders.name

  ack_deadline_seconds = 30

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}
```

### Anti-pattern — using Pub/Sub for synchronous request-response: Pub/Sub is designed for asynchronous, decoupled communication. For synchronous request-response, use gRPC or HTTP. Implementing request-response over Pub/Sub adds complexity and latency without benefit.

## Configuration

**Terraform setup:**
```hcl
resource "google_pubsub_topic" "orders" {
  name = "orders.created"

  message_retention_duration = "86400s"  # 24 hours

  schema_settings {
    schema   = google_pubsub_schema.order.id
    encoding = "JSON"
  }
}

resource "google_pubsub_subscription" "processor" {
  name  = "order-processor"
  topic = google_pubsub_topic.orders.name

  ack_deadline_seconds       = 30
  message_retention_duration = "604800s"  # 7 days
  retain_acked_messages      = false

  enable_exactly_once_delivery = true

  expiration_policy {
    ttl = ""  # never expire
  }
}
```

**Schema validation:**
```hcl
resource "google_pubsub_schema" "order" {
  name       = "order-event"
  type       = "AVRO"
  definition = file("schemas/order-event.avsc")
}
```

## Performance

**Batch publishing settings:**
```python
from google.cloud.pubsub_v1.types import BatchSettings

publisher = pubsub_v1.PublisherClient(
    batch_settings=BatchSettings(
        max_messages=100,
        max_bytes=1024 * 1024,  # 1 MB
        max_latency=0.01        # 10ms
    )
)
```

**Flow control for subscribers:**
```python
flow_control = pubsub_v1.types.FlowControl(
    max_messages=100,
    max_bytes=10 * 1024 * 1024
)
subscriber.subscribe(subscription_path, callback=callback, flow_control=flow_control)
```

**Ordering keys:** Use ordering keys only when message order matters (e.g., per-entity updates). Ordering keys limit throughput to 1 MB/s per key. Don't use a single ordering key for all messages.

**Seek for replay:** Use subscription seek to replay messages from a timestamp or snapshot — useful for reprocessing after a bug fix.

## Security

**IAM roles (least privilege):**
```hcl
resource "google_pubsub_topic_iam_member" "publisher" {
  topic  = google_pubsub_topic.orders.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:order-service@my-project.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "subscriber" {
  subscription = google_pubsub_subscription.processor.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:processor@my-project.iam.gserviceaccount.com"
}
```

**CMEK encryption:**
```hcl
resource "google_pubsub_topic" "sensitive" {
  name = "pii-events"
  kms_key_name = google_kms_crypto_key.pubsub.id
}
```

**VPC Service Controls:** Restrict Pub/Sub API access to within a VPC perimeter to prevent data exfiltration.

## Testing

**Pub/Sub Emulator for local testing:**
```bash
gcloud beta emulators pubsub start --project=test-project
export PUBSUB_EMULATOR_HOST=localhost:8085
```
```python
import os
os.environ["PUBSUB_EMULATOR_HOST"] = "localhost:8085"
# Client automatically connects to emulator
```

Test message publishing, subscription delivery, dead-letter routing, and ordering key semantics with the emulator. For integration tests, use a dedicated GCP project with isolated topics.

## Dos
- Use pull subscriptions for most workloads — they give you flow control and batching.
- Enable dead-letter topics for all subscriptions — unprocessable messages need a destination.
- Use schema validation on topics to reject malformed messages at publish time.
- Set `message_retention_duration` on topics — it enables seek-based replay after consumer failures.
- Use ordering keys scoped to the entity (user ID, order ID) — not a single key for all messages.
- Use exactly-once delivery when duplicate processing is unacceptable (financial transactions).
- Monitor subscription backlog with `num_undelivered_messages` metric and alert on growth.

## Don'ts
- Don't use Pub/Sub for synchronous request-response — use gRPC or HTTP instead.
- Don't use a single ordering key for all messages — it limits throughput to 1 MB/s.
- Don't set `ack_deadline_seconds` too short — messages redelivered before processing completes cause duplicates.
- Don't skip dead-letter configuration — poison messages block subscription processing indefinitely.
- Don't publish without flow control — unbounded publishing can overwhelm the client and cause OOM.
- Don't use Pub/Sub as a database — messages are ephemeral; use Cloud Storage or BigQuery for persistence.
- Don't ignore the 10 MB message size limit — large payloads should reference data in Cloud Storage.
