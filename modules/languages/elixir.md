# Elixir Language Conventions

> Support tier: contract-verified

## Type System

- Elixir is dynamically typed. Use **Dialyzer** via `@spec` and `@type` annotations for optional static analysis.
- Use typespecs for all public functions: `@spec create_user(String.t(), String.t()) :: {:ok, User.t()} | {:error, String.t()}`.
- Define custom types with `@type`: `@type user :: %User{name: String.t(), email: String.t()}`.
- Use atoms (`:ok`, `:error`) for tags and identifiers — they're interned and compared by identity.
- Use structs (`%User{}`) for typed maps with compile-time field checking.
- Max line length: 98 characters (Elixir formatter default).

## Null Safety / Error Handling

- Elixir uses `nil` but prefers tagged tuples over nil-checking: `{:ok, value}` / `{:error, reason}`.
- Use `with` for composing operations that may fail:
  ```elixir
  with {:ok, user} <- find_user(id),
       {:ok, order} <- create_order(user, items) do
    {:ok, order}
  end
  ```
- Use `case` for pattern matching on results: `case File.read(path) do {:ok, data} -> ...; {:error, reason} -> ... end`.
- Reserve `raise` for truly exceptional conditions (programming bugs) — use `{:ok, _}` / `{:error, _}` for expected failures.
- Use `bang!` functions (`File.read!`, `Repo.get!`) only when failure should crash the process (let-it-crash philosophy).
- Supervisors restart crashed processes automatically — design for failure, not prevention.

## Async / Concurrency

- Elixir runs on the BEAM VM — lightweight processes (~2KB each) with preemptive scheduling.
- Use `Task.async/await` for concurrent operations: `tasks = Enum.map(urls, &Task.async(fn -> fetch(&1) end)); results = Task.await_many(tasks)`.
- Use `GenServer` for stateful processes with a message-based interface.
- Use `Agent` for simple shared state: `Agent.start_link(fn -> %{} end)`.
- Use `Supervisor` trees for fault tolerance — every process should be supervised.
- Use `Task.Supervisor` for dynamically supervised tasks.
- Never share state between processes via mutable references — communicate via message passing.

## Idiomatic Patterns

- **Pipe operator** (`|>`) for data transformation chains:
  ```elixir
  users
  |> Enum.filter(&(&1.active))
  |> Enum.map(& &1.email)
  |> Enum.sort()
  ```
- **Pattern matching** everywhere — function heads, `case`, `with`, assignments: `{:ok, %{name: name}} = result`.
- **Guard clauses** on function definitions: `def process(x) when is_integer(x) and x > 0 do ... end`.
- **Multi-clause functions** for polymorphism via pattern matching:
  ```elixir
  def handle_event(:click, state), do: ...
  def handle_event(:hover, state), do: ...
  ```
- **Comprehensions** for transformation: `for %{role: :admin} = user <- users, do: user.email`.
- **Protocols** for polymorphism across types (like interfaces).
- **Behaviours** for defining callback contracts (like abstract base classes).

## Naming Idioms

- Modules: `PascalCase` (`MyApp.UserService`).
- Functions and variables: `snake_case`.
- Atoms: `snake_case` (`:user_created`).
- Files: `snake_case.ex` (source), `snake_case_test.exs` (test).
- Constants: not a concept — use module attributes: `@max_retries 5`.
- Predicates: `active?`, `valid?`, `empty?` — trailing `?`.
- Dangerous functions: `delete!`, `update!` — trailing `!` (may raise).
- Private functions: `defp` keyword, no underscore prefix.

## Logging

- Use the built-in **`Logger`** module (stdlib) — part of Elixir, no external dependency, supports structured metadata out of the box.
- For JSON output in production: **LoggerJSON** (`logger_json` hex package) as the formatter backend.
- Configure in `config/config.exs`:
  ```elixir
  config :logger, :default_handler,
    config: [type: :standard_io],
    level: :info

  # For JSON output in production:
  config :logger, :default_handler,
    config: [
      formatter: {LoggerJSON.Formatters.Basic, []}
    ]
  ```
- Use structured metadata — set request-scoped context once in a Plug/middleware:
  ```elixir
  Logger.metadata(correlation_id: correlation_id, trace_id: trace_id)
  Logger.info("Order created", order_id: order.id, user_id: user.id)
  ```
- Use the anonymous function form for expensive log messages — the function is only called if the level is enabled:
  ```elixir
  Logger.debug(fn -> "Complex state: #{inspect(complex_data)}" end)
  ```
- Logger metadata is process-scoped (bound to the BEAM process) — set it once in a Plug/middleware and it propagates through the entire request lifecycle automatically.
- Use `Logger.warning/2` (not `Logger.warn/2`, which is deprecated since Elixir 1.15).
- Never use `IO.puts`, `IO.inspect`, or `dbg` for operational logging — they lack levels, metadata, and routing.
- PII/credential/financial data logging rules: see `shared/logging-rules.md`.

## Anti-Patterns

- **Long process mailboxes** — a process receiving messages faster than it processes them causes memory issues. Use backpressure (GenStage, Flow) or load shedding.
- **Blocking in GenServer callbacks** — a blocked `handle_call` blocks all callers. Delegate to a Task for slow work.
- **Using `String.to_atom/1` with user input** — atoms are never garbage collected; unbounded atom creation causes memory exhaustion.
- **Ignoring OTP principles** — starting unsupervised processes, using bare `spawn`, or catching exits instead of supervising.
- **Premature optimization with ETS** — use process state (GenServer/Agent) first; ETS is for shared read-heavy concurrent access.

## Dos
- Use the pipe operator (`|>`) for data transformation — it's Elixir's most idiomatic pattern.
- Use tagged tuples (`{:ok, value}` / `{:error, reason}`) for function return values — not exceptions.
- Use pattern matching in function heads for dispatch — it's cleaner than conditional logic.
- Use supervisors for all processes — design applications as supervision trees.
- Use `@spec` and `@type` annotations and run Dialyzer in CI.
- Use `mix format` for consistent code style — it's built into the language toolchain.
- Use `with` for composing multiple fallible operations — it replaces nested `case` statements.
- All data structures are immutable — every transformation returns a new value. Embrace pipe operator `|>` chains for data transformations.
- Use Agent or GenServer for managed mutable state — these provide controlled, process-isolated mutation.

## Don'ts
- Don't use `String.to_atom/1` with user input — atoms are never garbage collected.
- Don't use bare `spawn` in production — always use supervised processes (`Task.Supervisor`, `DynamicSupervisor`).
- Don't catch `exit` signals to prevent restarts — let supervisors handle process failures.
- Don't use mutable state outside of processes — all state must be process-owned.
- Don't use `Enum` functions on large datasets that could be lazy — use `Stream` for lazy evaluation.
- Don't block `GenServer` callbacks with slow operations — delegate to Tasks.
- Don't use `:erlang.apply/3` or `Code.eval_string` with user input — it enables arbitrary code execution.
- Don't use Process dictionary as a mutable state workaround — it's invisible to other processes and untraceable.
- Don't use ETS as a substitute for properly designed GenServer state unless you need concurrent read access from multiple processes.
- Don't write OOP-style GenServer with massive state — decompose into smaller, focused processes.
- Don't chain `Enum.map |> Enum.filter |> Enum.reduce` — use `for` comprehensions for multi-step transforms with filtering.
- Don't create deep module hierarchies mimicking Java packages — keep modules flat and descriptive.
