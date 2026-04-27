# NestJS Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with NestJS-specific patterns.

## Code Documentation

- Use TSDoc (`/** */`) for all controllers, services, DTOs, guards, pipes, and interceptors.
- Controllers: TSDoc on each handler method documenting HTTP method, path, request DTO, response DTO, and HTTP status codes. Use `@ApiOperation` and `@ApiResponse` Swagger decorators — they are the machine-readable version.
- Services: document public methods with preconditions, return values, and exceptions thrown.
- DTOs: document non-obvious `class-validator` decorators. Use `@ApiProperty({ description: '...' })` — it feeds OpenAPI generation.
- Guards: document the condition checked and what happens on failure (exception type thrown).
- Module providers: document custom factory providers with `useFactory` — the factory logic is non-obvious.

```typescript
/**
 * Creates a new user account.
 *
 * @param dto - Validated creation payload (see {@link CreateUserDto})
 * @returns Created user with HTTP 201
 * @throws ConflictException if email is already registered
 */
@Post()
@ApiOperation({ summary: 'Create user' })
@ApiResponse({ status: 201, type: UserResponse })
@ApiResponse({ status: 409, description: 'Email already registered' })
async createUser(@Body() dto: CreateUserDto): Promise<UserResponse> { ... }
```

## Architecture Documentation

- Document the module dependency graph: which modules import which. NestJS modules form an explicit graph — document it.
- Document microservice transport configuration if using `@nestjs/microservices`: transport type, broker URL, patterns.
- Document custom `Pipes`, `Guards`, and `Interceptors`: what they do and where they are registered (global, controller, method).
- OpenAPI: use `@nestjs/swagger`. Document `SwaggerModule.setup` path and the generated spec endpoint.
- Document `ConfigModule` schema: required and optional environment variables, types, and validation rules.

## Diagram Guidance

- **Module dependency graph:** Mermaid class diagram showing NestJS module imports.
- **Request pipeline:** Sequence diagram showing Guard → Interceptor → Pipe → Handler → Interceptor order.

## Dos

- `@ApiProperty({ description: '...' })` on all DTO fields — feeds the OpenAPI spec
- TSDoc on all public service methods — they are the application layer API
- Document module `providers` that use `useFactory` — factory logic is invisible without documentation

## Don'ts

- Don't document NestJS built-in decorators (`@Get`, `@Post`, etc.) — document your handler's behavior
- Don't maintain a manual API reference alongside the Swagger UI — use `@ApiOperation` and `@ApiResponse`
