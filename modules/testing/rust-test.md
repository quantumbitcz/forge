# Rust Testing Conventions
> Support tier: contract-verified
## Test Structure

Unit tests live in a `#[cfg(test)] mod tests {}` block at the bottom of the module file. Integration tests live in the `tests/` directory at the crate root — each file is compiled as a separate crate, so they test only the public API.

```rust
// src/user_service.rs
pub fn create(email: &str) -> Result<User, AppError> { ... }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_with_valid_email_returns_user() {
        let user = create("alice@example.com").unwrap();
        assert_eq!(user.email, "alice@example.com");
    }
}
```

## Naming

- Test function: `{action}_{context}__{expectation}` or plain snake_case description
- Module: `tests` (unit) or descriptive name (`integration_create_user`)
- Integration test files in `tests/`: `{feature}.rs`

## Assertions

```rust
assert!(condition);
assert_eq!(left, right);
assert_ne!(left, right);
assert!(value > 0, "expected positive, got {}", value);  // message arg supported

// For Result/Option:
assert!(result.is_ok());
let val = result.unwrap();          // panics on Err — acceptable in tests
let val = result.expect("msg");     // prefer over unwrap() for better failures
```

## Panic Testing

```rust
#[test]
#[should_panic(expected = "index out of bounds")]
fn panics_on_invalid_index() {
    let v: Vec<i32> = vec![];
    let _ = v[1];
}
```

Use `expected = "..."` to assert on the panic message substring — prevents accidentally passing on the wrong panic.

## Async Testing

```rust
#[tokio::test]
async fn fetch_user_returns_data() {
    let user = service.fetch("uid-1").await.unwrap();
    assert_eq!(user.name, "Alice");
}

// async-std
#[async_std::test]
async fn test_something() { ... }
```

Match the async runtime used by the production code. Do not mix `tokio` and `async-std`.

## Mocking

Rust has no built-in mock framework. Options:
- **`mockall`** — derive `#[automock]` on traits for generated mocks with call expectations
- **Manual implementations** — implement the trait with hardcoded test behaviour (simplest)
- **`wiremock`** — for HTTP service mocking in integration tests

Inject dependencies as generic bounds or trait objects to enable test doubles.

```rust
#[automock]
pub trait UserRepository {
    fn find(&self, id: Uuid) -> Option<User>;
}

// In test:
let mut mock = MockUserRepository::new();
mock.expect_find().returning(|_| Some(user));
```

## Integration Tests

```
tests/
  create_user.rs      // tests public API end-to-end
  auth_flow.rs
```

Integration tests have access only to the public API. Use `use my_crate::...` at the top. Share test helpers via `tests/common/mod.rs` (not auto-discovered as a test target).

## What NOT to Test

- Trait implementations that delegate entirely to the standard library
- `Display` / `Debug` format strings with no custom logic
- Auto-derived `PartialEq`, `Clone`, `serde::Serialize` on simple structs
- Compiler-enforced invariants (ownership, lifetimes) — the compiler already tests these

## Anti-Patterns

- `std::thread::sleep` — use tokio's `time::sleep` in async tests or eliminate the delay
- `unwrap()` on `Mutex::lock()` in tests (may poison on panic) — use `unwrap_or_else` or restructure
- Large integration tests in unit test modules — keep `#[cfg(test)]` focused on unit behaviour
- Ignoring `#[test]` output with `println!` spam — use `eprintln!` and `-- --nocapture` flag intentionally
- `unsafe` in test code without a documented justification
