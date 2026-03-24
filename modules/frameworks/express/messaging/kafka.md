# Express + KafkaJS — Messaging Binding

## Integration Setup
- Add `kafkajs`; create a `Kafka` instance with `clientId` and `brokers` array from config
- Producers and consumers are long-lived — create once at app startup, not per request
- Graceful shutdown: call `producer.disconnect()` and `consumer.disconnect()` in SIGTERM handler

## Framework-Specific Patterns
- Producer: `kafka.producer({ idempotent: true })`; call `await producer.connect()` on startup
- Send messages: `await producer.send({ topic, messages: [{ key, value: JSON.stringify(payload) }] })`
- Consumer: `kafka.consumer({ groupId })`; call `await consumer.subscribe({ topic, fromBeginning: false })`
- `eachMessage`: process one message at a time with `async ({ topic, partition, message }) => {...}`
- `eachBatch`: process a batch with `async ({ batch, resolveOffset, heartbeat }) => {...}`; call `heartbeat()` for long batches
- Retry with exponential backoff: configure `retry` option on the `Kafka` constructor
- Dead-letter: on unrecoverable error, produce to `<topic>.dlq` before committing the offset

## Scaffolder Patterns
```
src/
  messaging/
    kafka/
      client.ts              # Kafka instance, singleton
      producer.ts            # typed producer wrapper with connect/disconnect
      consumers/
        user-events.consumer.ts  # subscribe + eachMessage handler
      dlq.ts                 # DLQ producer helper
  app.ts                     # connect producer/consumer at startup
  shutdown.ts                # disconnect on SIGTERM/SIGINT
```

## Dos
- Use `idempotent: true` on the producer to prevent duplicate messages on retries
- Use typed message value interfaces; serialize/deserialize with a schema-aware helper
- Set `sessionTimeout` and `heartbeatInterval` on the consumer to match broker config
- Log `topic`, `partition`, and `offset` on every consumed message for traceability

## Don'ts
- Don't create new Kafka producer/consumer instances per HTTP request
- Don't commit offsets manually with `eachMessage` — KafkaJS handles this automatically unless `autoCommit: false`
- Don't ignore `CRASH` events on the consumer — subscribe to `consumer.events.CRASH` and restart
- Don't use `fromBeginning: true` in production consumers without replaying logic
