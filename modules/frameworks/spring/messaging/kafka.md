# Spring Kafka — Messaging Binding

## Integration Setup
- Add `spring-kafka`; configure `spring.kafka.bootstrap-servers`, consumer `group-id`, and `auto-offset-reset`
- Add `spring-retry` for `@RetryableTopic` support
- For Spring Cloud Stream: add `spring-cloud-starter-stream-kafka` and define `function` beans

## Framework-Specific Patterns
- Annotate listener methods with `@KafkaListener(topics = ["topic"], groupId = "group")`; run in `@Service` beans
- Use `KafkaTemplate<K, V>` for producing; prefer `sendAndWait` only in tests — use `ListenableFuture` / coroutine `.await()` in production
- Configure serializers/deserializers explicitly: `JsonSerializer`/`JsonDeserializer` with trusted packages set
- Dead-letter topics: annotate listener with `@RetryableTopic(attempts = 3, backoff = @Backoff(delay = 1000))`; DLT handler annotated with `@DltHandler`
- For exactly-once: set `isolation.level=read_committed` on consumer and `enable.idempotence=true` on producer
- Spring Cloud Stream: define `Consumer<T>`, `Function<T, R>`, `Supplier<T>` beans; bind via `spring.cloud.stream.bindings`

## Scaffolder Patterns
```
src/main/kotlin/com/example/
  messaging/
    kafka/
      UserEventProducer.kt     # KafkaTemplate wrapper
      UserEventConsumer.kt     # @KafkaListener
      UserEventDltHandler.kt   # @DltHandler
      dto/
        UserCreatedEvent.kt    # event payload — versioned
  config/
    KafkaConfig.kt             # ConsumerFactory, ProducerFactory, KafkaTemplate beans
    KafkaTopicConfig.kt        # NewTopic beans for topic creation
```

## Dos
- Define event payloads as immutable data classes with a `schemaVersion` field
- Use topic naming convention: `<domain>.<aggregate>.<event>` (e.g., `user.account.created`)
- Configure consumer concurrency via `@KafkaListener(concurrency = "3")`
- Instrument with Micrometer: `KafkaClientMetrics` for consumer lag monitoring

## Don'ts
- Don't use `enable.auto.commit=true` in production — commit manually after processing
- Don't deserialize to `Object` with wildcards; always specify trusted packages for `JsonDeserializer`
- Don't perform blocking I/O inside a `@KafkaListener` without a dedicated thread pool
- Don't let consumer lag accumulate silently — alert on consumer lag metric
