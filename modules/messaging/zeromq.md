# ZeroMQ — Messaging Conventions

## Overview

ZeroMQ (ØMQ) is a lightweight, brokerless messaging library providing socket-like abstractions
for in-process, inter-process, TCP, and multicast messaging. Use it for low-latency microservice
communication, distributed computing, and real-time data pipelines where broker overhead is
unacceptable. ZeroMQ excels at patterns like pub/sub, request/reply, push/pull, and pipeline.
Avoid it when you need message persistence (use Kafka/RabbitMQ), guaranteed delivery, or when
operational simplicity of a managed broker outweighs the latency benefit.

## Architecture Patterns

### Request-Reply (REQ/REP)
```python
import zmq

# Server
context = zmq.Context()
socket = context.socket(zmq.REP)
socket.bind("tcp://*:5555")

while True:
    message = socket.recv_json()
    result = process(message)
    socket.send_json(result)

# Client
socket = context.socket(zmq.REQ)
socket.connect("tcp://server:5555")
socket.send_json({"action": "get_user", "id": 123})
response = socket.recv_json()
```

### Pub/Sub
```python
# Publisher
pub = context.socket(zmq.PUB)
pub.bind("tcp://*:5556")
pub.send_multipart([b"orders", json.dumps(order).encode()])

# Subscriber
sub = context.socket(zmq.SUB)
sub.connect("tcp://publisher:5556")
sub.setsockopt(zmq.SUBSCRIBE, b"orders")
topic, data = sub.recv_multipart()
```

### Push/Pull (Pipeline)
```python
# Ventilator (pushes work)
push = context.socket(zmq.PUSH)
push.bind("tcp://*:5557")
for task in tasks:
    push.send_json(task)

# Workers (pull work)
pull = context.socket(zmq.PULL)
pull.connect("tcp://ventilator:5557")
while True:
    task = pull.recv_json()
    process(task)
```

### Anti-pattern — using ZeroMQ as a message queue with persistence: ZeroMQ has no broker, no persistence, and no guaranteed delivery. Messages are lost if a subscriber isn't connected when published. For persistence, use Kafka or RabbitMQ.

## Configuration

```python
# Socket options
socket.setsockopt(zmq.RCVTIMEO, 5000)  # 5s receive timeout
socket.setsockopt(zmq.SNDTIMEO, 5000)  # 5s send timeout
socket.setsockopt(zmq.LINGER, 0)        # don't wait on close
socket.setsockopt(zmq.HWM, 10000)       # high water mark (backpressure)
```

## Performance

**High water mark (HWM):** Controls message buffering. Default is 1000. Set appropriately — too low drops messages, too high consumes memory.

**IO threads:** `context = zmq.Context(io_threads=4)` — increase for high-throughput scenarios.

**Multipart messages:** Use `send_multipart` for framing — it's more efficient than serializing into a single frame.

## Security

**CurveZMQ encryption:**
```python
server.curve_secretkey = server_secret
server.curve_publickey = server_public
server.curve_server = True

client.curve_secretkey = client_secret
client.curve_publickey = client_public
client.curve_serverkey = server_public
```

Never use ZeroMQ over untrusted networks without encryption. CurveZMQ provides both encryption and authentication.

## Testing

```python
def test_request_reply():
    ctx = zmq.Context()
    server = ctx.socket(zmq.REP)
    port = server.bind_to_random_port("tcp://127.0.0.1")

    client = ctx.socket(zmq.REQ)
    client.connect(f"tcp://127.0.0.1:{port}")

    client.send_json({"ping": True})
    msg = server.recv_json()
    assert msg == {"ping": True}

    server.close()
    client.close()
    ctx.term()
```

Use `inproc://` transport for in-process tests — it's fastest and requires no network.

## Dos
- Use the right socket pattern for your use case — REQ/REP for RPC, PUB/SUB for broadcast, PUSH/PULL for pipelines.
- Set `LINGER` to 0 on sockets used in request/reply — prevents hang on shutdown.
- Use `RCVTIMEO`/`SNDTIMEO` to prevent indefinite blocking on send/receive.
- Use `inproc://` for same-process communication — zero-copy, highest throughput.
- Use CurveZMQ for encryption on untrusted networks — ZeroMQ is plaintext by default.
- Use multipart messages for framing — separate routing, headers, and body into frames.
- Use `zmq.Poller` for multiplexing across multiple sockets.

## Don'ts
- Don't use ZeroMQ as a persistent message queue — messages are lost if recipients aren't connected.
- Don't connect PUB to SUB (wrong direction) — PUB binds, SUB connects (or use XPUB/XSUB for proxy).
- Don't ignore the "slow subscriber" problem in PUB/SUB — slow subscribers cause publisher memory growth; set HWM.
- Don't share sockets across threads — ZeroMQ sockets are not thread-safe; use one socket per thread.
- Don't forget to call `context.term()` — it cleans up background threads; skipping it causes hangs.
- Don't use REQ/REP for async communication — it enforces strict send/receive alternation; use DEALER/ROUTER for async.
- Don't expose ZeroMQ sockets to the internet without CurveZMQ — they accept arbitrary connections by default.
