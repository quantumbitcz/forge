# InfluxDB Best Practices

## Overview
InfluxDB is a purpose-built time-series database optimized for high-volume ingest of timestamped data: metrics, IoT sensor readings, application telemetry, and financial tick data. Use it when your primary access pattern is "write many points, query by time range with aggregation." Avoid InfluxDB for general-purpose relational data, complex joins, or workloads where ClickHouse or TimescaleDB (PostgreSQL-based) better fits your existing stack.

## Architecture Patterns

**Line protocol for high-throughput ingest:**
```
// measurement,tag_key=tag_value field_key=field_value timestamp
cpu,host=server01,region=us-east usage_idle=95.2,usage_user=4.1 1711036800000000000
cpu,host=server02,region=eu-west usage_idle=88.7,usage_user=10.5 1711036800000000000
```

**Bucket + measurement design:**
```
Bucket: monitoring (retention: 30d)
  ├── cpu      (tags: host, region)
  ├── memory   (tags: host, region)
  └── disk     (tags: host, mount)

Bucket: iot_sensors (retention: 1y)
  ├── temperature (tags: device_id, location)
  └── humidity    (tags: device_id, location)
```

**Flux queries (InfluxDB 2.x — deprecated in 3.x, prefer SQL for new deployments):**
```flux
from(bucket: "monitoring")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "cpu" and r.host == "server01")
  |> aggregateWindow(every: 5m, fn: mean)
  |> yield()
```

**SQL queries (InfluxDB 3.x / IOx):**
```sql
SELECT host, time_bucket('5 minutes', time) AS bucket,
       AVG(usage_idle) AS avg_idle
FROM cpu
WHERE time > now() - INTERVAL '1 hour'
GROUP BY host, bucket
ORDER BY bucket;
```

**Downsampling tasks for long-term retention:**
```flux
option task = {name: "downsample_cpu", every: 1h}

from(bucket: "monitoring")
  |> range(start: -task.every)
  |> filter(fn: (r) => r._measurement == "cpu")
  |> aggregateWindow(every: 1h, fn: mean)
  |> to(bucket: "monitoring_longterm")
```

**Anti-pattern — high-cardinality tags:** Tags like `user_id` or `request_id` with millions of unique values cause series explosion, degrading write and query performance. Use fields for high-cardinality values.

## Configuration

**Bucket with retention policy:**
```bash
influx bucket create --name monitoring --retention 30d --org myorg
```

**Write batching (client-side):**
```python
from influxdb_client import InfluxDBClient, WriteOptions

client = InfluxDBClient(url="http://influxdb:8086", token="...", org="myorg")
write_api = client.write_api(write_options=WriteOptions(
    batch_size=5000,
    flush_interval=1000,    # ms
    jitter_interval=500,    # ms — prevents thundering herd
    retry_interval=5000
))
```

**Production tuning:**
```toml
[storage]
  cache-max-memory-size = "1g"
  cache-snapshot-memory-size = "25m"
  compact-throughput = "48m"

[http]
  max-body-size = 25000000  # 25MB
  write-timeout = "30s"
```

## Performance

**Tag vs field selection:**
- **Tags**: indexed, low cardinality (hostname, region, sensor_type). Used in `WHERE` and `GROUP BY`.
- **Fields**: not indexed, any cardinality (temperature, cpu_usage, latency). Used for aggregation.

**Batch writes — never write one point at a time:**
```python
points = [Point("cpu").tag("host", h).field("usage", v).time(t) for h, v, t in data]
write_api.write(bucket="monitoring", record=points)
```

**Time-range filtering is essential:** Always filter by time range first — InfluxDB organizes data by time, and queries without time bounds scan all data.

**Shard group duration:** Align shard group duration with query patterns. Short retention (7d) → 1d shards. Long retention (1y) → 7d shards. Misaligned shards cause unnecessary I/O.

## Security

**Token-based authentication (InfluxDB 2.x+):**
```bash
influx auth create --org myorg --read-buckets --write-buckets --description "app-token"
```

**Separate read and write tokens:** Application writers get write-only tokens; dashboards get read-only tokens.

**TLS for all connections:**
```toml
[http]
  https-enabled = true
  https-certificate = "/etc/ssl/influxdb.crt"
  https-private-key = "/etc/ssl/influxdb.key"
```

**Never embed tokens in client-side code.** Store in environment variables or a secrets manager.

## Testing

Use **Testcontainers** for integration tests:
```python
from testcontainers.influxdb import InfluxDbContainer

with InfluxDbContainer("influxdb:2.7") as influxdb:
    client = influxdb.get_client()
    # write test data, query, assert
```

For unit tests, mock the write/query API. Test downsampling tasks by writing known data points and verifying aggregated output. Validate that high-cardinality tags don't slip through by asserting series cardinality after test writes.

## Dos
- Design tags for low cardinality (< 100k unique values per tag) — tags are indexed and affect series count.
- Always write in batches — single-point writes incur per-request overhead that kills throughput.
- Use downsampling tasks to reduce storage costs and speed up long-range queries.
- Filter by time range first in every query — it's the primary storage axis.
- Monitor series cardinality with `SHOW SERIES CARDINALITY` — exponential growth signals a schema problem.
- Use Flux tasks or continuous queries for pre-aggregation of common dashboard queries.
- Set appropriate retention policies per bucket — don't store raw metrics forever.

## Don'ts
- Don't use high-cardinality values (user IDs, UUIDs, IP addresses) as tags — they cause series cardinality explosion.
- Don't write one point at a time — batch writes are 100x more efficient.
- Don't query without a time range — unbounded queries scan all data and timeout.
- Don't use InfluxDB for relational data with joins — it has no JOIN support; use PostgreSQL for that.
- Don't ignore the `_measurement` naming convention — poorly named measurements make dashboards unmaintainable.
- Don't skip retention policies — unbounded data growth eventually fills disk and crashes the instance.
- Don't mix metrics granularity in one bucket — nanosecond precision metrics and daily summaries should live in separate buckets with different retention.
