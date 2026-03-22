# Concurrency Patterns (Swift)

## async-await

**Instead of:**
```swift
func fetchUser(id: Int, completion: @escaping (Result<User, Error>) -> Void) {
    URLSession.shared.dataTask(with: url) { data, _, error in
        if let error { completion(.failure(error)); return }
        let user = try! JSONDecoder().decode(User.self, from: data!)
        completion(.success(user))
    }.resume()
}
```

**Do this:**
```swift
func fetchUser(id: Int) async throws -> User {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(User.self, from: data)
}
```

**Why:** `async/await` replaces nested callbacks with linear code, making error propagation automatic via `throws`.

## task-groups

**Instead of:**
```swift
func loadAll(ids: [Int]) async throws -> [Item] {
    var items: [Item] = []
    for id in ids {
        items.append(try await fetchItem(id))
    }
    return items
}
```

**Do this:**
```swift
func loadAll(ids: [Int]) async throws -> [Item] {
    try await withThrowingTaskGroup(of: Item.self) { group in
        for id in ids {
            group.addTask { try await fetchItem(id) }
        }
        return try await group.reduce(into: []) { $0.append($1) }
    }
}
```

**Why:** Task groups run fetches concurrently instead of sequentially, using structured concurrency that automatically cancels on failure.

## actors

**Instead of:**
```swift
class Counter {
    private var value = 0
    private let lock = NSLock()

    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
```

**Do this:**
```swift
actor Counter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}
```

**Why:** Actors serialize access to mutable state at compile time, eliminating manual locking and the data races that come from forgetting it.

## main-actor

**Instead of:**
```swift
func refreshUI(with items: [Item]) {
    DispatchQueue.main.async {
        self.dataSource = items
        self.tableView.reloadData()
    }
}
```

**Do this:**
```swift
@MainActor
func refreshUI(with items: [Item]) {
    dataSource = items
    tableView.reloadData()
}
```

**Why:** `@MainActor` guarantees main-thread execution at compile time, so the compiler catches off-main-thread calls instead of crashing at runtime.
