# NestJS + RabbitMQ — Messaging Binding

## Integration Setup

Two integration options:
1. **`@nestjs/microservices` RMQ transport** — built-in, simpler, good for basic pub/sub and RPC
2. **`@golevelup/nestjs-rabbitmq`** — richer, supports exchanges, routing keys, dead-letter, and concurrent consumers

```bash
# Option 1: built-in
npm install amqplib amqp-connection-manager
npm install -D @types/amqplib

# Option 2: golevelup (preferred for advanced routing)
npm install @golevelup/nestjs-rabbitmq
```

## Option 1: Built-in RMQ Transport

### Microservice Setup
```typescript
// main.ts
const app = await NestFactory.createMicroservice<MicroserviceOptions>(AppModule, {
  transport: Transport.RMQ,
  options: {
    urls: [process.env.RABBITMQ_URL ?? 'amqp://localhost:5672'],
    queue: 'orders_queue',
    queueOptions: { durable: true },
    prefetchCount: 10,
    noAck: false,          // manual ack for reliability
  },
});
await app.listen();
```

### Consumer Controller
```typescript
@Controller()
export class OrdersConsumerController {
  @EventPattern('order.created')
  async handleOrderCreated(@Payload() data: OrderCreatedEvent): Promise<void> {
    await this.ordersService.process(data);
  }

  @MessagePattern('order.status')
  async getStatus(@Payload() data: { orderId: string }): Promise<OrderStatus> {
    return this.ordersService.getStatus(data.orderId);
  }
}
```

## Option 2: @golevelup/nestjs-rabbitmq

### Module Setup
```typescript
// app.module.ts
@Module({
  imports: [
    RabbitMQModule.forRootAsync(RabbitMQModule, {
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        uri: config.get<string>('RABBITMQ_URL'),
        exchanges: [
          { name: 'orders', type: 'topic' },
          { name: 'orders.dlx', type: 'direct' },
        ],
        connectionInitOptions: { wait: true, timeout: 10000 },
        prefetchCount: 10,
        enableControllerDiscovery: true,
      }),
    }),
  ],
})
export class AppModule {}
```

### Consumer with Exchange Routing
```typescript
@Injectable()
export class OrdersConsumer {
  private readonly logger = new Logger(OrdersConsumer.name);

  constructor(private readonly ordersService: OrdersService) {}

  @RabbitSubscribe({
    exchange: 'orders',
    routingKey: 'order.created',
    queue: 'orders-service.order-created',
    queueOptions: {
      durable: true,
      deadLetterExchange: 'orders.dlx',
      deadLetterRoutingKey: 'order.created.failed',
    },
  })
  async handleOrderCreated(payload: OrderCreatedEvent): Promise<void> {
    this.logger.log(`Processing order ${payload.orderId}`);
    await this.ordersService.process(payload);
  }

  @RabbitRPC({
    exchange: 'orders',
    routingKey: 'order.status.request',
    queue: 'orders-service.status-rpc',
  })
  async getOrderStatus(data: { orderId: string }): Promise<OrderStatus> {
    return this.ordersService.getStatus(data.orderId);
  }
}
```

### Publisher
```typescript
@Injectable()
export class OrdersPublisher {
  constructor(private readonly amqpConnection: AmqpConnection) {}

  async publishOrderCreated(order: Order): Promise<void> {
    await this.amqpConnection.publish('orders', 'order.created', {
      orderId: order.id,
      userId: order.userId,
      totalCents: order.totalCents,
    });
  }
}
```

## Scaffolder Patterns
```
src/
  orders/
    orders.module.ts
    orders.consumer.ts             # @RabbitSubscribe / @RabbitRPC handlers
    orders.publisher.ts            # AmqpConnection.publish wrapper
    orders.service.ts
```

## Dos
- Set `durable: true` on queues and exchanges so they survive broker restarts
- Use `deadLetterExchange` on queues to route failed messages to a DLQ automatically
- Use `prefetchCount` to limit concurrent message processing per consumer instance
- Use routing keys that follow a `domain.event` naming pattern (e.g., `order.created`)

## Don'ts
- Don't use `noAck: true` (auto-ack) for critical workflows — use manual ack for reliability
- Don't create exchanges or queues imperatively at runtime — declare them in module config
- Don't publish directly to a queue — publish to an exchange and let routing keys determine the queue
- Don't ignore connection errors — subscribe to the connection AMQP error event and alert
