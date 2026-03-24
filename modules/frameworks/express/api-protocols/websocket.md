# Express + WebSocket — API Protocol Binding

## Integration Setup
- Socket.IO: `socket.io` (server) + `socket.io-client` (client); attaches to existing HTTP server
- Raw WebSocket: `ws` package; attach `WebSocketServer` to the HTTP server via `handleProtocols`
- Redis adapter for multi-instance: `@socket.io/redis-adapter` + `ioredis`
- Peer auth middleware: `socketio-jwt` or custom `io.use()` middleware for token verification

## Framework-Specific Patterns
- Share the HTTP server: `const httpServer = createServer(app); const io = new Server(httpServer)`
- Namespace for domain isolation: `io.of("/chat")`, `io.of("/notifications")`
- Rooms for multi-cast: `socket.join(roomId)`, `io.to(roomId).emit(event, data)`
- Authentication middleware: `io.use((socket, next) => { /* verify JWT, attach user to socket.data */ })`
- Redis adapter: `io.adapter(createAdapter(pubClient, subClient))` — required for horizontally scaled deployments
- Graceful shutdown: call `io.close()` before `httpServer.close()` in SIGTERM handler

## Scaffolder Patterns
```
src/
  websocket/
    index.ts               # io setup, adapter, namespace registration
    namespaces/
      chat.namespace.ts    # io.of("/chat") + event handlers
      notifications.namespace.ts
    middleware/
      ws-auth.middleware.ts  # io.use() JWT verification
    adapters/
      redis-adapter.ts     # createAdapter factory
```

## Dos
- Validate all incoming event payloads with zod before processing
- Use rooms over broadcasting to all connected clients; minimise over-sending
- Store minimal state on `socket.data` — prefer Redis or database for persistent room state
- Emit versioned event names: `user:created:v1` to allow non-breaking evolution

## Don'ts
- Don't use Socket.IO polling transport in new deployments — configure `transports: ["websocket"]`
- Don't trust `socket.id` as a stable user identifier across reconnects
- Don't broadcast sensitive data to rooms without per-socket permission checks
- Don't skip the Redis adapter when running more than one process/pod
