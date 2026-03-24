# Spring REST — API Protocol Binding

## Integration Setup
- Add `spring-boot-starter-web` (MVC) or `spring-boot-starter-webflux` (reactive)
- Add `springdoc-openapi-starter-webmvc-ui` or `springdoc-openapi-starter-webflux-ui` for OpenAPI/Swagger UI
- Configure base path: `spring.mvc.servlet.path=/api` or via `@RequestMapping` on a base controller

## Framework-Specific Patterns
- Annotate controllers with `@RestController`; never use `@Controller` + `@ResponseBody` pair in new code
- Return `ResponseEntity<T>` for explicit status control; use typed `ResponseEntity.ok(body)` helpers
- Group related endpoints in a `@RequestMapping("/v1/resource")` class; version at path level, not header
- Use `@ControllerAdvice` + `@ExceptionHandler` for centralized error handling; return RFC 7807 `ProblemDetail`
- Reactive: return `Mono<ResponseEntity<T>>` or `Flux<T>`; never block inside a WebFlux handler
- Content negotiation: set `produces`/`consumes` on method level; prefer `application/json` default
- Validate request bodies with `@Valid`; handle `MethodArgumentNotValidException` in the advice
- Document endpoints via `@Operation`, `@ApiResponse`, `@Schema` from `io.swagger.v3.oas.annotations`

## Scaffolder Patterns
```
src/main/kotlin/com/example/
  web/
    UserController.kt          # @RestController, thin — delegates to use case
    dto/
      CreateUserRequest.kt     # @Valid annotated data class
      UserResponse.kt          # response projection
  config/
    OpenApiConfig.kt           # OpenAPI bean, servers, security scheme
  exception/
    GlobalExceptionHandler.kt  # @ControllerAdvice
```

## Dos
- Return `ProblemDetail` (Spring 6+) from exception handlers for RFC 7807 compliance
- Use `@PathVariable` + `@RequestBody` for mutation endpoints; `@RequestParam` only for filters
- Document all non-200 responses with `@ApiResponse`
- Validate with `@NotNull`/`@Size` on request DTOs; propagate field errors as 400

## Don'ts
- Don't put business logic in controllers — delegate to use-case/service layer immediately
- Don't swallow exceptions silently; always map to a meaningful HTTP status
- Don't return raw domain entities as responses; use dedicated response DTOs
- Don't mix reactive and blocking calls in WebFlux handlers
