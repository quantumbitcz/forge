# NestJS + Vitest Testing Patterns

> NestJS-specific testing patterns for Vitest. Extends `modules/testing/vitest.md`.

## Setup

```bash
npm install -D vitest @vitest/coverage-v8 unplugin-swc @swc/core
```

`vitest.config.ts`:
```typescript
import { defineConfig } from 'vitest/config';
import swc from 'unplugin-swc';

export default defineConfig({
  test: {
    globals: true,
    root: './',
    include: ['src/**/*.spec.ts'],
  },
  plugins: [swc.vite({ module: { type: 'es6' } })],
});
```

> SWC is required because Vitest's default esbuild transform does not support TypeScript decorators (`emitDecoratorMetadata`). Alternatively, use `@swc/jest` with Jest.

## Unit Test — Service with Mocked Provider

```typescript
import { Test } from '@nestjs/testing';
import { NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { UsersService } from './users.service';
import { UsersRepository } from './users.repository';

describe('UsersService', () => {
  let service: UsersService;
  const repoMock = {
    findById: vi.fn(),
    save: vi.fn(),
    delete: vi.fn(),
  };

  beforeEach(async () => {
    vi.clearAllMocks();
    const module = await Test.createTestingModule({
      providers: [
        UsersService,
        { provide: UsersRepository, useValue: repoMock },
      ],
    }).compile();
    service = module.get(UsersService);
  });

  describe('findOne', () => {
    it('returns user when found', async () => {
      repoMock.findById.mockResolvedValue({ id: '1', name: 'Alice' });
      const user = await service.findOne('1');
      expect(user.name).toBe('Alice');
    });

    it('throws NotFoundException when user not found', async () => {
      repoMock.findById.mockResolvedValue(null);
      await expect(service.findOne('missing')).rejects.toThrow(NotFoundException);
    });
  });
});
```

## Unit Test — Guard

```typescript
import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RolesGuard } from './roles.guard';

describe('RolesGuard', () => {
  let guard: RolesGuard;
  let reflector: Reflector;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [RolesGuard, Reflector],
    }).compile();
    guard = module.get(RolesGuard);
    reflector = module.get(Reflector);
  });

  it('allows when no roles required', () => {
    vi.spyOn(reflector, 'getAllAndOverride').mockReturnValue(undefined);
    const ctx = mockExecutionContext({ user: { role: 'user' } });
    expect(guard.canActivate(ctx)).toBe(true);
  });

  it('denies when user lacks required role', () => {
    vi.spyOn(reflector, 'getAllAndOverride').mockReturnValue(['admin']);
    const ctx = mockExecutionContext({ user: { role: 'user' } });
    expect(guard.canActivate(ctx)).toBe(false);
  });
});

function mockExecutionContext(request: object): ExecutionContext {
  return {
    switchToHttp: () => ({ getRequest: () => request }),
    getHandler: vi.fn(),
    getClass: vi.fn(),
  } as unknown as ExecutionContext;
}
```

## E2E Test with Supertest

```typescript
import { Test } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AppModule } from '../src/app.module';

describe('Users (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleRef.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
  });

  afterAll(() => app.close());

  it('POST /users creates a user', async () => {
    const res = await request(app.getHttpServer())
      .post('/users')
      .send({ name: 'Alice', email: 'alice@example.com' })
      .expect(201);

    expect(res.body).toMatchObject({ name: 'Alice', email: 'alice@example.com' });
    expect(res.body.id).toBeDefined();
  });

  it('POST /users returns 400 for invalid email', async () => {
    await request(app.getHttpServer())
      .post('/users')
      .send({ name: 'Bob', email: 'not-an-email' })
      .expect(400);
  });
});
```

## Overriding Providers in E2E Tests

```typescript
const moduleRef = await Test.createTestingModule({
  imports: [AppModule],
})
  .overrideProvider(MailService)
  .useValue({ sendWelcomeEmail: vi.fn() })
  .overrideGuard(AuthGuard)
  .useValue({ canActivate: () => true })
  .compile();
```

## Database Integration Tests (Testcontainers)

```typescript
import { PostgreSqlContainer } from '@testcontainers/postgresql';

let container: StartedPostgreSqlContainer;

beforeAll(async () => {
  container = await new PostgreSqlContainer().start();
  process.env.DATABASE_URL = container.getConnectionUri();
  // initialize app with real DB
});

afterAll(() => container.stop());
```

## Dos and Don'ts

- DO use `vi.clearAllMocks()` in `beforeEach` to prevent mock state leakage between tests
- DO use `Test.createTestingModule()` for every unit test — never instantiate service classes with `new`
- DO close the app in `afterAll(() => app.close())` in e2e tests — prevents open handle warnings
- DON'T test that NestJS DI resolves providers — that is a framework guarantee
- DON'T share the test module between `it()` blocks if provider state can mutate
- DON'T use real HTTP server ports in e2e tests — use `app.getHttpServer()` with supertest
