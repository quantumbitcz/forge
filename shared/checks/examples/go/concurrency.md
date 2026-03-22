# Concurrency Patterns (Go)

## goroutine-leak-prevention

**Instead of:**
```go
go func() {
    val := <-ch // blocks forever if ch is never closed
    process(val)
}()
```

**Do this:**
```go
go func() {
    select {
    case val := <-ch:
        process(val)
    case <-ctx.Done():
        return
    }
}()
```

**Why:** Without a cancellation path, goroutines block indefinitely and leak memory for the lifetime of the process.

## channel-patterns

**Instead of:**
```go
ch := make(chan Result)
for _, item := range items {
    go func(it Item) { ch <- process(it) }(item)
}
```

**Do this:**
```go
ch := make(chan Result, len(items))
for _, item := range items {
    go func(it Item) { ch <- process(it) }(item)
}
for range items {
    results = append(results, <-ch)
}
```

**Why:** A buffered channel sized to the expected sends prevents goroutines from blocking on write and makes collection straightforward.

## waitgroup

**Instead of:**
```go
for _, u := range urls {
    go fetch(u)
}
time.Sleep(5 * time.Second) // hope everything finishes
```

**Do this:**
```go
var wg sync.WaitGroup
for _, u := range urls {
    wg.Add(1)
    go func(url string) {
        defer wg.Done()
        fetch(url)
    }(u)
}
wg.Wait()
```

**Why:** `sync.WaitGroup` provides a deterministic join point instead of relying on arbitrary sleep durations.

## context-cancellation

**Instead of:**
```go
func fetchAll(urls []string) error {
    for _, u := range urls {
        if err := fetch(u); err != nil {
            return err
        }
    }
    return nil
}
```

**Do this:**
```go
func fetchAll(ctx context.Context, urls []string) error {
    for _, u := range urls {
        if err := ctx.Err(); err != nil {
            return err
        }
        if err := fetch(ctx, u); err != nil {
            return err
        }
    }
    return nil
}
```

**Why:** Threading `context.Context` lets callers enforce deadlines and cancel long-running work cooperatively.
