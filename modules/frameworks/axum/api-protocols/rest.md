# Axum REST — API Protocol Binding

## Integration Setup
- `axum` + `tokio` (full features) + `tower` + `tower-http`
- OpenAPI: `utoipa` + `utoipa-axum` + `utoipa-swagger-ui`; derive `ToSchema` on request/response types
- Validation: `validator` crate with `axum-valid` middleware; or `garde` for declarative rules

## Framework-Specific Patterns
- Build router with `Router::new().route("/users", get(list_users).post(create_user))`
- Extractors in handler parameters: `Path<Uuid>`, `Query<Params>`, `Json<CreateUserRequest>`, `State<AppState>`
- Return `impl IntoResponse`; use `(StatusCode, Json<T>)` tuples for explicit status
- Error handling: define an `AppError` enum implementing `IntoResponse`; map from domain errors in handlers
- Nest routers: `Router::new().nest("/api/v1", api_router())` for versioning
- Tower middleware: add with `.layer()`; use `tower_http::trace::TraceLayer` and `CorsLayer` at the router level
- State injection: `Router::with_state(state)` where `AppState` derives `Clone` and holds `Arc` references

## Scaffolder Patterns
```
src/
  routes/
    mod.rs
    users/
      mod.rs               # Router::new() + route definitions
      handlers.rs          # async fn handlers with extractors
      dto.rs               # request/response structs + ToSchema derives
  error.rs                 # AppError enum + IntoResponse impl
  state.rs                 # AppState struct
  openapi.rs               # utoipa OpenApi derive + SwaggerUi
  main.rs                  # Router assembly + serve
```

## Dos
- Derive `serde::Deserialize` on request types and `serde::Serialize` on response types
- Use `axum::extract::rejection` error types in the `AppError` enum for consistent 422 responses
- Apply `TraceLayer` for structured request/response tracing; propagate `trace_id` headers
- Use `Arc<dyn Trait>` in `AppState` for service dependencies to enable test mocking

## Don'ts
- Don't use `unwrap()` or `expect()` inside handlers — propagate errors via `AppError`
- Don't block the async runtime with synchronous I/O; use `tokio::task::spawn_blocking` when needed
- Don't put business logic inside handler functions — delegate to service layer
- Don't skip request validation; use `axum-valid` or manual validation before processing
