# Error Handling Patterns (C#)

## result-pattern

**Instead of:**
```csharp
public User GetUser(int id)
{
    var user = _db.Users.Find(id);
    if (user == null)
        throw new NotFoundException($"User {id} not found");
    return user;
}
```

**Do this:**
```csharp
public Result<User> GetUser(int id)
{
    var user = _db.Users.Find(id);
    return user is not null
        ? Result<User>.Success(user)
        : Result<User>.Failure($"User {id} not found");
}
```

**Why:** Exceptions are expensive and hide control flow. A `Result<T>` pattern makes failure an explicit return value, letting callers decide how to handle missing data without catching exceptions for expected scenarios.

## using-disposable

**Instead of:**
```csharp
public byte[] ReadFile(string path)
{
    var stream = new FileStream(path, FileMode.Open);
    var reader = new BinaryReader(stream);
    var data = reader.ReadBytes((int)stream.Length);
    reader.Dispose();
    stream.Dispose();
    return data;
}
```

**Do this:**
```csharp
public byte[] ReadFile(string path)
{
    using var stream = new FileStream(path, FileMode.Open);
    using var reader = new BinaryReader(stream);
    return reader.ReadBytes((int)stream.Length);
}
```

**Why:** `using` declarations (C# 8+) guarantee deterministic disposal even when exceptions propagate, without nesting try-finally blocks. Resources are disposed in reverse declaration order at scope exit.

## pattern-matching-null

**Instead of:**
```csharp
if (order != null && order.Customer != null && order.Customer.Address != null)
{
    return order.Customer.Address.City;
}
return "Unknown";
```

**Do this:**
```csharp
return order?.Customer?.Address?.City ?? "Unknown";
```

**Why:** Null-conditional chaining (`?.`) with the null-coalescing operator (`??`) expresses the null-safe traversal in a single expression, eliminating deeply nested null checks.
