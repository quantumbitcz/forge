# WebSocket Conventions

## Overview

WebSocket provides full-duplex, persistent connections over a single TCP connection. These conventions cover
connection lifecycle, heartbeats, reconnection, message framing, authentication, backpressure, and scaling
patterns to produce WebSocket servers that are reliable under network variability and production load.

## Architecture Patterns

### Connection Lifecycle

```
Client                          Server
  |                                |
  |-- HTTP Upgrade Request ------> |   (GET /ws, Upgrade: websocket)
  |<- 101 Switching Protocols ---- |
  |                                |
  |<======= WebSocket Frames =====>|   (OPEN — bidirectional)
  |                                |
  |-- Close Frame (1000) -------> |   (graceful close)
  |<- Close Frame (1000) --------- |
  |                                |   (CLOSED)
```

Always complete the closing handshake: send a Close frame and wait for the echoed Close before terminating
the TCP connection. Use close code `1000` (normal closure) for expected disconnects, `1001` (going away)
for server shutdown.

### Heartbeat / Ping-Pong

Use WebSocket-level ping frames every 30 seconds to detect stale connections:

```javascript
// Node.js server (ws library)
const HEARTBEAT_INTERVAL = 30_000;
const PONG_TIMEOUT = 10_000;

wss.on("connection", (ws) => {
  ws.isAlive = true;
  ws.on("pong", () => { ws.isAlive = true; });
});

setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) return ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, HEARTBEAT_INTERVAL);
```

Terminate (not close) unresponsive connections after missing a pong within `PONG_TIMEOUT`.

### Pub/Sub: Room / Topic Patterns

```javascript
// Server-side room management
const rooms = new Map(); // roomId -> Set<WebSocket>

function join(ws, roomId) {
  if (!rooms.has(roomId)) rooms.set(roomId, new Set());
  rooms.get(roomId).add(ws);
  ws.rooms = ws.rooms ?? new Set();
  ws.rooms.add(roomId);
}

function broadcast(roomId, message, excludeWs = null) {
  rooms.get(roomId)?.forEach((client) => {
    if (client !== excludeWs && client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(message));
    }
  });
}

function leave(ws, roomId) {
  rooms.get(roomId)?.delete(ws);
  if (rooms.get(roomId)?.size === 0) rooms.delete(roomId);
}

// On disconnect — clean up all rooms
ws.on("close", () => {
  ws.rooms?.forEach((roomId) => leave(ws, roomId));
});
```

## Configuration

### Message Framing

Prefer structured JSON for most use cases; use binary frames for high-throughput or media:

```javascript
// JSON framing with typed envelopes (client and server agree on shape)
const envelope = {
  type: "chat.message",   // namespaced event type
  id: crypto.randomUUID(), // message ID for deduplication
  timestamp: Date.now(),
  payload: { text: "Hello", channelId: "c1" },
};
ws.send(JSON.stringify(envelope));

// Binary framing (e.g., Uint8Array for sensor data)
const buffer = new ArrayBuffer(8);
const view = new DataView(buffer);
view.setFloat32(0, sensorValue);
ws.send(buffer);
```

Always include a `type` discriminator so receivers can route messages without schema inspection.

### Authentication

**Option 1 — Token in query parameter (simpler, less secure):**
```
wss://api.example.com/ws?token=eyJhbGci...
```
Only acceptable over TLS; tokens appear in server logs — use short-lived tokens (< 60s TTL).

**Option 2 — Token in first message (preferred):**
```javascript
// Client sends auth as the first message after connection
ws.onopen = () => {
  ws.send(JSON.stringify({ type: "auth", token: getAccessToken() }));
};

// Server — reject and close if first message is not a valid auth within 5s
const authTimeout = setTimeout(() => ws.close(4001, "Auth timeout"), 5000);
ws.once("message", async (raw) => {
  clearTimeout(authTimeout);
  const { type, token } = JSON.parse(raw);
  if (type !== "auth" || !(await validateToken(token))) {
    return ws.close(4001, "Unauthorized");
  }
  // Connection is now authenticated — register for events
});
```

Use custom close codes `4000-4999` for application-level errors.

## Performance

### Reconnection with Exponential Backoff

```javascript
class ReconnectingWebSocket {
  #attempts = 0;
  #maxDelay = 30_000;
  #baseDelay = 1_000;

  connect(url) {
    this.ws = new WebSocket(url);
    this.ws.onopen = () => { this.#attempts = 0; };
    this.ws.onclose = (event) => {
      if (event.code !== 1000) this.#scheduleReconnect(url); // don't retry normal close
    };
  }

  #scheduleReconnect(url) {
    const jitter = Math.random() * 1000;
    const delay = Math.min(this.#baseDelay * 2 ** this.#attempts + jitter, this.#maxDelay);
    this.#attempts++;
    setTimeout(() => this.connect(url), delay);
  }
}
```

Cap attempts at a maximum delay (30s) and add jitter to avoid thundering herd on server restart.

### Backpressure Handling

```javascript
// Server — check bufferedAmount before sending to avoid overloading slow clients
const MAX_BUFFER = 64 * 1024; // 64 KB

function safeSend(ws, message) {
  if (ws.bufferedAmount > MAX_BUFFER) {
    // Drop or queue; log for monitoring
    metrics.increment("ws.dropped_messages");
    return false;
  }
  ws.send(message);
  return true;
}

// For high-frequency streams, implement a sliding window drop policy:
// keep the latest N messages, discard older ones when buffer is full
```

## Security

- Always require WSS (TLS) in production; reject `ws://` connections
- Validate the `Origin` header on upgrade to prevent cross-site WebSocket hijacking
- Apply per-connection rate limits on incoming message frequency
- Re-validate auth tokens on reconnect — do not cache authorization across connections
- Set timeouts: unauthenticated connection close after 5s, idle connection close after configured idle period

```javascript
// Origin validation on upgrade
server.on("upgrade", (req, socket, head) => {
  const origin = req.headers.origin;
  if (!ALLOWED_ORIGINS.includes(origin)) {
    socket.write("HTTP/1.1 403 Forbidden\r\n\r\n");
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => wss.emit("connection", ws, req));
});
```

## Scaling

### Sticky Sessions vs Redis Pub/Sub

| Strategy | Pros | Cons |
|----------|------|------|
| Sticky sessions (LB affinity) | Simple, no external dependency | No failover if node restarts; uneven load |
| Redis pub/sub | Horizontal scale, failover safe | Extra infrastructure, latency overhead |

```javascript
// Redis pub/sub adapter (e.g., socket.io-adapter or manual)
const sub = redis.createClient();
const pub = redis.createClient();

sub.subscribe("room:c1");
sub.on("message", (channel, raw) => {
  const message = JSON.parse(raw);
  localClients.get(channel)?.forEach((ws) => ws.send(raw));
});

// When broadcasting, publish to Redis instead of local set
pub.publish("room:c1", JSON.stringify(envelope));
```

Use Redis pub/sub (or a message broker) for any deployment with more than one server instance.

## Testing

```
# Connection tests
- Upgrade succeeds with valid token, rejects with invalid/missing token (4001)
- Server closes unauthenticated connections after auth timeout
- Origin header validation: allowed origin connects, disallowed is rejected

# Message tests
- Valid envelope dispatched to correct handler
- Unknown message type logged and silently ignored (no crash)
- Malformed JSON closes connection with code 1007

# Lifecycle tests
- Heartbeat: terminate client that does not respond to ping within PONG_TIMEOUT
- Graceful close: server sends Close frame, client echoes, TCP closes cleanly
- Reconnection: simulate disconnect, assert client reconnects with backoff

# Scale tests
- 10,000 concurrent connections: memory stable, no file descriptor leak
- Broadcast to 1,000 clients: no backpressure violation for fast clients
```

## Dos

- Complete the WebSocket closing handshake — send Close, wait for echo
- Implement heartbeat ping/pong; terminate unresponsive clients
- Use typed message envelopes with a `type` discriminator field
- Include jitter in reconnection backoff to prevent thundering herd
- Check `bufferedAmount` before sending to fast-producing, slow-consuming connections
- Use Redis pub/sub or an equivalent broker when running multiple server instances
- Re-authenticate tokens on every new connection, not just the first

## Don'ts

- Don't use `ws://` (unencrypted) in any environment beyond local development
- Don't skip Origin validation on the HTTP upgrade request
- Don't store long-lived auth tokens in query parameters — use first-message auth
- Don't broadcast to all clients with a simple `wss.clients.forEach` in large deployments
- Don't retry with a fixed delay — use exponential backoff with jitter
- Don't ignore backpressure — unbounded send queues cause OOM on slow clients
- Don't rely on TCP keepalives alone — use application-level ping/pong
