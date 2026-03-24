# ASP.NET + MassTransit/RabbitMQ — Messaging Binding

## Integration Setup
- Add `MassTransit` + `MassTransit.RabbitMQ`
- Configure: `builder.Services.AddMassTransit(x => { x.AddConsumers(Assembly.GetEntryAssembly()); x.UsingRabbitMq(...) })`
- Outbox pattern: add `MassTransit.EntityFrameworkCore` + `x.AddEntityFrameworkOutbox<DbContext>()`
- Saga: add `MassTransit.EntityFrameworkCore` for persistence; register with `x.AddSagaStateMachine<TStateMachine, TState>()`

## Framework-Specific Patterns
- Consumer: implement `IConsumer<TMessage>` and override `Consume(ConsumeContext<TMessage> context)`
- Publish: inject `IPublishEndpoint`; call `await endpoint.Publish(new UserCreated(...))`
- Send to specific queue: inject `ISendEndpointProvider`; call `await provider.Send(destinationAddress, command)`
- Outbox: configure via `x.AddEntityFrameworkOutbox<AppDbContext>(o => { o.UsePostgres(); o.UseBusOutbox() })` — ensures at-least-once delivery with DB transaction
- Saga state machine: `public class OrderStateMachine : MassTransitStateMachine<OrderState>` with `State<OrderState>`, `Event<T>`, `During(...).When(...).Then(...)`
- Retry/fault: configure retry on consumer: `e.UseMessageRetry(r => r.Intervals(1000, 5000, 15000))`

## Scaffolder Patterns
```
src/
  Messaging/
    Consumers/
      UserCreatedConsumer.cs    # IConsumer<UserCreated>
    Contracts/
      UserCreated.cs            # message contract (immutable record)
    Sagas/
      OrderStateMachine.cs      # MassTransitStateMachine<OrderState>
      OrderState.cs             # SagaStateMachineInstance
  Infrastructure/
    MassTransitConfig.cs        # extension method registering MassTransit
```

## Dos
- Define message contracts as immutable C# records in a shared `Contracts` assembly/namespace
- Use the outbox pattern for all consumers that write to the database — prevents dual writes
- Name consumers and exchanges explicitly in `UsingRabbitMq` config; don't rely on MassTransit defaults for production topology
- Use `IPublishEndpoint` for events and `ISendEndpointProvider` for commands

## Don'ts
- Don't inject `IBus` directly for publishing — inject `IPublishEndpoint` or `ISendEndpointProvider` instead
- Don't mutate saga state outside of `During(...).When(...).Then(...)` blocks
- Don't skip fault consumers for critical messages — define `IConsumer<Fault<TMessage>>` to handle failures
- Don't use raw RabbitMQ client (`RabbitMQ.Client`) alongside MassTransit — pick one abstraction
