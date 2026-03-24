# Apache Pulsar — Messaging Conventions

## Overview

Pulsar separates compute (brokers) from storage (BookKeeper), enabling independent scaling of both layers.
Its native multi-tenancy, tiered storage offload, and diverse subscription types make it a strong choice for
large organizations or regulated industries. Use it when you need multi-tenancy isolation, long retention
with cost-effective tiered storage, or geographic replication without a complex dual-cluster setup.

## Architecture Patterns

### Multi-Tenancy: Tenants / Namespaces / Topics

```
persistent://tenant/namespace/topic

persistent://payments/europe/transactions
persistent://inventory/warehouse-a/stock-movements
non-persistent://telemetry/iot/sensor-readings   # In-memory only — ephemeral
```

```bash
# Provision a tenant (usually ops/platform team)
pulsar-admin tenants create payments \
  --allowed-clusters us-east-1,eu-west-1 \
  --admin-roles payments-admin

# Namespace — policy boundary (retention, replication, schema, rate limits)
pulsar-admin namespaces create payments/europe
pulsar-admin namespaces set-retention payments/europe \
  --size 50G --time 7d
pulsar-admin namespaces set-schema-compatibility-strategy payments/europe \
  --compatibility BACKWARD_TRANSITIVE
```

### Subscription Types

| Type | Semantics | Best Use Case |
|------|-----------|---------------|
| `Exclusive` | Single active consumer | Ordered, single-writer state machine |
| `Failover` | One active + standbys; auto-failover | HA for ordered processing |
| `Shared` | Round-robin to all consumers | Parallel work queue (no ordering guarantee) |
| `Key_Shared` | Key-consistent routing to consumers | Ordered per key, parallel across keys |

```java
// Key_Shared — ordered per orderId, parallel across different orders
Consumer<OrderEvent> consumer = client.newConsumer(Schema.AVRO(OrderEvent.class))
    .topic("persistent://payments/europe/transactions")
    .subscriptionName("order-processor")
    .subscriptionType(SubscriptionType.Key_Shared)
    .keySharedPolicy(KeySharedPolicy.autoSplitHashRange())
    .subscribe();
```

### Schema Registry
```java
// Pulsar has a built-in schema registry — no external service needed
Producer<PaymentEvent> producer = client.newProducer(Schema.AVRO(PaymentEvent.class))
    .topic("persistent://payments/europe/transactions")
    .create();

// Schema compatibility enforced at publish time
// BACKWARD: consumers using old schema can read new messages (add optional fields)
// FORWARD: new consumers can read old messages (remove fields)
// FULL: both BACKWARD and FORWARD
```

### Delayed Message Delivery
```java
// Schedule a message for future delivery — useful for retries and reminders
producer.newMessage()
    .value(retryEvent)
    .deliverAfter(30, TimeUnit.SECONDS)   // Broker holds and delivers at T+30s
    .send();

// Or absolute delivery time
producer.newMessage()
    .value(reminderEvent)
    .deliverAt(Instant.now().plusSeconds(3600).toEpochMilli())
    .send();
```

### Dead Letter Topics
```java
Consumer<OrderEvent> consumer = client.newConsumer(Schema.AVRO(OrderEvent.class))
    .topic("persistent://payments/europe/transactions")
    .subscriptionName("order-processor")
    .deadLetterPolicy(DeadLetterPolicy.builder()
        .maxRedeliverCount(3)
        .deadLetterTopic("persistent://payments/europe/transactions-DLT")
        .retryLetterTopic("persistent://payments/europe/transactions-RETRY")
        .build())
    .enableRetry(true)   // Auto-publish to retry topic with backoff
    .subscribe();
```

### Topic Compaction
```bash
# Compaction retains only the latest message per key — equivalent to Kafka log compaction
# Trigger manually or schedule automatically
pulsar-admin topics compact persistent://inventory/warehouse-a/product-states

# Set auto-compaction threshold (compact when backlog > 100 MB)
pulsar-admin namespaces set-compaction-threshold inventory/warehouse-a --threshold 104857600
```

### Tiered Storage (BookKeeper + Offload)
```bash
# Offload cold segments to S3 / GCS / Azure Blob after threshold
pulsar-admin namespaces set-offload-policies payments/europe \
  --driver s3 \
  --bucket pulsar-offload-payments \
  --region eu-west-1 \
  --offloadAfterThreshold 10G \
  --offloadedReadPriority tiered-storage-first
```

### Pulsar Functions (Lightweight Stream Processing)
```python
# Stateless enrichment function — runs inside Pulsar without an external processing framework
from pulsar import Function

class EnrichOrderFunction(Function):
    def process(self, input: bytes, context) -> bytes:
        event = json.loads(input)
        event["enriched_at"] = datetime.utcnow().isoformat()
        event["region"] = context.get_user_config_value("region")
        return json.dumps(event).encode()

# Deploy
# pulsar-admin functions create \
#   --py enrich_order.py --classname enrich_order.EnrichOrderFunction \
#   --inputs persistent://payments/europe/transactions-raw \
#   --output  persistent://payments/europe/transactions-enriched \
#   --parallelism 4
```

### Geo-Replication
```bash
# Namespace-level replication — Pulsar brokers handle cross-cluster sync automatically
pulsar-admin namespaces set-replication-clusters payments/europe \
  --clusters us-east-1,eu-west-1

# Exclude specific topics from replication (e.g., region-local audit logs)
pulsar-admin topics set-replication-clusters \
  persistent://payments/europe/local-audit --clusters eu-west-1
```

## Configuration

```properties
# broker.conf — key production settings
managedLedgerDefaultEnsembleSize=3      # BookKeeper ensemble — all writes go to this many bookies
managedLedgerDefaultWriteQuorum=3       # How many bookies must acknowledge a write
managedLedgerDefaultAckQuorum=2         # How many acks needed before write succeeds (ack quorum <= write quorum)
backlogQuotaDefaultRetentionPolicy=producer_exception   # Reject producers when backlog full (vs silent drop)
defaultRetentionTimeInMinutes=10080     # 7 days default retention
defaultRetentionSizeInMB=51200          # 50 GB default retention cap
```

## Performance

- Tune `receiverQueueSize` on consumers (default 1000) — increase for high-throughput, decrease for memory-constrained workers.
- Use batching on producers: `batchingEnabled=true`, `batchingMaxMessages=1000`, `batchingMaxPublishDelay=5ms`.
- For Key_Shared, ensure key cardinality is high enough to distribute work evenly across consumers.
- Prefer `Shared` subscription over `Key_Shared` when message ordering per key is not required — it has lower CPU overhead.

## Security

```bash
# Namespace-level authorization
pulsar-admin namespaces grant-permission payments/europe \
  --actions produce --role payments-producer-sa
pulsar-admin namespaces grant-permission payments/europe \
  --actions consume --role payments-consumer-sa

# TLS for broker connections + JWT token authentication
# Set authenticationEnabled=true, authorizationEnabled=true in broker.conf
```

## Testing

```java
// PulsarMock (unit tests, no broker required)
@Test void shouldProcessPaymentEvent() throws Exception {
    PulsarClient client = PulsarMock.newMockPulsarClient();
    Producer<byte[]> producer = client.newProducer().topic("test-topic").create();
    Consumer<byte[]> consumer = client.newConsumer()
        .topic("test-topic").subscriptionName("test-sub").subscribe();

    producer.send("test".getBytes());
    Message<byte[]> msg = consumer.receive(1, TimeUnit.SECONDS);
    assertThat(new String(msg.getData())).isEqualTo("test");
    consumer.acknowledge(msg);
}

// Integration: Testcontainers with apachepulsar/pulsar image
```

## Dos

- Use `Key_Shared` subscription when you need both parallelism and per-key ordering.
- Configure schema compatibility at the namespace level (`BACKWARD_TRANSITIVE`) to catch breaks in CI.
- Set `maxRedeliverCount` and a dead letter topic on every production subscription.
- Use tiered storage offload for topics with retention > 7 days to control BookKeeper disk usage.
- Monitor `pulsar_storage_backlog_size` and `pulsar_consumers_count` per subscription for lag.

## Don'ts

- Don't use `non-persistent://` topics for any data that must survive broker restarts.
- Don't set `managedLedgerDefaultAckQuorum > managedLedgerDefaultWriteQuorum` — write quorum must be >= ack quorum.
- Don't use Pulsar Functions for CPU-heavy or stateful aggregations — use Flink or Spark Structured Streaming instead.
- Don't share a namespace across teams with different compliance requirements — create a namespace per team.
- Don't configure geo-replication without testing consumer idempotency — messages may be delivered from multiple clusters during failover.
