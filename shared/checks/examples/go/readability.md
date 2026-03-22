# Readability Patterns (Go)

## nesting

**Instead of:**
```go
func process(r *http.Request) error {
    if r != nil {
        if r.Body != nil {
            data, err := io.ReadAll(r.Body)
            if err == nil {
                return handle(data)
            }
            return err
        }
        return errors.New("empty body")
    }
    return errors.New("nil request")
}
```

**Do this:**
```go
func process(r *http.Request) error {
    if r == nil {
        return errors.New("nil request")
    }
    if r.Body == nil {
        return errors.New("empty body")
    }
    data, err := io.ReadAll(r.Body)
    if err != nil {
        return err
    }
    return handle(data)
}
```

**Why:** Early returns flatten nesting so the happy path reads top-to-bottom without indentation pyramids.

## naming

**Instead of:**
```go
func ProcUsrData(d []byte) (*UDResult, error) {
    var udr UDResult
    // ...
}
```

**Do this:**
```go
func ParseUserProfile(data []byte) (*UserProfile, error) {
    var profile UserProfile
    // ...
}
```

**Why:** Go favours clear, unabbreviated names; short variable names are fine for small scopes, but exported symbols need full words.

## guard-clauses

**Instead of:**
```go
func (s *Service) Delete(id string) error {
    if id != "" {
        item, err := s.repo.Find(id)
        if err == nil && item != nil {
            return s.repo.Delete(id)
        }
        return fmt.Errorf("not found: %s", id)
    }
    return errors.New("empty id")
}
```

**Do this:**
```go
func (s *Service) Delete(id string) error {
    if id == "" {
        return errors.New("empty id")
    }
    item, err := s.repo.Find(id)
    if err != nil {
        return fmt.Errorf("find %s: %w", id, err)
    }
    if item == nil {
        return fmt.Errorf("not found: %s", id)
    }
    return s.repo.Delete(id)
}
```

**Why:** Guard clauses handle invalid states first, keeping the main logic at the lowest indentation level.

## accept-interfaces-return-structs

**Instead of:**
```go
func NewService() ServiceInterface {
    return &service{} // hides the concrete type behind an interface
}
```

**Do this:**
```go
type Store interface {
    Get(id string) (*Item, error)
}

func NewService(store Store) *Service {
    return &Service{store: store}
}
```

**Why:** Accepting interfaces decouples from implementations; returning structs preserves full type information and avoids premature abstraction.
