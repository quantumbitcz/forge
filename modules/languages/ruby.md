# Ruby Language Conventions

## Type System

- Ruby is dynamically typed. Use **Sorbet** (`sig { params(...).returns(...) }`) or **RBS** (`.rbs` type definition files) for opt-in static type checking in larger codebases.
- Use `frozen_string_literal: true` magic comment at the top of every file — prevents accidental string mutation and improves performance.
- Use symbols (`:name`) for identifiers and hash keys; strings for data values.
- Use `Struct` or `Data.define` (Ruby 3.2+) for simple value objects.
- Prefer keyword arguments for methods with 3+ parameters: `def create_user(name:, email:, role: :user)`.
- Max line length: 120 characters (RuboCop default).

## Null Safety / Error Handling

- Ruby's nil is pervasive. Use safe navigation operator (`&.`) for nil-safe method chains: `user&.address&.city`.
- Never rescue `Exception` — rescue `StandardError` or specific subclasses: `rescue ActiveRecord::RecordNotFound`.
- Use custom exception classes inheriting from `StandardError` for domain errors.
- Use `raise` for exceptional conditions; use return values (nil, Result objects) for expected failure paths.
- Use `ensure` (not `rescue`) for cleanup — it runs regardless of whether an exception was raised.
- Avoid `retry` without a counter — infinite retry loops are a common Ruby bug.

## Async / Concurrency

- Ruby's GIL (Global Interpreter Lock, CRuby) prevents true thread parallelism for CPU-bound work. Use `Ractor` (Ruby 3.0+) for CPU parallelism or delegate to a background job framework.
- Use **Sidekiq** or **GoodJob** for background jobs — never use threads for long-running work in a web process.
- Use `Concurrent::Future` (from concurrent-ruby gem) for async I/O operations.
- For async I/O without threads, use **Fiber Scheduler** (Ruby 3.1+) with compatible gems.
- Use `Mutex` for shared state in threaded code: `@mutex.synchronize { @counter += 1 }`.

## Idiomatic Patterns

- **Blocks and iterators** over explicit loops: `users.select { |u| u.active? }.map(&:email)`.
- **Enumerable methods** (`map`, `select`, `reject`, `reduce`, `each_with_object`) over manual iteration.
- **Method missing** sparingly — use `respond_to_missing?` alongside it, prefer `define_method` or delegation.
- **Open classes** — extend built-in classes only via refinements (`using`), never globally in gems.
- **Guard clauses** for early returns: `return unless valid?` over nested `if` blocks.
- **String interpolation** (`"Hello, #{name}"`) over concatenation.
- **Hash#fetch** for required keys with clear error messages: `config.fetch(:api_key)`.

## Naming Idioms

- Files and directories: `snake_case.rb`.
- Classes and modules: `PascalCase` (CamelCase).
- Methods and variables: `snake_case`.
- Constants: `UPPER_SNAKE_CASE`.
- Predicates (boolean-returning methods): `active?`, `valid?`, `empty?`.
- Dangerous methods (mutate in place): `sort!`, `strip!`, `delete!` — bang suffix.
- Attribute accessors: `attr_reader :name`, `attr_accessor :email`.

## Anti-Patterns

- **God objects** — classes with too many responsibilities. Use mixins (`include`) or composition to decompose.
- **Monkey patching** — modifying core classes globally breaks gems and tests. Use refinements instead.
- **Rescue nil** — `rescue nil` silently swallows all errors. Always name the exception class.
- **String keys in hashes** — use symbols: `{ name: "Alice" }` not `{ "name" => "Alice" }` (unless parsing external data).
- **Overly clever metaprogramming** — `method_missing`, `define_method`, and `class_eval` make code untraceable. Use only when the alternative is significantly more verbose.

## Dos
- Use `frozen_string_literal: true` in every file — it catches mutation bugs and is a prerequisite for future Ruby immutability features.
- Use RuboCop for linting and formatting — it enforces community conventions automatically.
- Use keyword arguments for clarity — `create_user(name: "Alice", role: :admin)` reads better than positional args.
- Use `Enumerable` methods (`map`, `select`, `reduce`) instead of manual loops.
- Use `Struct.new` or `Data.define` for simple value objects — avoid full classes for data containers.
- Use `freeze` on constants: `ALLOWED_ROLES = %i[admin user viewer].freeze`.
- Use `begin/rescue/ensure` with specific exception classes for structured error handling.

## Don'ts
- Don't rescue `Exception` — it catches `SignalException`, `SystemExit`, and `NoMemoryError`, preventing graceful shutdown.
- Don't use `eval` or `class_eval` with user input — it enables remote code execution.
- Don't mutate frozen strings — enable `frozen_string_literal: true` globally and use `String.new` or `dup` when mutation is needed.
- Don't use global variables (`$var`) — they create invisible coupling between modules.
- Don't put logic in `initialize` beyond assignment — use factory methods or builder patterns for complex construction.
- Don't use `Thread.new` for background work in web processes — use Sidekiq or GoodJob.
- Don't chain more than 3-4 method calls without intermediate variables — it hampers debugging.
