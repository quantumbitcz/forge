# Readability Patterns (Swift)

## nesting

**Instead of:**
```swift
func handle(_ request: Request) -> Response {
    if request.isValid {
        if let user = request.user {
            if user.isActive {
                return serve(request, for: user)
            }
        }
    }
    return .badRequest
}
```

**Do this:**
```swift
func handle(_ request: Request) -> Response {
    guard request.isValid else { return .badRequest }
    guard let user = request.user else { return .badRequest }
    guard user.isActive else { return .badRequest }
    return serve(request, for: user)
}
```

**Why:** `guard` statements flatten nested `if`s by exiting early, keeping the main logic at the top indentation level.

## naming

**Instead of:**
```swift
func calc(_ a: Double, _ b: Double, _ t: Bool) -> Double {
    t ? a * 1.2 : a + b
}
```

**Do this:**
```swift
func totalPrice(subtotal: Double, shipping: Double, isTaxable: Bool) -> Double {
    isTaxable ? subtotal * 1.2 : subtotal + shipping
}
```

**Why:** Descriptive parameter names and labels make call sites read like prose: `totalPrice(subtotal: 50, shipping: 5, isTaxable: true)`.

## guard-clauses

**Instead of:**
```swift
func process(_ items: [Item]?) {
    if let items {
        if !items.isEmpty {
            for item in items {
                save(item)
            }
        }
    }
}
```

**Do this:**
```swift
func process(_ items: [Item]?) {
    guard let items, !items.isEmpty else { return }
    for item in items {
        save(item)
    }
}
```

**Why:** Guard clauses handle the degenerate cases upfront so the meaningful work is not buried inside conditionals.

## protocol-extensions

**Instead of:**
```swift
struct Dog: Describable {
    var name: String
    var description: String { "Dog: \(name)" }
}
struct Cat: Describable {
    var name: String
    var description: String { "Cat: \(name)" }
}
```

**Do this:**
```swift
protocol Describable {
    var name: String { get }
}

extension Describable {
    var description: String { "\(Self.self): \(name)" }
}
```

**Why:** A default implementation in a protocol extension removes identical boilerplate from every conforming type while still allowing overrides.
