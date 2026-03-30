# Gin + godoc

> Extends `modules/code-quality/godoc.md` with Gin-specific integration.
> Generic godoc conventions (comment format, example functions, CI integration) are NOT repeated here.

## Integration Setup

No additional tooling is required — godoc conventions apply directly to Gin projects. Enforce documentation via golangci-lint's `revive` linter with the `exported` rule enabled:

```yaml
# .golangci.yml
linters-settings:
  revive:
    rules:
      - name: exported
        arguments:
          - "checkPrivateReceivers"
          - "sayRepetitiveInsteadOfStutters"
```

## Framework-Specific Patterns

### Documenting Handler Functions

Handler functions are the primary API surface of a Gin service. Document each handler with its HTTP method, route, request/response contract, and error codes:

```go
// GetUserByID retrieves a single user by their numeric ID.
//
// Route: GET /api/v1/users/:id
//
// Path parameter:
//   - id: numeric user ID (required)
//
// Responses:
//   - 200: [UserResponse] — user found
//   - 400: invalid id format
//   - 404: user not found
//   - 500: internal server error
func (h *UserHandler) GetUserByID(c *gin.Context) {
```

### Documenting Middleware

Middleware functions should document their effect on `gin.Context`, any keys they set, and the conditions under which they abort the chain:

```go
// AuthMiddleware validates the Bearer token in the Authorization header and
// sets the authenticated user ID in the context under the key "userID".
//
// Aborts with 401 if the token is missing, malformed, or expired.
// Aborts with 403 if the token is valid but the user is inactive.
//
// Context keys set:
//   - "userID": string — the authenticated user's ID
//   - "userRole": string — the user's role (admin, member, viewer)
func AuthMiddleware(secret string) gin.HandlerFunc {
```

### Documenting Request and Response DTOs

Document all request/response structs with field-level comments describing validation rules:

```go
// CreateOrderRequest is the request body for POST /api/v1/orders.
type CreateOrderRequest struct {
    // ProductID is the ID of the product to order. Required.
    ProductID string `json:"product_id" binding:"required,uuid"`

    // Quantity is the number of units to order. Must be between 1 and 1000.
    Quantity int `json:"quantity" binding:"required,min=1,max=1000"`

    // Notes are optional free-text instructions for the order.
    Notes string `json:"notes" binding:"omitempty,max=500"`
}
```

### Example Functions for Handler Tests

Write example functions that demonstrate how to call the handler through `httptest` — they serve as living documentation:

```go
func ExampleUserHandler_GetUserByID() {
    router := gin.New()
    h := NewUserHandler(stubUserService{})
    router.GET("/users/:id", h.GetUserByID)

    w := httptest.NewRecorder()
    req := httptest.NewRequest(http.MethodGet, "/users/1", nil)
    router.ServeHTTP(w, req)

    fmt.Println(w.Code)
    // Output:
    // 200
}
```

## Additional Dos

- Document context keys set by middleware using a constants block — callers and reviewers can find all keys without tracing middleware code.
- Add `// Route:` and response code comments to every exported handler function — they act as inline API documentation readable without a Swagger tool.
- Document the router setup function with the full route tree — a single comment listing all registered routes helps reviewers validate completeness.

## Additional Don'ts

- Don't leave middleware undocumented — the keys it injects into `gin.Context` are invisible to callers without documentation.
- Don't document request DTOs with only `json` tag information — describe validation rules and business constraints in the comment, not just the field name.
- Don't write example functions that depend on a live database — use stubs or in-memory implementations so examples run as part of `go test`.
