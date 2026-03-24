# Redis Streams — Messaging Conventions

## Overview

Redis Streams provide a persistent, append-only log with consumer groups, inspired by Kafka but embedded
inside Redis. Use them when you already run Redis and need lightweight event streaming without a separate
broker. Prefer Kafka or Pulsar for multi-datacenter durability, very high throughput (> 100k msg/s), or
long retention requirements.

## Architecture Patterns

### Stream vs Pub/Sub Decision Matrix

| Requirement | Streams | Pub/Sub |
|-------------|---------|---------|
| Persistence (survives subscriber downtime) | Yes | No |
| Replay / time-travel | Yes (by ID) | No |
| Consumer groups (each message once) | Yes | No |
| Fan-out (every subscriber gets every message) | Yes (multiple groups) | Yes |
| Latency | Low (~1 ms) | Ultra-low (~0.1 ms) |
| Backpressure | `MAXLEN` trimming | None |

Prefer Streams for any production work queue. Reserve Pub/Sub for live dashboards and ephemeral real-time
notifications where message loss is acceptable.

### Producing Messages
```python
# XADD — append to stream; Redis auto-generates a millisecond ID (1714000000000-0)
# Use "*" for auto-ID; explicit ID only when replaying from an external source
r.xadd("orders:events", {
    "type": "order.created",
    "order_id": "ord_123",
    "customer_id": "cust_456",
    "amount": "199.99",
})

# Cap stream length to prevent unbounded growth (approximate is faster)
r.xadd("orders:events", fields, maxlen=100_000, approximate=True)
```

### Consumer Groups
```python
# Create group — start from "$" (new messages) or "0" (replay all)
try:
    r.xgroup_create("orders:events", "order-processor", id="$", mkstream=True)
except redis.exceptions.ResponseError as e:
    if "BUSYGROUP" not in str(e):
        raise  # Group already exists — ignore; other errors re-raise

# Consumer reads with blocking wait
def consume(consumer_name: str):
    while True:
        # ">" means: give me messages not yet delivered to any consumer in this group
        entries = r.xreadgroup(
            groupname="order-processor",
            consumername=consumer_name,
            streams={"orders:events": ">"},
            count=50,
            block=5000,   # Block 5 s; returns empty list on timeout
        )
        for stream, messages in (entries or []):
            for msg_id, fields in messages:
                try:
                    process(fields)
                    r.xack("orders:events", "order-processor", msg_id)
                except NonRetryableError:
                    move_to_dlstream("orders:dead-letters", msg_id, fields)
                    r.xack("orders:events", "order-processor", msg_id)
```

### Consumer ID Strategy

Name consumers after their host+pid or pod name: `worker-pod-7b4f9-0`. This enables the server to
track which consumer owns which pending messages and supports XCLAIM-based recovery without ambiguity.

```python
import socket, os
consumer_name = f"{socket.gethostname()}-{os.getpid()}"
```

### Pending Entry List (PEL) — Acknowledgment Recovery
```python
# XPENDING — inspect messages delivered but not acknowledged
pending = r.xpending_range("orders:events", "order-processor", "-", "+", count=100)
# Returns: [{id, consumer, time_since_delivered_ms, delivery_count}, ...]

STALE_THRESHOLD_MS = 60_000   # 60 seconds

for entry in pending:
    if entry["time_since_delivered"] > STALE_THRESHOLD_MS:
        # Reclaim from dead/slow consumer
        r.xclaim(
            "orders:events", "order-processor",
            min_idle_time=STALE_THRESHOLD_MS,
            message_ids=[entry["message_id"]],
            consumer=consumer_name,
        )

# XAUTOCLAIM — atomic "find stale + claim" in one round trip (Redis >= 7.0)
claimed, next_cursor, _ = r.xautoclaim(
    "orders:events", "order-processor", consumer_name,
    min_idle_time=STALE_THRESHOLD_MS,
    start_id="0-0",
    count=50,
)
```

### Stream Trimming
```python
# Trim by length — keep the most recent N messages
r.xtrim("orders:events", maxlen=500_000, approximate=True)

# Trim by minimum ID (time-based) — keep messages younger than 7 days
import time
seven_days_ms = int((time.time() - 7 * 86400) * 1000)
r.xtrim("orders:events", minid=f"{seven_days_ms}-0")

# Automate via XADD MAXLEN on every write (approximate is ~10% of exact cost)
r.xadd("orders:events", fields, maxlen=500_000, approximate=True)
```

### XREAD Blocking for Real-Time
```python
# Non-group consumer — reads from a position (used for replication/monitoring)
last_id = "$"   # Start from newest; use "0" to replay from beginning
while True:
    results = r.xread({"orders:events": last_id}, count=100, block=2000)
    if results:
        for stream, messages in results:
            for msg_id, fields in messages:
                observe(fields)
                last_id = msg_id
```

## Configuration

```conf
# redis.conf — streams-relevant settings
maxmemory 4gb
maxmemory-policy allkeys-lru   # Evict LRU when maxmemory hit — use noeviction if data must not be lost
save 60 1000                   # RDB snapshot every 60 s if 1000 writes — tune to RPO
appendonly yes                 # AOF for durability (set appendfsync to everysec for balance)
appendfsync everysec
```

## Performance

- Use `MAXLEN ~` (approximate trimming) in `XADD` — it is 3–5× faster than exact trimming.
- Batch reads: set `COUNT=50–500` in `XREADGROUP` to amortize round-trip cost.
- Pipeline `XADD` calls with Redis pipelining when ingesting high-velocity events.
- Monitor `XLEN` and PEL length (`XPENDING` count) — both growing unboundedly indicates consumer lag.

## Security

- Use ACL rules to restrict stream commands per service: producers get `XADD`; consumers get `XREADGROUP`, `XACK`, `XCLAIM`; no service needs `XDEL` or `XTRIM` in production.
- Enable TLS (`tls-port`, `tls-cert-file`, `tls-key-file`) for all client connections.
- Separate streams from cache in different Redis instances if different retention/eviction policies are needed.

## Testing

```python
# Use a real Redis via Testcontainers — fakeredis supports basic stream commands for unit tests
import fakeredis
r = fakeredis.FakeRedis()
r.xadd("test:stream", {"key": "value"})
r.xgroup_create("test:stream", "test-group", id="0")
entries = r.xreadgroup("test-group", "consumer-1", {"test:stream": ">"}, count=10)
assert len(entries[0][1]) == 1
r.xack("test:stream", "test-group", entries[0][1][0][0])
assert r.xpending("test:stream", "test-group")["pending"] == 0

# For integration: testcontainers-python with redis module
```

## Dos

- Use consumer groups for all production work queues — bare `XREAD` offers no group semantics.
- Include consumer name (hostname+pid) in `XREADGROUP` calls for PEL ownership tracking.
- Run a PEL reaper loop (XAUTOCLAIM) to recover messages from crashed consumers.
- Trim streams with `MAXLEN ~` in every `XADD` call to bound memory usage automatically.
- Monitor PEL depth and `XLEN` — treat unbounded growth as a production incident.

## Don'ts

- Don't use `DEL` on a stream to "reset" it in production — you lose the consumer group definitions.
- Don't use `XACK` before processing completes — an unacknowledged message is the safety net on crash.
- Don't omit `approximate=True` in XTRIM/XADD MAXLEN — exact trimming is significantly slower.
- Don't use Redis Streams as the sole store for data you cannot reconstruct — Redis persistence (AOF/RDB) must be configured and tested.
- Don't rely on Pub/Sub for any message that must survive a consumer restart — use Streams instead.
