# Readability Patterns (Rust)

## nesting

**Instead of:**
```rust
fn handle(req: Option<Request>) -> Result<Response> {
    if let Some(r) = req {
        if let Some(body) = r.body {
            if !body.is_empty() {
                return process(&body);
            }
            return Err(anyhow!("empty body"));
        }
        return Err(anyhow!("no body"));
    }
    Err(anyhow!("no request"))
}
```

**Do this:**
```rust
fn handle(req: Option<Request>) -> Result<Response> {
    let r = req.ok_or_else(|| anyhow!("no request"))?;
    let body = r.body.ok_or_else(|| anyhow!("no body"))?;
    if body.is_empty() {
        return Err(anyhow!("empty body"));
    }
    process(&body)
}
```

**Why:** Converting `Option` to `Result` with `ok_or_else` and using `?` flattens nested `if let` chains into a linear flow.

## naming

**Instead of:**
```rust
fn proc_dat(d: &[u8], f: bool) -> Vec<u8> {
    let mut r = Vec::new();
    // ...
    r
}
```

**Do this:**
```rust
fn compress_payload(data: &[u8], include_header: bool) -> Vec<u8> {
    let mut output = Vec::new();
    // ...
    output
}
```

**Why:** Descriptive names for functions, parameters, and locals eliminate the need for comments and make code self-documenting.

## guard-clauses

**Instead of:**
```rust
fn withdraw(account: &mut Account, amount: u64) -> Result<()> {
    if account.active {
        if amount > 0 {
            if account.balance >= amount {
                account.balance -= amount;
                Ok(())
            } else {
                Err(anyhow!("insufficient funds"))
            }
        } else {
            Err(anyhow!("invalid amount"))
        }
    } else {
        Err(anyhow!("inactive account"))
    }
}
```

**Do this:**
```rust
fn withdraw(account: &mut Account, amount: u64) -> Result<()> {
    if !account.active {
        return Err(anyhow!("inactive account"));
    }
    if amount == 0 {
        return Err(anyhow!("invalid amount"));
    }
    if account.balance < amount {
        return Err(anyhow!("insufficient funds"));
    }
    account.balance -= amount;
    Ok(())
}
```

**Why:** Guard clauses reject invalid states upfront so the core logic sits at the top level without deep nesting.

## iterator-chains

**Instead of:**
```rust
let mut result = Vec::new();
for item in &items {
    if item.is_active() {
        let name = item.name().to_uppercase();
        result.push(name);
    }
}
result.sort();
```

**Do this:**
```rust
let mut result: Vec<String> = items
    .iter()
    .filter(|item| item.is_active())
    .map(|item| item.name().to_uppercase())
    .collect();
result.sort();
```

**Why:** Iterator chains express data transformations declaratively, reducing mutable state and making the pipeline of operations explicit.
