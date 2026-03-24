# Express REST — API Protocol Binding

## Integration Setup
- `express` + `express-async-errors` (auto-propagates async rejections to error middleware)
- Validation: `zod` with `zod-express-middleware` or `joi`; OpenAPI: `swagger-jsdoc` + `swagger-ui-express`
- Body parsing: `express.json()` and `express.urlencoded({ extended: true })` as app-level middleware

## Framework-Specific Patterns
- Organise routes with `express.Router()`; mount at a versioned path: `app.use("/api/v1/users", userRouter)`
- Validate request bodies/params/query via middleware before the handler; reject with 400 if invalid
- Async handlers: wrap with `express-async-errors` or explicit `try/catch` + `next(err)` call
- Centralised error handler: 4-argument middleware `(err, req, res, next)` registered last; return RFC 7807 JSON
- Use `res.status(201).json(body)` pattern; never call `res.send()` after `res.json()`
- Document with JSDoc `@swagger` comments above routes; serve spec at `/api/docs`

## Scaffolder Patterns
```
src/
  routes/
    users/
      index.ts             # Router mount
      users.controller.ts  # thin handler — delegates to service
      users.schema.ts      # zod schemas for request validation
  services/
    users.service.ts
  middleware/
    validate.ts            # generic zod validation middleware factory
    errorHandler.ts        # global error handler
  config/
    swagger.ts             # swagger-jsdoc options
```

## Dos
- Validate all incoming data at the route boundary before touching business logic
- Return consistent error shapes: `{ title, status, detail }` (RFC 7807)
- Use router-level middleware for auth; never repeat auth checks inside handlers
- Set `X-Request-Id` header in a middleware; log it with every request

## Don'ts
- Don't use synchronous `fs`/CPU-heavy calls inside request handlers without offloading
- Don't let unhandled promise rejections reach the process without an error boundary
- Don't put database queries directly in route handlers
- Don't expose stack traces to clients in production error responses
