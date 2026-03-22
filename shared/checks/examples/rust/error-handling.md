# Error Handling Patterns (Rust)

## result-propagation

**Instead of:**
```rust
fn read_config(path: &str) -> Config {
    let text = std::fs::read_to_string(path).unwrap();
    toml::from_str(&text).unwrap()
}
```

**Do this:**
```rust
fn read_config(path: &str) -> Result<Config, Box<dyn std::error::Error>> {
    let text = std::fs::read_to_string(path)?;
    let config = toml::from_str(&text)?;
    Ok(config)
}
```

**Why:** Returning `Result` lets callers decide how to handle failure instead of panicking the entire program.

## custom-error-types

**Instead of:**
```rust
fn parse(input: &str) -> Result<Ast, String> {
    Err(format!("unexpected token at position {}", pos))
}
```

**Do this:**
```rust
#[derive(Debug)]
enum ParseError {
    UnexpectedToken { pos: usize },
    UnexpectedEof,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnexpectedToken { pos } => write!(f, "unexpected token at {pos}"),
            Self::UnexpectedEof => write!(f, "unexpected end of input"),
        }
    }
}

impl std::error::Error for ParseError {}
```

**Why:** Typed errors enable callers to match on variants and handle each case precisely, unlike opaque strings.

## thiserror

**Instead of:**
```rust
impl std::fmt::Display for AppError { /* boilerplate */ }
impl std::error::Error for AppError { /* boilerplate */ }
impl From<io::Error> for AppError { /* boilerplate */ }
```

**Do this:**
```rust
use thiserror::Error;

#[derive(Debug, Error)]
enum AppError {
    #[error("io failure: {0}")]
    Io(#[from] std::io::Error),
    #[error("parse failure: {0}")]
    Parse(#[from] serde_json::Error),
}
```

**Why:** `thiserror` derives `Display`, `Error`, and `From` impls, eliminating repetitive boilerplate for library-style errors.

## question-mark-operator

**Instead of:**
```rust
fn load(path: &Path) -> Result<Data> {
    let bytes = match std::fs::read(path) {
        Ok(b) => b,
        Err(e) => return Err(e.into()),
    };
    let data = match serde_json::from_slice(&bytes) {
        Ok(d) => d,
        Err(e) => return Err(e.into()),
    };
    Ok(data)
}
```

**Do this:**
```rust
fn load(path: &Path) -> Result<Data> {
    let bytes = std::fs::read(path)?;
    let data = serde_json::from_slice(&bytes)?;
    Ok(data)
}
```

**Why:** The `?` operator replaces verbose match-and-return patterns, keeping the happy path linear and readable.
