# Express + TypeScript Variant

> TypeScript-specific patterns for Express/Node.js projects. Extends `modules/languages/typescript.md` and `modules/frameworks/express/conventions.md`.

## Request/Response Typing

- Use `Request<Params, ResBody, ReqBody, Query>` generics for typed handlers
- Create request DTOs with Zod schemas and infer types: `type CreateUser = z.infer<typeof createUserSchema>`
- Use middleware to attach typed data to `req` (extend `Request` interface)

```typescript
import { Request, Response, NextFunction } from 'express';

interface TypedRequest<T> extends Request {
  body: T;
}

const createUser = async (req: TypedRequest<CreateUserDTO>, res: Response) => {
  const user = await userService.create(req.body);
  res.status(201).json(user);
};
```

## Error Class Typing

- Define base `AppError` class with `statusCode` property
- Use discriminated unions or class hierarchy for error types
- Type error handler middleware with all 4 parameters

## Module System

- ESM imports only -- `import`/`export`, never `require()`
- `"type": "module"` in package.json or `.mts` extensions
- Use `import type` for type-only imports

## Async Patterns

- **Unhandled rejections:** Every `async` function must have error handling or propagate with `await`
- **Promise.all vs Promise.allSettled:** Use `Promise.all` when all must succeed, `Promise.allSettled` for partial results
- **Concurrent limits:** Use `p-limit` or manual semaphore for rate-limited APIs

## NestJS TypeScript

- Use decorators: `@Injectable()`, `@Controller()`, `@Module()`
- DTOs with `class-validator` decorators for runtime validation
- Use `@nestjs/config` with typed configuration service
