# Testing Patterns (Rust)

## unit-test-module

**Instead of:**
```rust
// tests in a separate file with duplicated imports
// test_math.rs
use crate::math::add;
#[test]
fn test_add() { assert_eq!(add(1, 2), 3); }
```

**Do this:**
```rust
fn add(a: i32, b: i32) -> i32 { a + b }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adds_positive_numbers() {
        assert_eq!(add(1, 2), 3);
    }
}
```

**Why:** The `#[cfg(test)] mod tests` pattern keeps unit tests next to the code they cover and grants access to private items via `use super::*`.

## integration-tests

**Instead of:**
```rust
// putting integration tests inside src/ with #[cfg(test)]
#[cfg(test)]
mod integration {
    fn test_full_pipeline() { /* ... */ }
}
```

**Do this:**
```rust
// tests/pipeline.rs (top-level tests/ directory)
use my_crate::Pipeline;

#[test]
fn full_pipeline_produces_output() {
    let p = Pipeline::new();
    let result = p.run("input.txt").unwrap();
    assert!(!result.is_empty());
}
```

**Why:** Files in the `tests/` directory compile as separate crates that test the public API, ensuring your library works as an external consumer would use it.

## assert-macros

**Instead of:**
```rust
#[test]
fn test_contains() {
    let v = vec![1, 2, 3];
    if !v.contains(&2) {
        panic!("expected 2 in {:?}", v);
    }
}
```

**Do this:**
```rust
#[test]
fn contains_expected_value() {
    let v = vec![1, 2, 3];
    assert!(v.contains(&2), "expected 2 in {v:?}");
}
```

**Why:** `assert!` and `assert_eq!` print both expected and actual values on failure, producing clearer diagnostics than manual panics.

## proptest

**Instead of:**
```rust
#[test]
fn test_reverse() {
    assert_eq!(reverse(reverse("hello")), "hello");
    assert_eq!(reverse(reverse("")), "");
    // hoping two cases are enough...
}
```

**Do this:**
```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn reverse_is_involution(s in "\\PC*") {
        assert_eq!(reverse(&reverse(&s)), s);
    }
}
```

**Why:** Property-based tests generate hundreds of random inputs, catching edge cases that hand-picked examples miss.
