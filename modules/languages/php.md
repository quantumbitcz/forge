# PHP Language Conventions

> Support tier: contract-verified

## Type System

- Use strict types in every file: `declare(strict_types=1);` — prevents implicit type coercion.
- Add type declarations to all function parameters, return types, and class properties (PHP 7.4+).
- Use union types (PHP 8.0+): `int|string`, nullable types: `?string`.
- Use enums (PHP 8.1+) for fixed sets of values: `enum Status: string { case Active = 'active'; }`.
- Use readonly properties (PHP 8.1+) and readonly classes (PHP 8.2+) for immutable data.
- Use intersection types (PHP 8.1+) for combining interfaces: `Countable&Iterator`.
- Max line length: 120 characters (PSR-12 standard).

## Null Safety / Error Handling

- Use nullable types (`?Type`) and null coalescing operator (`??`).
- Use nullsafe operator (PHP 8.0+): `$user?->getAddress()?->getCity()`.
- Never use `@` error suppression operator — it hides bugs and makes debugging impossible.
- Use typed exceptions extending domain-specific base classes.
- Use `try/catch/finally` with specific exception types — never catch `\Throwable` without re-throwing.
- Use `set_exception_handler()` and `set_error_handler()` for global error handling.

## Async / Concurrency

- PHP is traditionally synchronous (one request per process). For async workloads, use:
  - **ReactPHP** or **Amphp** for event-loop-based async I/O.
  - **Swoole/OpenSwoole** for coroutine-based async with true concurrency.
  - **Laravel Queue** or **Symfony Messenger** for background job processing.
- Use **Fibers** (PHP 8.1+) for cooperative multitasking within async frameworks.
- Never use `pcntl_fork()` in web processes — use a queue/worker architecture.

## Idiomatic Patterns

- **Named arguments** (PHP 8.0+): `htmlspecialchars(string: $text, flags: ENT_QUOTES)`.
- **Match expression** (PHP 8.0+) over `switch`: `match($status) { 'active' => true, default => false }`.
- **Arrow functions** for short closures: `$names = array_map(fn($u) => $u->name, $users)`.
- **Attributes** (PHP 8.0+) over docblock annotations: `#[Route('/api/users')]`.
- **Constructor promotion** (PHP 8.0+): `public function __construct(private readonly string $name) {}`.
- **`sprintf()`** for formatted strings; string interpolation (`"Hello, $name"`) for simple cases.
- **Collections** — use `array_map`, `array_filter`, `array_reduce` or a collection library.

## Naming Idioms

- Files: `PascalCase.php` (PSR-4, one class per file).
- Classes, interfaces, traits, enums: `PascalCase`.
- Methods and functions: `camelCase`.
- Variables and properties: `camelCase`.
- Constants: `UPPER_SNAKE_CASE`.
- Interfaces: `PascalCase` (no `I` prefix — `UserRepository`, not `IUserRepository`).
- Abstract classes: prefix with `Abstract`: `AbstractController`.

## Logging

- Use **Monolog** (`monolog/monolog`) — the de facto PHP logging library, PSR-3 compliant, with 60+ handlers for any output target.
- Always code against the **PSR-3** interface (`Psr\Log\LoggerInterface`) — decouples application code from the logging implementation.
- In frameworks: Laravel and Symfony ship Monolog by default and expose it via PSR-3.
- Inject `LoggerInterface` via constructor — never instantiate loggers directly:
  ```php
  public function __construct(
      private readonly LoggerInterface $logger,
  ) {}

  public function createOrder(CreateOrderCommand $command): Order
  {
      $this->logger->info('Order created', [
          'order_id' => $order->id,
          'user_id' => $command->userId,
      ]);
  }
  ```
- Use context arrays for structured data — never string interpolation:
  ```php
  // Correct — structured, searchable
  $this->logger->info('Order created', ['order_id' => $order->id]);

  // Wrong — baked into message, unsearchable
  $this->logger->info("Order {$order->id} created");
  ```
- Use Monolog's `JsonFormatter` or `LogstashFormatter` for structured JSON output in production.
- Use Monolog processors to inject request-scoped context (correlation ID, trace ID) automatically into every log record.
- Never use `echo`, `print`, `var_dump()`, or `error_log()` for logging — they lack levels, structure, and routing.
- PII/credential/financial data logging rules: see `shared/logging-rules.md`.

## Anti-Patterns

- **No `declare(strict_types=1)`** — without it, PHP silently coerces `"123"` to `123`, masking type errors.
- **Using `@` error suppression** — hides errors completely, making debugging a nightmare.
- **Using `extract()` or `compact()`** — creates/destroys variables implicitly, making code flow untraceable.
- **String comparison without `===`** — `==` performs type juggling (`"0" == false` is `true`).
- **Global state via `$_GLOBALS`** — use dependency injection and service containers.

## Dos
- Use `declare(strict_types=1)` in every PHP file — it prevents silent type coercion bugs.
- Use Composer for dependency management and PSR-4 autoloading.
- Use PHP-CS-Fixer or PHP_CodeSniffer with PSR-12 for consistent code style.
- Use constructor promotion (PHP 8.0+) to reduce boilerplate in DTOs and value objects.
- Use enums (PHP 8.1+) instead of class constants for fixed sets of values.
- Use `===` (strict comparison) everywhere — `==` causes type juggling surprises.
- Use PHPStan or Psalm at maximum level for static analysis — they catch bugs that tests miss.

## Don'ts
- Don't use `@` error suppression — it hides bugs and makes debugging impossible.
- Don't use `eval()` or `shell_exec()` with user input — command injection vulnerabilities.
- Don't use `mysql_*` functions — they were removed in PHP 7.0; use PDO with prepared statements.
- Don't use `extract()` — it pollutes the variable scope and makes code analysis impossible.
- Don't use `==` for comparisons — type juggling produces surprising results (`"0" == false`, `"" == 0`).
- Don't put business logic in controllers — use services, handlers, or use case classes.
- Don't use `var` for class properties — use typed properties with visibility modifiers.
- Don't write Java-style getter/setter methods when `readonly` properties (PHP 8.1+) or constructor promotion works.
- Don't create `AbstractBaseService` class hierarchies — use composition and interfaces.
- Don't use `array` for everything — use typed DTOs with `readonly class` (PHP 8.2+).
