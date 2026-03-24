# NestJS REST — API Protocol Binding

## Integration Setup
- `@nestjs/common` controllers with `@Get`, `@Post`, `@Put`, `@Patch`, `@Delete` decorators
- Validation: `class-validator` + `class-transformer` with global `ValidationPipe`
- Swagger: `@nestjs/swagger` with `SwaggerModule.setup()` in `main.ts`
- Body parsing: built-in — NestJS parses JSON by default

## Framework-Specific Patterns
- Organise controllers by resource: `UsersController` maps to `/users`
- Use `@ApiTags()`, `@ApiOperation()`, `@ApiResponse()` on every endpoint for Swagger docs
- Use `@ApiProperty()` on every DTO field for Swagger schema generation
- Use built-in pipes: `ParseUUIDPipe`, `ParseIntPipe`, `ParseBoolPipe` on `@Param()` / `@Query()`
- Return DTOs from controller methods — never return raw entities
- Use `@HttpCode(HttpStatus.NO_CONTENT)` for DELETE endpoints, `@HttpCode(HttpStatus.CREATED)` for POST
- Set up versioning: `app.enableVersioning({ type: VersioningType.URI })` and `@Version('1')` on controllers
- Serve Swagger UI: `SwaggerModule.setup('api/docs', app, document)` in `main.ts`

## Scaffolder Patterns
```
src/
  users/
    users.module.ts
    users.controller.ts          # @Controller('users') with CRUD endpoints
    users.service.ts
    dto/
      create-user.dto.ts         # class-validator decorators + @ApiProperty
      update-user.dto.ts         # extends PartialType(CreateUserDto)
      user-response.dto.ts       # @Exclude() on sensitive fields
    users.controller.spec.ts
  common/
    filters/
      all-exceptions.filter.ts   # global exception filter — RFC 7807 shape
    interceptors/
      logging.interceptor.ts
```

## Dos
- Use `PartialType(CreateUserDto)` from `@nestjs/swagger` (not `@nestjs/mapped-types`) for update DTOs — preserves Swagger schema
- Apply `ClassSerializerInterceptor` globally to enforce `@Exclude()` on response DTOs
- Return consistent error shapes: `{ statusCode, message, error }` from the global exception filter
- Use `@ApiProperty({ example: '...' })` to provide realistic examples in Swagger UI

## Don'ts
- Don't use `@Res()` injection unless returning streams or SSE — return values from controller methods instead
- Don't put business logic or database calls in controllers
- Don't expose `UserEntity` from controllers — always map through a response DTO
- Don't skip `@ApiResponse()` decorators — undocumented error codes degrade Swagger quality
