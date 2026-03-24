# RabbitMQ — Messaging Conventions

## Overview

RabbitMQ is a broker centered on the AMQP exchange/queue model. It excels at flexible routing, workflow
orchestration, and per-message acknowledgment semantics. Prefer it over Kafka when you need complex routing
logic, low-latency delivery with small payloads, or per-consumer flow control via prefetch.

## Architecture Patterns

### Exchange Types

| Exchange | Routing Key Matching | Best Use Case |
|----------|---------------------|---------------|
| `direct` | Exact match | Point-to-point work queues |
| `topic` | Wildcard (`*` = 1 word, `#` = 0+) | Event routing by domain + type |
| `fanout` | Ignored — all queues | Broadcast to all subscribers |
| `headers` | AMQP header map | Multi-attribute routing without a routing key |

```python
# Topic exchange — route by domain and severity
channel.exchange_declare("app.events", exchange_type="topic", durable=True)

# payments.# — all payment events
# *.error    — errors from any domain
channel.queue_bind("payments-audit-queue", "app.events", routing_key="payments.#")
channel.queue_bind("alerting-queue",       "app.events", routing_key="*.error")
```

### Queue Durability and Persistence
```python
# Durable queue survives broker restart; persistent messages written to disk
channel.queue_declare(
    "orders",
    durable=True,
    arguments={"x-queue-type": "quorum"}   # Quorum queues: raft-replicated, preferred over classic mirrored
)

channel.basic_publish(
    exchange="", routing_key="orders",
    body=payload,
    properties=pika.BasicProperties(delivery_mode=2)  # 2 = persistent
)
```

### Dead Letter Exchanges (DLX)
```python
# Declare the DLX and its dead-letter queue first
channel.exchange_declare("dlx.orders", exchange_type="direct", durable=True)
channel.queue_declare("orders.dead-letters", durable=True)
channel.queue_bind("orders.dead-letters", "dlx.orders", routing_key="orders")

# Wire DLX into the main queue
channel.queue_declare(
    "orders",
    durable=True,
    arguments={
        "x-dead-letter-exchange": "dlx.orders",
        "x-dead-letter-routing-key": "orders",
        "x-message-ttl": 30000,          # Messages expire after 30 s → go to DLX
        "x-max-length": 100000,          # Overflow → DLX (head-drop by default)
    }
)
```

### Publisher Confirms
```python
# Synchronous confirm (simple, lower throughput)
channel.confirm_delivery()
try:
    channel.basic_publish(...)  # raises UnroutableError / NackError on failure
except pika.exceptions.UnroutableError:
    log.error("Message returned — no matching queue")

# Asynchronous confirms (high throughput)
channel.add_on_return_callback(on_return)
channel.add_on_nack_callback(on_nack)
channel.basic_publish(..., mandatory=True)
```

### Consumer Acknowledgment (Manual Ack)
```python
def on_message(ch, method, properties, body):
    try:
        process(body)
        ch.basic_ack(delivery_tag=method.delivery_tag)
    except NonRetryableError:
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)  # → DLX
    except RetryableError:
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)   # back to queue

channel.basic_consume("orders", on_message)
```

### Prefetch Count Tuning
```python
# Prevents one slow consumer from hoarding all messages
# Rule of thumb: prefetch = (processing_time_ms / network_round_trip_ms) × consumer_count
channel.basic_qos(prefetch_count=20)   # 20 unacknowledged messages max per consumer
```

## Configuration

```yaml
# rabbitmq.conf — key production settings
vm_memory_high_watermark.relative = 0.6   # Pause publishers at 60% RAM
disk_free_limit.absolute = 2GB            # Pause at 2 GB free disk
heartbeat = 60                            # Detect dead TCP connections (seconds)
channel_max = 2047                        # Prevent channel leaks
consumer_timeout = 1800000               # 30 min max unacked message (ms)
```

## Performance

- Use quorum queues in production — they replace classic mirrored queues with Raft consensus.
- Keep queues short (< 100k messages); long queues cause high memory use and slow browsing.
- Set `prefetch_count` per consumer, not per channel, to distribute work evenly.
- Batch publish with `publisher confirms` in async mode — synchronous confirms are 10× slower.
- Enable lazy queues (store to disk early) if your queues regularly grow large.

## TTL and Queue Length Limits

```python
# Per-message TTL (set by publisher)
properties=pika.BasicProperties(expiration="60000")  # 60 s in ms, as string

# Per-queue TTL and length (set at queue declaration, cannot change on existing queue)
arguments={
    "x-message-ttl": 86400000,   # 24 h
    "x-max-length": 50000,       # hard cap — overflow behavior: drop-head (default) or reject-publish
    "x-overflow": "reject-publish-dlx",  # overflow → DLX instead of silent drop
}
```

## Shovel and Federation for Multi-DC

```bash
# Shovel — active message mover, useful for DC migration or overflow relief
rabbitmqctl set_parameter shovel dc1-to-dc2 \
  '{"src-protocol":"amqp091","src-uri":"amqp://dc1","src-queue":"orders",
    "dest-protocol":"amqp091","dest-uri":"amqp://dc2","dest-queue":"orders"}'

# Federation — passive link, subscriber pulls from upstream exchange
# Prefer federation for read-fan-out across DCs; shovel for write replication
```

## Virtual Hosts for Isolation

```bash
# Create per-team or per-service vhosts to prevent cross-tenant queue browsing
rabbitmqctl add_vhost /payments
rabbitmqctl add_user payments-svc strong-password
rabbitmqctl set_permissions -p /payments payments-svc ".*" ".*" ".*"
# Other services have zero permissions on /payments by default
```

## Security

- Use TLS for all client connections; enforce with `ssl_options.fail_if_no_peer_cert = true`.
- Assign each service its own credentials with minimum required permissions (configure/write/read).
- Rotate credentials via a secrets manager; never hardcode in application config.
- Disable the default `guest` user or restrict it to `localhost` only.

## Testing

```python
# Use a real RabbitMQ via Testcontainers — mocking AMQP semantics is error-prone
from testcontainers.rabbitmq import RabbitMqContainer

with RabbitMqContainer("rabbitmq:3.13-management") as rmq:
    connection = pika.BlockingConnection(pika.URLParameters(rmq.get_connection_url()))
    # Declare, publish, consume, assert

# For Spring AMQP: @SpringBootTest with a Testcontainers-managed broker
# For Go: use github.com/testcontainers/testcontainers-go/modules/rabbitmq
```

## Dos

- Declare exchanges, queues, and bindings as durable; use persistent delivery mode for important messages.
- Always use manual acknowledgment — `auto_ack=True` loses messages on consumer crash.
- Attach a DLX to every production queue; inspect dead letters to catch poison messages early.
- Set `prefetch_count` to a value calibrated against your processing latency to avoid head-of-line blocking.
- Use quorum queues for new deployments; migrate classic mirrored queues during planned maintenance.

## Don'ts

- Don't use a single channel for both publishing and consuming — use separate channels per operation.
- Don't declare a queue without a DLX in production — rejected messages will pile up invisibly.
- Don't change `x-max-length` or `x-message-ttl` on a live queue — delete and redeclare during a maintenance window.
- Don't set `prefetch_count=0` (unlimited) on slow consumers — it starves other consumers on the same channel.
- Don't rely on RabbitMQ as a durable event log — it is a broker, not a replay-capable stream store.
