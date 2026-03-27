# Python Language Conventions

## Type System

- Add `from __future__ import annotations` at the top of every module — enables PEP 563 postponed evaluation, allowing forward references and cleaner type hints without circular import issues.
- Annotate all function signatures and return types (PEP 484) — parameters, return type, and `self` in methods (except `self`/`cls` which are implicit).
- Use `|` union syntax (Python 3.10+) for union types: `str | None` instead of `Optional[str]`.
- Use `TypeVar` for generic functions; use `Protocol` for structural subtyping (duck-typed interfaces).
- Use `dataclasses.dataclass` for plain data containers — prefer `frozen=True` for immutable value objects.
- Use `NamedTuple` for simple typed tuples.
- Max line length: 120 characters (ruff default).

## Null Safety / Error Handling

- Python has no null-safety built in — be explicit with `Optional[T]` / `T | None` in type hints and guard at boundaries.
- Never use bare `except:` — always name the exception type(s): `except ValueError:` or `except (ValueError, KeyError):`.
- Use custom exception classes inheriting from a domain-specific base for user-facing errors.
- Raise exceptions at the point of detection; catch and handle at the layer that knows the recovery strategy.
- Use `assert` only for internal invariants (not for input validation) — `assert` is stripped in optimized mode (`-O`).

## Async / Concurrency

- Use `async def` for all I/O-bound functions; use `asyncio.gather()` for concurrent I/O operations.
- Never use synchronous I/O (`open()`, `os.path.exists()`, `requests.get()`) inside `async def` functions — it blocks the event loop for all coroutines.
- Use `aiofiles` for async file I/O; `httpx.AsyncClient` for async HTTP.
- CPU-bound work: use `asyncio.to_thread()` or a `ProcessPoolExecutor` — do not block the event loop.
- Do not use `time.sleep()` in async context — use `asyncio.sleep()`.
- `asyncio.gather()` fails fast on the first exception by default — pass `return_exceptions=True` for partial-failure tolerance.

## Idiomatic Patterns

- **f-strings** for string interpolation (Python 3.6+): `f"Hello, {name}!"` — not `%` formatting or `.format()`.
- **Context managers** (`with` statement) for resource management: files, database connections, locks. Implement `__enter__`/`__exit__` or use `contextlib.contextmanager` for generator-based context managers.
- **List/dict/set comprehensions** over `map()`/`filter()` for readability: `[x * 2 for x in items if x > 0]`.
- **`dataclasses`** over hand-written `__init__`/`__repr__`/`__eq__` for data containers.
- **`@property`** for computed attributes; avoid direct attribute access for values with non-trivial derivation.
- **`pathlib.Path`** over `os.path` for file system operations.

## Naming Idioms

- Modules and packages: `snake_case`.
- Classes: `PascalCase`.
- Functions, methods, variables: `snake_case`.
- Constants: `UPPER_SNAKE_CASE` (module-level).
- Private names: single leading underscore (`_private`); name-mangled: double leading underscore (`__mangled`).
- Boolean variables/properties: `is_x`, `has_x`, `can_x`.
- Type aliases: `PascalCase` (e.g., `UserId = NewType('UserId', int)`).

## Anti-Patterns

- **Mutable default arguments:** `def fn(items=[])` shares the same list across all calls. Use `None` and assign inside the function.
- **Bare `except:`:** Catches `SystemExit`, `KeyboardInterrupt`, and generator `StopIteration` — breaks normal Python control flow. Always name exception types.
- **`print()` in production code:** Use `logging` or `structlog` with appropriate levels and structured output.
- **Synchronous I/O in async context:** Blocks the entire event loop. Offload via `asyncio.to_thread()`.
- **Global mutable state:** Module-level mutable variables are shared across all uses; use dependency injection or context variables (`contextvars.ContextVar`).
- **`import *`:** Pollutes the namespace and makes it impossible to trace where names come from. Always use explicit imports.
- **Missing `await` on a coroutine:** Silently returns a coroutine object instead of executing it — type checkers and `asyncio` debug mode catch this.
- **`isinstance` chains as poor-man's dispatch:** Use a dispatch dictionary, `functools.singledispatch`, or a proper class hierarchy.

## Dos
- Use `from __future__ import annotations` at the top of every module for forward references.
- Use `dataclasses` (with `frozen=True` for immutability) for data containers over manual `__init__`.
- Use f-strings for string formatting — never `%` formatting or `.format()`.
- Use `pathlib.Path` over `os.path` for file system operations.
- Use `async def` for all I/O-bound functions and `asyncio.gather()` for concurrency.
- Use context managers (`with` statement) for resource management — files, connections, locks.
- Use `ruff` for linting and formatting — it replaces `flake8`, `isort`, and `black` in one tool.

## Don'ts
- Don't use bare `except:` — it catches `SystemExit` and `KeyboardInterrupt`, breaking normal control flow.
- Don't use mutable default arguments (`def fn(items=[])`) — they're shared across calls.
- Don't use `print()` in production — use `logging` or `structlog` with appropriate levels.
- Don't use synchronous I/O in async contexts — it blocks the entire event loop.
- Don't use `import *` — it pollutes the namespace and makes tracing imports impossible.
- Don't use `global` variables for runtime state — use dependency injection or `contextvars`.
- Don't use `assert` for input validation — assertions are stripped in optimized mode (`-O`).
- Don't write Java-style `AbstractBaseFactory` class hierarchies — use `Protocol` + `@dataclass` for structural subtyping.
- Don't use `@staticmethod` when a module-level function works — classes are not namespaces in Python.
- Don't create single-method classes — use plain functions; closures replace most strategy/command patterns.
