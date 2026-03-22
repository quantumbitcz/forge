# Error Handling Patterns (Go)

## wrap-errors

**Instead of:**
```go
if err != nil {
    return fmt.Errorf("failed to load config: " + err.Error())
}
```

**Do this:**
```go
if err != nil {
    return fmt.Errorf("load config: %w", err)
}
```

**Why:** Using `%w` preserves the error chain so callers can unwrap and inspect with `errors.Is` / `errors.As`.

## sentinel-errors

**Instead of:**
```go
if err.Error() == "not found" {
    // handle
}
```

**Do this:**
```go
var ErrNotFound = errors.New("not found")

if errors.Is(err, ErrNotFound) {
    // handle
}
```

**Why:** String comparison is brittle and breaks when error messages change; sentinel errors provide a stable identity.

## error-types

**Instead of:**
```go
return fmt.Errorf("validation: field %s invalid", name)
```

**Do this:**
```go
type ValidationError struct {
    Field  string
    Reason string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation: field %s %s", e.Field, e.Reason)
}
```

**Why:** Custom error types let callers extract structured context via `errors.As` instead of parsing strings.

## check-all-errors

**Instead of:**
```go
file, _ := os.Open(path)
defer file.Close()
```

**Do this:**
```go
file, err := os.Open(path)
if err != nil {
    return fmt.Errorf("open %s: %w", path, err)
}
defer file.Close()
```

**Why:** Ignoring errors hides failures that surface later as confusing nil-pointer panics or corrupt state.
