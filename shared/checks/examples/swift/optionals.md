# Optional Patterns (Swift)

## optional-binding

**Instead of:**
```swift
func greet(_ name: String?) {
    if name != nil {
        print("Hello, \(name!)")
    }
}
```

**Do this:**
```swift
func greet(_ name: String?) {
    if let name {
        print("Hello, \(name)")
    }
}
```

**Why:** `if let` unwraps once and binds a non-optional, removing the risk of a force-unwrap crash if the condition changes.

## guard-let

**Instead of:**
```swift
func process(data: Data?) {
    if let data {
        let parsed = parse(data)
        validate(parsed)
        save(parsed)
    }
}
```

**Do this:**
```swift
func process(data: Data?) {
    guard let data else { return }
    let parsed = parse(data)
    validate(parsed)
    save(parsed)
}
```

**Why:** `guard let` exits early and keeps the unwrapped value available for the rest of the scope, avoiding rightward drift.

## nil-coalescing

**Instead of:**
```swift
func displayName(for user: User) -> String {
    if let nickname = user.nickname {
        return nickname
    } else {
        return user.fullName
    }
}
```

**Do this:**
```swift
func displayName(for user: User) -> String {
    user.nickname ?? user.fullName
}
```

**Why:** The `??` operator expresses a default value in a single expression, which is shorter and immediately shows the fallback.

## optional-chaining

**Instead of:**
```swift
func cityName(from order: Order?) -> String? {
    if let order = order {
        if let address = order.shipping {
            return address.city
        }
    }
    return nil
}
```

**Do this:**
```swift
func cityName(from order: Order?) -> String? {
    order?.shipping?.city
}
```

**Why:** Optional chaining collapses nested nil checks into a single expression that short-circuits to `nil` at the first missing link.
