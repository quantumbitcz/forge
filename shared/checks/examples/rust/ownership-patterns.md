# Ownership Patterns (Rust)

## borrowing-vs-cloning

**Instead of:**
```rust
fn process(data: Vec<u8>) -> Result<()> {
    let copy = data.clone(); // unnecessary clone
    validate(&copy)?;
    transform(data)
}
```

**Do this:**
```rust
fn process(data: &[u8]) -> Result<()> {
    validate(data)?;
    transform(data)
}
```

**Why:** Borrowing with `&[u8]` avoids allocation and works with both `Vec<u8>` and slices; clone only when you truly need a separate owned copy.

## lifetime-elision

**Instead of:**
```rust
fn first_word<'a>(s: &'a str) -> &'a str {
    s.split_whitespace().next().unwrap_or(s)
}
```

**Do this:**
```rust
fn first_word(s: &str) -> &str {
    s.split_whitespace().next().unwrap_or(s)
}
```

**Why:** Rust's elision rules infer the lifetime when there is exactly one input reference, so the explicit annotation adds noise without clarity.

## arc-mutex

**Instead of:**
```rust
static mut COUNTER: u64 = 0; // unsafe global mutable state

fn increment() {
    unsafe { COUNTER += 1; }
}
```

**Do this:**
```rust
use std::sync::{Arc, Mutex};

let counter = Arc::new(Mutex::new(0u64));
let c = Arc::clone(&counter);
std::thread::spawn(move || {
    *c.lock().unwrap() += 1;
});
```

**Why:** `Arc<Mutex<T>>` provides safe shared mutable state across threads without `unsafe` blocks or data races.

## cow

**Instead of:**
```rust
fn normalize(input: &str) -> String {
    if input.contains('\t') {
        input.replace('\t', "    ")
    } else {
        input.to_string() // allocates even when unchanged
    }
}
```

**Do this:**
```rust
use std::borrow::Cow;

fn normalize(input: &str) -> Cow<'_, str> {
    if input.contains('\t') {
        Cow::Owned(input.replace('\t', "    "))
    } else {
        Cow::Borrowed(input)
    }
}
```

**Why:** `Cow` avoids allocation in the common no-change path while still returning an owned `String` when modification is needed.
