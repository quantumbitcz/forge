# Gin Documentation Conventions

> Extends `modules/documentation/conventions.md` with Gin-specific patterns.

## Code Documentation

- Use godoc format for all exported handler functions, middleware, and service types.
- Handler functions: document the HTTP method, route, request binding struct, response struct, and error codes.
- Middleware functions: document what they read from the context, what they set on the context, and when they abort.
- Binding structs: document validation tags — they are the request contract.
- Router groups: module-level godoc describing which routes are registered and their auth requirements.

```go
// CreateUser handles POST /api/v1/users.
//
// Binds and validates a [CreateUserRequest] from the JSON body.
// Returns [UserResponse] with HTTP 201 on success.
// Returns HTTP 409 if the email is already registered.
func (h *UserHandler) CreateUser(c *gin.Context) { ... }

// AuthMiddleware validates the Bearer JWT in the Authorization header.
// On success, sets "userID" and "roles" in the gin.Context.
// Aborts with HTTP 401 on missing or invalid token.
func AuthMiddleware(jwtKey []byte) gin.HandlerFunc { ... }
```

## Architecture Documentation

- Document the router group structure: list route groups, their path prefix, applied middleware, and handler files.
- Document middleware registration order per router group — ordering is significant.
- OpenAPI: use `swaggo/swag` annotations or maintain an `openapi.yaml`. Document spec generation command in `README.md`.
- Document `gin.Context` keys set by middleware — they are an implicit API between middleware and handlers.

## Diagram Guidance

- **Router structure:** Table listing route groups, middleware, and handler files.
- **Middleware chain:** Sequence diagram for a typical authenticated request.

## Dos

- Document `c.Set`/`c.Get` context keys in a central constants file — and reference them in middleware godoc
- Use `swaggo/swag` annotations if project uses auto-generated OpenAPI
- Document binding struct validation tags — `binding:"required,email"` is the API contract

## Don'ts

- Don't godoc Gin's built-in middleware wrappers (e.g., `gin.Logger()`) — document your custom middleware only
- Don't maintain separate route documentation alongside the router file — the router IS the documentation
