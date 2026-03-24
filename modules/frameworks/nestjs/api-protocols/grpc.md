# NestJS + gRPC — API Protocol Binding

## Integration Setup
- `@nestjs/microservices` + `@grpc/grpc-js` + `@grpc/proto-loader`
- Define service contracts in `.proto` files
- NestJS gRPC transport handles serialization/deserialization

## Framework-Specific Patterns

### gRPC Microservice or Hybrid App

Pure gRPC microservice:
```typescript
// main.ts
const app = await NestFactory.createMicroservice<MicroserviceOptions>(AppModule, {
  transport: Transport.GRPC,
  options: {
    package: 'users',
    protoPath: join(__dirname, '../proto/users.proto'),
    url: '0.0.0.0:5000',
  },
});
await app.listen();
```

Hybrid app (HTTP + gRPC):
```typescript
const app = await NestFactory.create(AppModule);
app.connectMicroservice<MicroserviceOptions>({
  transport: Transport.GRPC,
  options: {
    package: 'users',
    protoPath: join(__dirname, '../proto/users.proto'),
    url: '0.0.0.0:5000',
  },
});
await app.startAllMicroservices();
await app.listen(3000);
```

### Proto File
```protobuf
// proto/users.proto
syntax = "proto3";
package users;

service UsersService {
  rpc FindOne (FindOneRequest) returns (User);
  rpc CreateUser (CreateUserRequest) returns (User);
  rpc ListUsers (ListUsersRequest) returns (stream User);
}

message User {
  string id = 1;
  string name = 2;
  string email = 3;
}

message FindOneRequest { string id = 1; }
message CreateUserRequest { string name = 1; string email = 2; }
message ListUsersRequest { int32 page = 1; int32 limit = 2; }
```

### gRPC Controller (Server-Side Handler)
```typescript
// users/users.grpc.controller.ts
@Controller()
export class UsersGrpcController {
  constructor(private readonly usersService: UsersService) {}

  @GrpcMethod('UsersService', 'FindOne')
  async findOne(data: FindOneRequest): Promise<User> {
    return this.usersService.findOne(data.id);
  }

  @GrpcMethod('UsersService', 'CreateUser')
  async createUser(data: CreateUserRequest): Promise<User> {
    return this.usersService.create(data);
  }

  @GrpcStreamMethod('UsersService', 'ListUsers')
  listUsers(data: Observable<ListUsersRequest>): Observable<User> {
    return data.pipe(
      switchMap(({ page, limit }) => from(this.usersService.findPaginated(page, limit))),
      concatMap((users) => from(users)),
    );
  }
}
```

### gRPC Client (Calling Another Service)
```typescript
// orders/orders.module.ts
@Module({
  imports: [
    ClientsModule.registerAsync([{
      name: 'USERS_SERVICE',
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        transport: Transport.GRPC,
        options: {
          package: 'users',
          protoPath: join(__dirname, '../../proto/users.proto'),
          url: config.get<string>('USERS_GRPC_URL'),
        },
      }),
    }]),
  ],
  providers: [OrdersService],
})
export class OrdersModule {}

// orders/orders.service.ts
@Injectable()
export class OrdersService implements OnModuleInit {
  private usersClient: UsersServiceClient;

  constructor(@Inject('USERS_SERVICE') private readonly client: ClientGrpc) {}

  onModuleInit(): void {
    this.usersClient = this.client.getService<UsersServiceClient>('UsersService');
  }

  async getUser(id: string): Promise<User> {
    return firstValueFrom(this.usersClient.findOne({ id }));
  }
}
```

## Scaffolder Patterns
```
proto/
  users.proto                        # shared contract — commit to source control
src/
  users/
    users.module.ts
    users.grpc.controller.ts         # @GrpcMethod handlers
    users.service.ts                 # shared service used by HTTP + gRPC controllers
  common/
    grpc/
      users-service.interface.ts     # TypeScript interface matching proto
```

## Dos
- Keep `.proto` files in a version-controlled `proto/` directory at the repo root
- Use `firstValueFrom()` from `rxjs` to convert gRPC observables to promises in HTTP routes
- Apply `@UsePipes(new ValidationPipe())` on gRPC controllers for input validation
- Generate TypeScript interfaces from `.proto` with `ts-proto` or `@grpc/proto-loader` for type safety

## Don'ts
- Don't mix gRPC response shapes with HTTP response DTOs — define separate interfaces per transport
- Don't handle gRPC errors with `throw new HttpException` — use gRPC status codes via `status` from `@grpc/grpc-js`
- Don't hard-code gRPC service URLs — inject via `ConfigService`
- Don't forget to call `app.startAllMicroservices()` before `app.listen()` in hybrid apps
