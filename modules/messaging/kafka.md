# Apache Kafka — Messaging Conventions

## Overview

Kafka is a distributed log optimized for high-throughput, ordered, replayable event streams. Use it when
you need durability, consumer-group fan-out, or time-travel replay. Avoid it for low-latency RPC patterns
(use NATS or gRPC instead) or tiny deployments where Kafka's operational overhead exceeds the benefit.

## Architecture Patterns

### Topic Naming
Use a hierarchical dot-separated convention: `{domain}.{entity}.{event-type}`.

```
payments.transactions.created
payments.transactions.refunded
inventory.products.stock-updated
notifications.emails.delivery-failed
```

- All lowercase, hyphens inside segments, dots as separators.
- Never embed environment in topic name — use separate clusters or namespaces per env.
- Version suffix (`..v2`) only when schema evolution requires a hard cutover.

### Partitions and Replication
```yaml
# Production baseline
partitions: 12           # Start 2–4× consumer instances; scale later (only increases allowed)
replication.factor: 3    # Minimum for HA; RF=1 loses data on single broker failure
min.insync.replicas: 2   # Reject writes when only 1 replica alive (acks=all + min.isr=2)
```

### Partitioning Strategy
```java
// Key-based — preserves order per entity (e.g., all events for orderId together)
producer.send(new ProducerRecord<>("orders.events.v1", order.getId(), event));

// Round-robin — maximum throughput when ordering is irrelevant
producer.send(new ProducerRecord<>("metrics.raw.v1", null, metric));

// Custom partitioner — route VIP customers to dedicated partitions
public class PriorityPartitioner implements Partitioner {
    public int partition(String topic, Object key, ..., int numPartitions) {
        return isVip(key) ? 0 : (Math.abs(key.hashCode()) % (numPartitions - 1)) + 1;
    }
}
```

### Exactly-Once Semantics
```java
// Idempotent producer (deduplicates retries within a session)
props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
props.put(ProducerConfig.ACKS_CONFIG, "all");
props.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5);

// Transactional producer (atomic multi-topic writes)
props.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG, "payments-producer-1");
producer.initTransactions();
try {
    producer.beginTransaction();
    producer.send(outboxRecord);
    producer.sendOffsetsToTransaction(offsets, consumerGroupMetadata);
    producer.commitTransaction();
} catch (ProducerFencedException e) {
    producer.close(); // Another instance took over — do not retry
} catch (KafkaException e) {
    producer.abortTransaction();
}
```

### Schema Registry (Avro/Protobuf)
```java
// Producer with Confluent Schema Registry
props.put("schema.registry.url", "http://schema-registry:8081");
props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class);
props.put("auto.register.schemas", false);   // Enforce pre-registration in CI
props.put("use.latest.version", true);

// Schema compatibility: BACKWARD (default) allows adding optional fields
// FORWARD allows removing fields; FULL is both — pick per-topic in the registry
```

### Dead Letter Topics
```java
// Consumer: route unprocessable messages to DLT
try {
    process(record);
    consumer.commitSync();
} catch (NonRetryableException e) {
    producer.send(new ProducerRecord<>(topic + ".DLT", record.key(), augment(record, e)));
    consumer.commitSync();
} catch (RetryableException e) {
    // Back off and retry — do NOT commit offset
}
```

### Compaction vs Retention
```yaml
# Log compaction — keep latest value per key (good for changelogs/cache-fill)
cleanup.policy: compact
min.cleanable.dirty.ratio: 0.5
delete.retention.ms: 86400000   # 24 h tombstone visibility window

# Time-based retention — event log, audit trail
cleanup.policy: delete
retention.ms: 604800000          # 7 days
retention.bytes: -1              # Unbounded by size (let time control)

# Both — retain recent history AND compact older segments
cleanup.policy: compact,delete
```

## Configuration

```properties
# Consumer — minimize rebalance disruption
group.id=payments-consumer-group
enable.auto.commit=false
max.poll.records=500
max.poll.interval.ms=300000
session.timeout.ms=45000
heartbeat.interval.ms=15000
isolation.level=read_committed   # Required for EOS consumers
```

## Performance

- Use batch sending: `linger.ms=5`, `batch.size=65536` for throughput; set both to 0 for ultra-low latency.
- Compress at producer: `compression.type=lz4` — good CPU/ratio tradeoff for most workloads.
- Pre-allocate consumer threads at the partition count — one thread per partition is the maximum useful concurrency.

## Consumer Lag Monitoring

```bash
# Built-in CLI
kafka-consumer-groups.sh --bootstrap-server broker:9092 \
  --group payments-consumer-group --describe

# Key metric: LAG column. Alert when LAG > (expected throughput × acceptable delay in seconds)
# Expose via JMX: kafka.consumer:type=consumer-fetch-manager-metrics,records-lag-max
```

## Consumer Rebalancing Strategies

```java
// Sticky assignor — minimizes partition movement on rebalance (prefer over RangeAssignor)
props.put(ConsumerConfig.PARTITION_ASSIGNMENT_STRATEGY_CONFIG,
    StickyAssignor.class.getName());

// Cooperative sticky — rolling rebalance, zero downtime for unchanged partitions
props.put(ConsumerConfig.PARTITION_ASSIGNMENT_STRATEGY_CONFIG,
    CooperativeStickyAssignor.class.getName());
```

## Security

- Encrypt in transit: `security.protocol=SSL` or `SASL_SSL`.
- Authenticate with SASL/SCRAM-SHA-512 or mTLS for service-to-service.
- ACL per topic: grant `WRITE` to producer principals only; `READ` to consumer group principals only.
- Never embed credentials in application config — use environment variables or a secrets manager.

## Testing

```java
// EmbeddedKafka for unit/integration tests (Spring Kafka)
@EmbeddedKafka(partitions = 3, topics = {"orders.events.v1"})
class OrderEventConsumerTest {
    @Autowired EmbeddedKafkaBroker broker;

    @Test void shouldProcessCreatedEvent() {
        // Produce → consume → assert side effects
    }
}

// Testcontainers for full schema-registry integration
@Container
static KafkaContainer kafka = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));
```

## Dos

- Set `acks=all` + `min.insync.replicas=2` for any data you cannot afford to lose.
- Always disable `auto.commit` and commit offsets explicitly after successful processing.
- Register schemas in CI and set `auto.register.schemas=false` in production.
- Use compacted topics for state (latest value per key), delete-retention topics for event logs.
- Monitor consumer lag as the primary health signal; alert before lag causes SLA breaches.

## Don'ts

- Don't use Kafka as a request/reply RPC mechanism — latency is unpredictable.
- Don't store large payloads (> 1 MB) directly in messages — store in object storage and send a reference.
- Don't share a `transactional.id` across multiple producer instances — this causes fencing.
- Don't increase partition count without understanding the rebalance impact on ordered consumers.
- Don't ignore `max.poll.interval.ms` — a slow consumer loop causes spurious rebalances.
