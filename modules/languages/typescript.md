# TypeScript Language Conventions

> Support tier: contract-verified

## Type System

- Enable `strict: true` in `tsconfig.json` — this activates `strictNullChecks`, `noImplicitAny`, `strictFunctionTypes`, and more.
- Enable `noUncheckedIndexedAccess: true` — index access (`arr[0]`, `obj[key]`) returns `T | undefined`, forcing explicit null handling.
- Never use `any` — use `unknown` and narrow with type guards (`typeof`, `instanceof`, `in`, custom predicates).
- Use `as const` for literal type inference: `const STATUS = { ACTIVE: 'active', INACTIVE: 'inactive' } as const`.
- Use discriminated unions for tagged variants: `{ type: 'success'; data: T } | { type: 'error'; message: string }`.
- Use template literal types for string unions: `type EventName = \`on${Capitalize<string>}\``.
- Utility types: `Partial<T>`, `Required<T>`, `Pick<T, K>`, `Omit<T, K>`, `Record<K, V>`, `Readonly<T>`, `ReturnType<F>`, `Parameters<F>`.
- Prefer interface for object shapes that may be extended; prefer `type` alias for unions, intersections, and computed types.

## Null Safety / Error Handling

- Represent absence with `undefined` (not `null`) for optional fields — or declare them optional with `?`.
- Use optional chaining (`?.`) and nullish coalescing (`??`) rather than manual null checks.
- For error values, prefer discriminated union returns (`{ ok: true; value: T } | { ok: false; error: E }`) over throwing for expected failures.
- Throwing is appropriate for programmer errors and unrecoverable conditions.
- Never use non-null assertion (`!`) unless the nullability is a known TypeScript limitation (e.g., post-null-check in closures) — document why.

## Async / Concurrency

- Use `async/await` over raw Promise chains — it is more readable and errors propagate naturally.
- Every `async` function must either handle errors internally or propagate them via `await` — no floating promises.
- `Promise.all` when all operations must succeed; `Promise.allSettled` when partial results are acceptable.
- Use `AbortController` to cancel in-flight async operations on timeout or unmount.
- For rate-limited concurrency (e.g., batch API calls), use a semaphore or `p-limit` — do not fire hundreds of concurrent requests.
- Handle `unhandledRejection` at process/application level for non-awaited promises.

## Import Order

1. Runtime/framework imports (e.g., `react`, `node:fs`)
2. Third-party packages
3. Internal shared/barrel imports (e.g., `@/shared`)
4. Feature-local imports
5. Type-only imports (`import type { ... }`)

Use ESM `import` syntax — never `require()` in TypeScript projects targeting ES modules.

## Naming Idioms

- Types and interfaces: `PascalCase`.
- Variables, functions, methods: `camelCase`.
- Constants with literal intent: `UPPER_SNAKE_CASE` (or `camelCase` if module-private).
- Generic type parameters: single uppercase letter (`T`, `K`, `V`) or descriptive (`TItem`, `TKey`).
- Boolean variables/properties: `isX`, `hasX`, `canX`, `shouldX`.
- Files: `camelCase.ts` for utilities/services, `PascalCase.ts` for class/component files.

## Logging

- Use **pino** (`pino`) — the fastest Node.js structured logger, outputs JSON by default, async-safe.
- Alternative: **winston** for projects requiring multiple transports and format customization.
- Create a shared logger instance:
  ```typescript
  import pino from 'pino';

  export const logger = pino({
    level: process.env.LOG_LEVEL ?? 'info',
    formatters: { level: (label) => ({ level: label }) },
  });
  ```
- Create child loggers with request-scoped context (correlation ID, trace ID):
  ```typescript
  const requestLogger = logger.child({ correlationId, traceId });
  requestLogger.info({ orderId: order.id }, 'Order created');
  ```
- Use structured fields as the first argument — never string interpolation:
  ```typescript
  // Correct — structured, searchable
  logger.info({ userId, action: 'login' }, 'User logged in');

  // Wrong — unstructured, unsearchable
  logger.info(`User ${userId} logged in`);
  ```
- For Express/Fastify, use `pino-http` middleware to auto-log requests with correlation IDs and response times.
- Never use `console.log`, `console.warn`, or `console.error` in production code — they lack structure, levels, and routing.
- PII/credential/financial data logging rules: see `shared/logging-rules.md`.

## Anti-Patterns

- **`any` type:** Silently disables type checking for everything downstream. Use `unknown` and narrow.
- **Non-null assertion (`!`) without justification:** Deferred runtime crash. Fix the type or add a guard.
- **Mixing `null` and `undefined`:** Pick one convention per codebase. TypeScript optional (`?`) implies `undefined`.
- **`require()` in ESM projects:** Breaks module semantics and tree-shaking. Always use `import`.
- **Unhandled floating promises:** `someAsyncFn()` without `await` or `.catch()` silently swallows errors.
- **`Promise.all` for independent operations that should continue on partial failure:** Use `Promise.allSettled` instead.
- **Overly broad catch blocks catching `unknown`:** Narrow the error type before accessing properties (`err instanceof Error`).
- **Type assertions (`as Foo`) to paper over mismatches:** Fix the type mismatch properly; `as` only suppresses the check.
- **`index` as array key in lists that can reorder or filter:** Causes incorrect reconciliation and state bugs.
- **`var` declarations:** Always use `const` (default) or `let` (when reassignment is required). `var` has function scope and hoisting behavior that causes subtle bugs.

## Dos
- Use `const` by default — mutability should be the exception, not the rule.
- Use discriminated unions (`type Result = { ok: true; data: T } | { ok: false; error: Error }`) for type-safe error handling.
- Use `unknown` instead of `any` — it forces type narrowing before use.
- Use `satisfies` (TS 4.9+) for type-checking expressions without widening the inferred type.
- Use `readonly` on arrays, tuples, and object properties that shouldn't be mutated.
- Use `as const` for literal type inference on configuration objects.
- Use `strict: true` in `tsconfig.json` — it enables all strict type-checking options.

## Don'ts
- Don't use `any` — it silently disables type checking for everything downstream.
- Don't use `!` (non-null assertion) without strong justification — it defers crashes to runtime.
- Don't use `require()` in ESM projects — it breaks module semantics and tree-shaking.
- Don't use `var` — use `const` or `let`; `var` has function scope and hoisting bugs.
- Don't use `enum` for simple string unions — use `type Status = "active" | "inactive"` instead.
- Don't leave floating promises without `await` or `.catch()` — errors are silently swallowed.
- Don't use type assertions (`as Foo`) to paper over mismatches — fix the underlying type.
- Don't use barrel index re-exports creating circular dependencies — import directly from source modules.
- Don't write Java-style class hierarchies — prefer union types + type guards or discriminated unions.
- Don't use `implements` on every class — TypeScript has structural typing, explicit `implements` is only needed for documentation.
