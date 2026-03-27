# C++ Language Conventions

## Type System

- Use modern C++ (C++17 minimum, C++20/23 preferred). Enable via `-std=c++20` or `set(CMAKE_CXX_STANDARD 20)`.
- Use `auto` for type deduction where the type is obvious from context: `auto result = compute();`.
- Use `std::optional<T>` (C++17) for values that may be absent — never use sentinel values or pointer null checks.
- Use `std::variant<T...>` for sum types and `std::visit` for pattern matching.
- Use `constexpr` for compile-time computation: `constexpr int max_size = 1024;`.
- Use `concepts` (C++20) for constraining template parameters: `template<std::integral T> T add(T a, T b)`.
- Use `enum class` (scoped enums) instead of `enum` — prevents implicit int conversion.
- Use `std::string_view` for non-owning string references — avoids unnecessary copies.

## Null Safety / Error Handling

- Use `std::optional<T>` for values that may not exist — never use `nullptr` for optional return values.
- Use `std::expected<T, E>` (C++23) or a library equivalent for result types: success or typed error.
- Use exceptions for truly exceptional conditions; use error codes or result types for expected failures.
- Use RAII (Resource Acquisition Is Initialization) for all resource management — destructors handle cleanup.
- Never throw exceptions in destructors — it causes `std::terminate` during stack unwinding.
- Use `noexcept` on functions that don't throw — enables compiler optimizations and documents intent.
- Use `[[nodiscard]]` on functions whose return value must not be ignored.

## Async / Concurrency

- Use `std::jthread` (C++20) over `std::thread` — it auto-joins on destruction, preventing resource leaks.
- Use `std::mutex` with `std::lock_guard` or `std::scoped_lock` — never lock/unlock manually.
- Use `std::atomic<T>` for lock-free shared state on primitive types.
- Use `std::async` with `std::launch::async` for simple concurrent tasks — but prefer a thread pool for production.
- Use `std::condition_variable` for producer-consumer patterns — always check the predicate in a loop.
- Use `std::shared_mutex` for read-heavy workloads (multiple readers, exclusive writer).
- Avoid `volatile` for synchronization — it does not provide atomicity or memory ordering guarantees.

## Idiomatic Patterns

- **RAII** — acquire resources in constructors, release in destructors. No explicit `close()`, `free()`, or `release()`.
- **Smart pointers**: `std::unique_ptr<T>` for single ownership, `std::shared_ptr<T>` for shared ownership, raw pointers for non-owning references only.
- **Range-based for loops**: `for (const auto& item : items) { ... }`.
- **Structured bindings** (C++17): `auto [key, value] = map.extract(it);`.
- **std::ranges** (C++20) for algorithm composition:
  ```cpp
  auto active_emails = users
      | std::views::filter([](const User& u) { return u.active; })
      | std::views::transform([](const User& u) { return u.email; });
  ```
- **Move semantics** — use `std::move` to transfer ownership; implement move constructors for resource-owning types.
- **`const` correctness** — mark everything `const` that doesn't need to be mutable.

## Naming Idioms

- Files: `snake_case.cpp`, `snake_case.hpp` (or `.h`).
- Classes and structs: `PascalCase`.
- Functions and methods: `snake_case` (Google/LLVM style) or `camelCase` (Qt/Unreal style) — pick one consistently.
- Variables and parameters: `snake_case`.
- Constants and constexpr: `kPascalCase` (Google style) or `UPPER_SNAKE_CASE`.
- Member variables: trailing underscore (`name_`) or `m_` prefix (`m_name`).
- Namespaces: `lowercase` (`my_project::utils`).
- Template parameters: `PascalCase` (`template<typename ValueType>`).

## Anti-Patterns

- **Manual memory management** — use smart pointers and RAII; raw `new`/`delete` is almost never needed in modern C++.
- **`using namespace std;`** — pollutes the global namespace and causes ambiguity. Use `std::` prefix or selective `using std::string;`.
- **C-style casts** — use `static_cast<T>`, `dynamic_cast<T>`, `const_cast<T>`, or `reinterpret_cast<T>` for explicit, searchable, type-safe casts.
- **`volatile` for synchronization** — it doesn't guarantee atomicity or memory ordering; use `std::atomic`.
- **Returning raw pointers from functions** — return `std::unique_ptr` for ownership transfer, `std::optional` for optional values.

## Dos
- Use RAII for all resource management — file handles, network connections, locks, memory.
- Use `std::unique_ptr` for single-owner heap allocation — raw `new`/`delete` is a code smell.
- Use `const` everywhere — `const` references, `const` methods, `const` variables.
- Use `std::optional<T>` for values that may not exist — never use sentinel values.
- Use `enum class` instead of `enum` — prevents implicit conversion and namespace pollution.
- Use `[[nodiscard]]` on functions whose return values must be checked.
- Use `constexpr` for compile-time computation — it catches errors at compile time and eliminates runtime cost.

## Don'ts
- Don't use raw `new`/`delete` — use smart pointers and containers.
- Don't use C-style arrays — use `std::array<T, N>` (fixed size) or `std::vector<T>` (dynamic).
- Don't use C-style casts — use `static_cast`, `dynamic_cast`, etc.
- Don't throw in destructors — it causes `std::terminate` during stack unwinding.
- Don't use `using namespace std;` in headers — it pollutes every file that includes the header.
- Don't use `volatile` for thread synchronization — use `std::atomic` or mutexes.
- Don't use `std::endl` for line endings — it flushes the buffer; use `'\n'` instead.
- Don't write C-style `void*` + casts — use templates or `std::variant`.
- Don't use `new`/`delete` — use `std::unique_ptr` and `std::make_unique`.
- Don't write C-style error codes — use exceptions or `std::expected` (C++23).
