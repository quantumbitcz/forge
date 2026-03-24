# Spring RabbitMQ — Messaging Binding

## Integration Setup
- Add `spring-boot-starter-amqp`; configure `spring.rabbitmq.host/port/username/password`
- For retry: add `spring-retry` and `@EnableRetry` on a configuration class
- For JSON messages: register `Jackson2JsonMessageConverter` as a bean — Spring Boot auto-configures it

## Framework-Specific Patterns
- Annotate listener methods with `@RabbitListener(queues = ["queue-name"])`; place in `@Service` beans
- Use `@RabbitHandler` on methods within a `@RabbitListener`-annotated class for multi-type dispatch
- Declare exchanges, queues, and bindings as beans: `DirectExchange`, `Queue`, `Binding` via `BindingBuilder`
- Inject `RabbitTemplate` for publishing; use `convertAndSend(exchange, routingKey, payload)`
- Configure retry with `SimpleRetryPolicy` + `ExponentialBackOffPolicy` via `RetryOperationsInterceptor`
- Dead-letter queue: declare queue with `x-dead-letter-exchange` and `x-dead-letter-routing-key` args
- For request/reply: use `RabbitTemplate.convertSendAndReceive()`; set `replyTimeout`

## Scaffolder Patterns
```
src/main/kotlin/com/example/
  messaging/
    rabbitmq/
      UserEventPublisher.kt    # RabbitTemplate wrapper
      UserEventConsumer.kt     # @RabbitListener
      dto/
        UserCreatedEvent.kt    # event payload — versioned
  config/
    RabbitMqConfig.kt          # Exchange, Queue, Binding beans; MessageConverter
    RabbitRetryConfig.kt       # RetryOperationsInterceptor, DLQ declaration
```

## Dos
- Use `Jackson2JsonMessageConverter` as the default message converter; include `__TypeId__` header
- Declare topology (exchanges, queues, bindings) as Spring beans — not ad-hoc at publish time
- Set `prefetch` count on the container factory to limit in-flight messages per consumer
- Monitor queue depth via Micrometer `RabbitMetrics` and alert on DLQ message count

## Don'ts
- Don't use the default `SimpleMessageConverter` with plain strings in new services
- Don't acknowledge messages manually unless you have a specific at-least-once requirement with custom ACK logic
- Don't use `RabbitTemplate` inside `@RabbitListener` for replies without configuring a reply address
- Don't declare topology only in RabbitMQ UI — always codify it in `RabbitMqConfig`
