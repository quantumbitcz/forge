# MQTT — Messaging Conventions

## Overview

MQTT (Message Queuing Telemetry Transport) is a lightweight pub/sub messaging protocol designed
for constrained devices and unreliable networks. Use it for IoT sensor data, telemetry,
home automation, fleet tracking, and device-to-cloud communication. MQTT excels at minimal
bandwidth overhead (2-byte header), persistent sessions, retained messages, and Last Will
and Testament (LWT) for device presence. Avoid MQTT for high-throughput stream processing
(use Kafka), complex routing patterns (use RabbitMQ), or when HTTP webhooks suffice.

## Architecture Patterns

### Topic Hierarchy
```
# Hierarchical topic naming
{org}/{site}/{device_type}/{device_id}/{measurement}

sensors/factory-1/temperature/sensor-001/reading
sensors/factory-1/humidity/sensor-002/reading
devices/fleet-a/truck-123/gps/location
devices/fleet-a/truck-123/engine/status

# Wildcards
sensors/factory-1/+/+/reading      # single-level: any device_type and device_id
sensors/factory-1/#                 # multi-level: all topics under factory-1
```

### Publishing (Python — paho-mqtt)
```python
import paho.mqtt.client as mqtt
import json

client = mqtt.Client(client_id="publisher-001", protocol=mqtt.MQTTv5)
client.tls_set(ca_certs="/etc/ssl/ca.pem", certfile="/etc/ssl/client.pem", keyfile="/etc/ssl/client-key.pem")
client.username_pw_set("device", "password")
client.connect("mqtt.internal", 8883)

# QoS 1: at-least-once delivery (most common for telemetry)
payload = json.dumps({"temperature": 22.5, "humidity": 45.2, "timestamp": "2026-03-26T10:00:00Z"})
client.publish("sensors/factory-1/temperature/sensor-001/reading", payload, qos=1, retain=False)
```

### Subscribing
```python
def on_message(client, userdata, msg):
    data = json.loads(msg.payload)
    logger.info(f"Topic: {msg.topic}, Data: {data}")
    store_reading(msg.topic, data)

def on_connect(client, userdata, flags, rc, properties=None):
    # Re-subscribe on reconnect to restore subscriptions after disconnect
    client.subscribe("sensors/factory-1/#", qos=1)

client = mqtt.Client(client_id="consumer-001", protocol=mqtt.MQTTv5, clean_start=False)
client.on_connect = on_connect
client.on_message = on_message
client.connect("mqtt.internal", 8883)
client.loop_forever()
```

### Last Will and Testament (Device Presence)
```python
client.will_set(
    topic="devices/fleet-a/truck-123/status",
    payload=json.dumps({"status": "offline", "timestamp": "..."}),
    qos=1,
    retain=True
)
# If this client disconnects unexpectedly, broker publishes the will message
```

### Retained Messages (Latest Known State)
```python
# Retained message: broker stores the last message on a topic
# New subscribers immediately receive the latest value
client.publish("devices/truck-123/gps/location",
    json.dumps({"lat": 48.85, "lon": 2.35}),
    qos=1, retain=True)
```

### Anti-pattern — using QoS 2 for high-frequency telemetry: QoS 2 (exactly-once) adds a 4-step handshake per message. For temperature readings every second, QoS 1 (at-least-once) with idempotent consumers is far more efficient. Reserve QoS 2 for critical commands (firmware update triggers, actuator commands).

## Configuration

**Mosquitto broker configuration:**
```conf
# mosquitto.conf
listener 8883
protocol mqtt
cafile /etc/mosquitto/ca.pem
certfile /etc/mosquitto/server.pem
keyfile /etc/mosquitto/server-key.pem
require_certificate true

max_connections 10000
max_inflight_messages 20
max_queued_messages 1000
message_size_limit 262144      # 256 KB

persistence true
persistence_location /var/lib/mosquitto/

# Authentication
password_file /etc/mosquitto/passwd
acl_file /etc/mosquitto/acl
```

**EMQX / HiveMQ for production scale:**
```yaml
# EMQX Docker
emqx:
  image: emqx/emqx:5
  ports:
    - "1883:1883"    # MQTT
    - "8883:8883"    # MQTT over TLS
    - "8083:8083"    # MQTT over WebSocket
    - "18083:18083"  # Dashboard
  environment:
    EMQX_LOADED_PLUGINS: "emqx_auth_mnesia,emqx_dashboard"
```

**QoS levels:**
- QoS 0: fire-and-forget (no guarantee) — use for non-critical metrics
- QoS 1: at-least-once (default for telemetry) — consumer must be idempotent
- QoS 2: exactly-once (4-step handshake) — reserve for critical commands

## Performance

**Keep payloads small:** MQTT is designed for constrained networks. Use compact formats (JSON without whitespace, CBOR, MessagePack, or Protobuf) and send only changed values.

**Persistent sessions (`clean_start=False`):** Broker queues messages for offline clients with persistent sessions. Set `session_expiry_interval` to limit queue growth.

**Shared subscriptions (MQTT 5.0) for load balancing:**
```python
# Multiple consumers share the same subscription — broker distributes messages
client.subscribe("$share/workers/sensors/factory-1/#", qos=1)
```

**Topic aliases (MQTT 5.0):** Reduce per-message overhead by replacing long topic strings with short integer aliases after the first message.

**Batch telemetry at the device:** Instead of publishing every reading immediately, batch 10-60 seconds of readings and publish as a single message to reduce connection overhead.

## Security

**Always use TLS (port 8883):** Never use plaintext MQTT (port 1883) on public networks.

**Client certificate authentication (mTLS):**
```python
client.tls_set(
    ca_certs="/etc/ssl/ca.pem",
    certfile="/etc/ssl/device.pem",
    keyfile="/etc/ssl/device-key.pem"
)
```

**ACL (Access Control Lists):**
```conf
# Mosquitto ACL
user device-001
topic read sensors/factory-1/temperature/device-001/#
topic write sensors/factory-1/temperature/device-001/#

user admin
topic readwrite #
```

**Unique client IDs:** If two clients connect with the same client ID, the broker disconnects the first. Use device serial numbers or UUIDs as client IDs.

**Payload encryption:** For sensitive data, encrypt payloads at the application layer (AES-256-GCM) in addition to TLS transport encryption.

## Testing

**Mosquitto test broker:**
```bash
docker run -p 1883:1883 -p 9001:9001 eclipse-mosquitto:2 \
  mosquitto -c /mosquitto-no-auth.conf
```

**Python test with pytest:**
```python
import paho.mqtt.client as mqtt
import pytest
import time

@pytest.fixture
def mqtt_client():
    client = mqtt.Client(client_id="test", protocol=mqtt.MQTTv5)
    client.connect("localhost", 1883)
    client.loop_start()
    yield client
    client.loop_stop()
    client.disconnect()

def test_publish_subscribe(mqtt_client):
    received = []
    mqtt_client.on_message = lambda c, u, msg: received.append(json.loads(msg.payload))
    mqtt_client.subscribe("test/topic", qos=1)
    time.sleep(0.1)
    mqtt_client.publish("test/topic", json.dumps({"value": 42}), qos=1)
    time.sleep(0.5)
    assert len(received) == 1
    assert received[0]["value"] == 42
```

Test with a local Mosquitto container. Test QoS levels, retained messages, LWT behavior, and reconnection with persistent sessions.

## Dos
- Use hierarchical topic naming (`org/site/device/measurement`) — enables wildcard subscriptions and ACL patterns.
- Use QoS 1 for telemetry and QoS 0 for non-critical metrics — QoS 2 is rarely needed.
- Use retained messages for "latest known state" queries (device status, last GPS position).
- Use Last Will and Testament for device presence detection — the broker handles disconnect events.
- Use shared subscriptions (MQTT 5.0) to distribute workload across multiple consumer instances.
- Use mTLS for device authentication in production — passwords are weak for IoT at scale.
- Set `session_expiry_interval` for persistent sessions to prevent unbounded queue growth.

## Don'ts
- Don't use QoS 2 for high-frequency telemetry — the 4-step handshake adds latency and overhead.
- Don't use plaintext MQTT (port 1883) on public networks — always use TLS (port 8883).
- Don't create flat topic hierarchies — `sensordata` is not filterable; `sensors/site/type/id/measurement` is.
- Don't use the same client ID for multiple devices — the broker disconnects the previous client.
- Don't send large payloads (> 256 KB) over MQTT — use a reference pattern (store in object storage, publish the reference).
- Don't subscribe to `#` (all topics) in production applications — it receives every message on the broker.
- Don't rely on MQTT for guaranteed ordering across topics — ordering is only guaranteed within a single connection and QoS level.
