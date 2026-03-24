# NestJS + Kafka — Messaging Binding

## Integration Setup
- `@nestjs/microservices` (built-in Kafka transport via `kafkajs`)
- Kafka transport is a first-class citizen in NestJS microservices

## Framework-Specific Patterns

### Kafka Microservice or Hybrid Consumer

Pure Kafka microservice:
```typescript
// main.ts
const app = await NestFactory.createMicroservice<MicroserviceOptions>(AppModule, {
  transport: Transport.KAFKA,
  options: {
    client: {
      clientId: process.env.SERVICE_NAME,
      brokers: [process.env.KAFKA_BROKER ?? 'localhost:9092'],
    },
    consumer: {
      groupId: `${process.env.SERVICE_NAME}-consumer`,
    },
  },
});
await app.listen();
```

Hybrid (HTTP + Kafka):
```typescript
app.connectMicroservice<MicroserviceOptions>({
  transport: Transport.KAFKA,
  options: {
    client: { clientId: 'orders-service', brokers: ['kafka:9092'] },
    consumer: { groupId: 'orders-consumer' },
  },
});
await app.startAllMicroservices();
await app.listen(3000);
```

### Consumer Controller

```typescript
// orders/orders.consumer.controller.ts
@Controller()
export class OrdersConsumerController {
  private readonly logger = new Logger(OrdersConsumerController.name);

  constructor(private readonly ordersService: OrdersService) {}

  @EventPattern('user.created')
  async handleUserCreated(@Payload() data: UserCreatedEvent): Promise<void> {
    this.logger.log(`Received user.created event for userId=${data.userId}`);
    await this.ordersService.initializeUserProfile(data.userId);
  }

  @MessagePattern('order.getStatus')
  async getOrderStatus(@Payload() data: { orderId: string }): Promise<OrderStatusResponse> {
    return this.ordersService.getStatus(data.orderId);
  }
}
```

### Producer (ClientProxy)

```typescript
// app.module.ts — register the Kafka producer client
@Module({
  imports: [
    ClientsModule.registerAsync([{
      name: 'KAFKA_PRODUCER',
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        transport: Transport.KAFKA,
        options: {
          client: {
            clientId: 'orders-producer',
            brokers: [config.get<string>('KAFKA_BROKER')],
          },
          producer: { idempotent: true },
        },
      }),
    }]),
  ],
})
export class AppModule {}

// orders/orders.service.ts
@Injectable()
export class OrdersService implements OnModuleDestroy {
  constructor(
    @Inject('KAFKA_PRODUCER') private readonly kafkaClient: ClientKafka,
  ) {}

  async onModuleInit(): Promise<void> {
    // Subscribe to reply topics for request-reply patterns
    this.kafkaClient.subscribeToResponseOf('order.getStatus');
    await this.kafkaClient.connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.kafkaClient.close();
  }

  async publishOrderCreated(order: Order): Promise<void> {
    await firstValueFrom(
      this.kafkaClient.emit('order.created', {
        key: order.id,
        value: { orderId: order.id, userId: order.userId, totalCents: order.totalCents },
      }),
    );
  }
}
```

## Dead-Letter Handling

```typescript
@EventPattern('order.created')
async handleOrderCreated(@Payload() data: OrderCreatedEvent): Promise<void> {
  try {
    await this.ordersService.processOrder(data);
  } catch (error) {
    this.logger.error(`Failed to process order ${data.orderId}`, error);
    await firstValueFrom(
      this.kafkaClient.emit('order.created.dlq', { ...data, error: (error as Error).message }),
    );
  }
}
```

## Scaffolder Patterns
```
src/
  orders/
    orders.module.ts
    orders.consumer.controller.ts    # @EventPattern / @MessagePattern handlers
    orders.service.ts
  app.module.ts                      # ClientsModule.registerAsync([...])
```

## Dos
- Use `idempotent: true` on the producer to prevent duplicate messages on retries
- Use `@Payload()` to extract the message value — `@Ctx()` for Kafka context metadata (topic, partition, offset)
- Log topic, partition, and offset on every consumed message for traceability
- Use `firstValueFrom()` to await `ClientProxy.emit()` — it returns an Observable

## Don'ts
- Don't create new Kafka client instances per request — use the module-registered `ClientProxy`
- Don't swallow consumer errors silently — publish to a DLQ topic for failed messages
- Don't use `subscribe()` directly on `ClientProxy.emit()` — use `firstValueFrom()` or `lastValueFrom()`
- Don't forget `await this.kafkaClient.connect()` in `onModuleInit()` for producer/reply subscriptions
