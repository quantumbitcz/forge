# Express + Vitest Testing Patterns

> Express-specific testing patterns for Vitest. Extends `modules/testing/vitest.md`.

## Integration Testing with Supertest

- Use `supertest` for HTTP integration tests
- Create a test app factory that returns the Express app without starting the server

```typescript
import request from 'supertest';
import { createApp } from '../src/app';

describe('POST /api/users', () => {
  const app = createApp();

  it('creates user with valid data', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ name: 'Alice', email: 'alice@example.com' })
      .expect(201);

    expect(response.body.name).toBe('Alice');
  });

  it('returns 400 for invalid data', async () => {
    await request(app)
      .post('/api/users')
      .send({ name: '' })
      .expect(400);
  });
});
```

## Service Layer Testing

- Mock dependencies with `vi.mock()` or manual fakes
- Test service methods in isolation from HTTP layer
- Use dependency injection to swap real implementations with test doubles

## Database Testing

- Use testcontainers or in-memory SQLite for integration tests
- Reset database state between tests (transactions with rollback, or truncate)
- Use factory functions for creating test entities

## NestJS Testing

- Use `@nestjs/testing` with `Test.createTestingModule` for module-level tests
- Override providers with mock implementations
- Use `app.getHttpAdapter()` for supertest integration

## Middleware Testing

- Test middleware in isolation by passing mock `req`, `res`, `next`
- Verify error propagation: ensure `next(err)` is called for failures
