# NestJS Framework Conventions
> Support tier: contract-verified
> Framework-specific conventions for NestJS projects. Language idioms are in `modules/languages/typescript.md`. Generic testing patterns are in `modules/testing/vitest.md`.

## Architecture (Module-Based / Layered)

| Layer | Responsibility | NestJS Artifact |
|-------|---------------|-----------------|
| `modules/` | Feature boundaries, DI wiring | `@Module()` class |
| `controllers/` | Request parsing, response shaping (thin) | `@Controller()` class |
| `services/` | Business logic | `@Injectable()` class |
| `repositories/` | Data access, persistence | `@Injectable()` class (or repository injection via `persistence:` choice) |
| `dto/` | Input/output shapes, validation | Plain class with `class-validator` decorators |
| `entities/` | Database models/schemas | Depends on `persistence:` choice (see persistence binding file) |
| `guards/` | Auth, role enforcement | `CanActivate` impl |
| `interceptors/` | Transform, logging, caching | `NestInterceptor` impl |
| `filters/` | Exception mapping to HTTP responses | `ExceptionFilter` impl |
| `pipes/` | Input transformation and validation | `PipeTransform` impl |
| `middleware/` | Cross-cutting HTTP concerns | `NestMiddleware` impl |

**Dependency rule:** Controllers depend on services only. Services depend on repositories/providers. Never import a controller into another module's service.

## Module Structure

### Feature Module Pattern
Every domain feature gets its own module:

```typescript
// users/users.module.ts
@Module({
  imports: [/* persistence module registration — depends on persistence: choice */],
  controllers: [UsersController],
  providers: [UsersService, UsersRepository],
  exports: [UsersService],          // only export what other modules need
})
export class UsersModule {}
```

- Use `exports:` only for services that genuinely cross module boundaries
- Never export controllers — they are always module-private
- `AppModule` imports feature modules; feature modules do NOT import `AppModule`
- Global modules (`@Global()`) for cross-cutting providers: `ConfigModule`, `LoggerModule`, `DatabaseModule`

### Dynamic Modules
Use `forRoot` / `forRootAsync` / `forFeature` pattern for configurable modules:

```typescript
DatabaseModule.forRootAsync({
  inject: [ConfigService],
  useFactory: (config: ConfigService) => ({
    url: config.get<string>('DATABASE_URL'),
  }),
})
```

## Dependency Injection

- Constructor injection only — do not use property injection except in edge cases (circular deps)
- Use interface tokens for loose coupling: `@Inject(USER_REPOSITORY) private repo: IUserRepository`
- Define injection tokens as `const TOKENS = { USER_REPO: 'USER_REPOSITORY' }` in a shared file
- `@Optional()` for non-critical dependencies; document why the dep is optional

## Controllers

- Thin controllers: parse request, call service, return result — no business logic
- Use `@ApiTags()`, `@ApiOperation()`, `@ApiResponse()` for Swagger documentation
- Return plain objects or DTOs; never return database entities directly
- Use `@HttpCode()` for non-200 success codes (e.g., `@HttpCode(201)` on create endpoints)

```typescript
@Controller('users')
@ApiTags('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get(':id')
  @ApiOperation({ summary: 'Get user by ID' })
  @ApiResponse({ status: 200, type: UserResponseDto })
  @ApiResponse({ status: 404, description: 'User not found' })
  async findOne(@Param('id', ParseUUIDPipe) id: string): Promise<UserResponseDto> {
    return this.usersService.findOne(id);
  }
}
```

## Validation with Pipes

- Register `ValidationPipe` globally in `main.ts`:
  ```typescript
  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,          // strip unknown properties
    forbidNonWhitelisted: true,
    transform: true,          // auto-transform payloads to DTO instances
    transformOptions: { enableImplicitConversion: true },
  }));
  ```
- DTO classes use `class-validator` + `class-transformer` decorators
- Use `@IsUUID()`, `@IsEmail()`, `@IsString()`, `@IsOptional()` etc.; combine with `@Type()` for nested objects
- Never use `@Body() body: any` — always type the DTO

```typescript
export class CreateUserDto {
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  name: string;

  @IsEmail()
  email: string;

  @IsOptional()
  @IsEnum(UserRole)
  role?: UserRole;
}
```

## Guards

- Auth guard: extend `AuthGuard('jwt')` from `@nestjs/passport` or implement `CanActivate`
- Role guard: reads `@Roles()` metadata set by `@SetMetadata()` or custom decorator
- Register globally with `APP_GUARD` token in `AppModule.providers` for universal auth
- Exception from global guard via `@Public()` decorator + guard reflector check

```typescript
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(ctx: ExecutionContext): boolean {
    const roles = this.reflector.getAllAndOverride<Role[]>('roles', [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (!roles) return true;
    const { user } = ctx.switchToHttp().getRequest();
    return roles.includes(user.role);
  }
}
```

## Interceptors

- Use interceptors for: response transformation, logging, caching, serialization
- `ClassSerializerInterceptor` globally to apply `class-transformer` `@Exclude()`/`@Expose()` on responses
- Register globally: `app.useGlobalInterceptors(new ClassSerializerInterceptor(app.get(Reflector)))`
- Custom interceptors: implement `NestInterceptor<T, R>` — use `next.handle().pipe(map(...))` for response transform

## Exception Filters

- Map domain exceptions to HTTP responses in a global filter, not in controllers
- Extend `BaseExceptionFilter` to preserve built-in NestJS exception handling for `HttpException` subtypes
- Domain exception hierarchy: `DomainException` → `NotFoundException`, `ConflictException`, etc.

```typescript
@Catch(DomainException)
export class DomainExceptionFilter implements ExceptionFilter {
  catch(exception: DomainException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    response.status(exception.statusCode).json({
      statusCode: exception.statusCode,
      message: exception.message,
      error: exception.code,
    });
  }
}
```

Register globally: `app.useGlobalFilters(new DomainExceptionFilter())`.

## Middleware

- Use NestJS middleware for HTTP-level cross-cutting: request logging, correlation IDs, rate limiting
- Apply in `AppModule.configure()` via `MiddlewareConsumer`:
  ```typescript
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(LoggerMiddleware, CorrelationIdMiddleware).forRoutes('*');
  }
  ```
- Prefer interceptors over middleware for response transformation (interceptors run in NestJS context)

## Microservices and Messaging

- Transport layers: TCP (default), Redis, NATS, Kafka, gRPC, RabbitMQ
- `@MessagePattern('pattern')` for request/reply; `@EventPattern('event')` for fire-and-forget
- Hybrid apps: `app.connectMicroservice(options)` + `await app.startAllMicroservices()`
- Use `ClientProxy` (from `ClientsModule`) to emit messages/events from services

## Configuration

- Always use `@nestjs/config` with `ConfigModule.forRoot({ isGlobal: true, validate })`
- Validate env vars at startup with a Zod or `class-validator` schema
- Inject `ConfigService` — never read `process.env` directly in application code
- Group related config into namespaced config objects: `config.get<string>('database.url')`

## Naming Patterns

| Artifact | File Pattern | Class Pattern |
|----------|-------------|--------------|
| Module | `xxx.module.ts` | `XxxModule` |
| Controller | `xxx.controller.ts` | `XxxController` |
| Service | `xxx.service.ts` | `XxxService` |
| Guard | `xxx.guard.ts` | `XxxGuard` |
| Interceptor | `xxx.interceptor.ts` | `XxxInterceptor` |
| Filter | `xxx.filter.ts` | `XxxFilter` |
| Pipe | `xxx.pipe.ts` | `XxxPipe` |
| Middleware | `xxx.middleware.ts` | `XxxMiddleware` |
| DTO | `create-xxx.dto.ts` / `update-xxx.dto.ts` | `CreateXxxDto` |
| Entity | `xxx.entity.ts` | `XxxEntity` |

## Barrel Exports

Each feature module exposes a barrel `index.ts`:

```typescript
// users/index.ts
export * from './users.module';
export * from './dto/create-user.dto';
export * from './dto/user-response.dto';
// DO NOT export entities or internal services
```

## Security

- Never expose raw database entities from controllers — use response DTOs with `@Exclude()` on sensitive fields
- Apply `helmet()` and `compression()` in `main.ts`
- Rate limiting: `@nestjs/throttler` with `ThrottlerGuard` registered globally
- CORS: `app.enableCors({ origin: config.get('CORS_ORIGIN') })` — never `origin: '*'` in production
- Input sanitization: `whitelist: true` in `ValidationPipe` strips unknown fields automatically

## Code Quality

- Functions / methods: max ~40 lines, max 3 nesting levels
- Services max ~200 lines; split into focused sub-services if exceeded
- Strict TypeScript: `strict: true`, no `any` in DTOs or service signatures
- No `console.log` — use NestJS `Logger` or inject a custom logger

## Logging

```typescript
@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  async findOne(id: string): Promise<UserResponseDto> {
    this.logger.log(`Finding user ${id}`);
    // ...
  }
}
```

Use `logger.error()`, `logger.warn()`, `logger.log()`, `logger.debug()`, `logger.verbose()`.

## Testing

### Test Framework
- **Vitest** (preferred) or **Jest** as the test runner
- `@nestjs/testing` for `Test.createTestingModule()` — always use to build isolated modules in unit tests
- **supertest** for e2e HTTP integration tests

### Unit Test Patterns
- Use `Test.createTestingModule()` with `overrideProvider()` to swap real providers with mocks
- Prefer `vi.fn()` (Vitest) or `jest.fn()` (Jest) for service mocks
- Test one service method per `it()` block; name clearly: `it('should throw NotFoundException when user not found', ...)`

```typescript
describe('UsersService', () => {
  let service: UsersService;
  let repoMock: { findOne: ReturnType<typeof vi.fn> };

  beforeEach(async () => {
    repoMock = { findOne: vi.fn() };
    const module = await Test.createTestingModule({
      providers: [
        UsersService,
        { provide: UsersRepository, useValue: repoMock },
      ],
    }).compile();
    service = module.get(UsersService);
  });

  it('throws NotFoundException when user not found', async () => {
    repoMock.findOne.mockResolvedValue(null);
    await expect(service.findOne('unknown-id')).rejects.toThrow(NotFoundException);
  });
});
```

### E2E Test Patterns
- Create test application with `Test.createTestingModule({ imports: [AppModule] }).compile()`
- Use `app.getHttpAdapter()` or `app.getHttpServer()` with supertest
- Reset database state between tests (transactions or Testcontainers)

### What to Test
- Service-layer business logic with mocked repositories
- Guard logic: allowed/denied scenarios per role and token validity
- Pipe validation: valid DTOs pass, invalid DTOs throw `BadRequestException`
- Exception filter: domain exception maps to correct HTTP status and body shape

### What NOT to Test
- NestJS DI container resolves providers (framework guarantee)
- `ValidationPipe` parses basic types — test complex cross-field validations only
- `ClassSerializerInterceptor` applies `@Exclude()` correctly (framework guarantee)

### Example Test Structure
```
src/
  users/
    users.controller.ts
    users.service.ts
    users.service.spec.ts         # co-located unit test
    users.controller.spec.ts
test/
  users.e2e-spec.ts               # e2e with supertest
  jest-e2e.json
```

For general Vitest patterns, see `modules/testing/vitest.md`.

## Smart Test Rules

- No duplicate tests — grep existing tests before writing new ones
- Test business behavior, not implementation details
- Do NOT test NestJS DI wiring or framework internals
- Do NOT test basic `class-validator` type checks for primitive fields
- Each test scenario covers a unique code path
- Fewer meaningful tests > high coverage of trivial code

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated modules, changing provider contracts, restructuring interceptor chains.

## Dos and Don'ts

### Do
- Register `ValidationPipe` globally with `whitelist: true` and `transform: true`
- Use `@nestjs/config` for all configuration — never read `process.env` directly in services
- Use NestJS `Logger` for all logging — never use `console.log`
- Use `@nestjs/swagger` decorators to document all endpoints
- Apply `ClassSerializerInterceptor` globally to prevent accidental entity leakage
- Use barrel `index.ts` files per module for clean imports
- Use `@Roles()` + `RolesGuard` for authorization; define roles as an enum

### Don't
- Don't use `res.send()` or `res.json()` directly in controllers — return values from controller methods
- Don't put business logic in controllers — delegate everything to services
- Don't import one feature module's service directly into another feature's module; use `exports:` + `imports:` wiring
- Don't use `any` in DTOs or service method signatures
- Don't use persistence repository injection without registering the entity in the same module (depends on `persistence:` choice)
- Don't use auto-sync/auto-schema features in any environment other than a throw-away local dev DB
- Don't bypass `ValidationPipe` by accepting untyped `@Body()`
