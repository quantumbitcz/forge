# Readability Patterns (C#)

## records-over-classes

**Instead of:**
```csharp
public class UserDto
{
    public string Name { get; set; }
    public string Email { get; set; }

    public override bool Equals(object obj) =>
        obj is UserDto other && Name == other.Name && Email == other.Email;

    public override int GetHashCode() =>
        HashCode.Combine(Name, Email);
}
```

**Do this:**
```csharp
public record UserDto(string Name, string Email);
```

**Why:** Records (C# 9+) generate equality, hash code, deconstruction, and `ToString()` automatically. They signal immutable data transfer intent at the type level.

## collection-expressions

**Instead of:**
```csharp
var list = new List<string> { "alpha", "beta", "gamma" };
var array = new string[] { "alpha", "beta", "gamma" };
```

**Do this:**
```csharp
List<string> list = ["alpha", "beta", "gamma"];
string[] array = ["alpha", "beta", "gamma"];
```

**Why:** Collection expressions (C# 12) provide a unified, terse syntax for initializing any collection type, reducing boilerplate and making the target type the single source of truth.

## switch-expression

**Instead of:**
```csharp
string GetStatusMessage(OrderStatus status)
{
    switch (status)
    {
        case OrderStatus.Pending: return "Waiting for processing";
        case OrderStatus.Shipped: return "On its way";
        case OrderStatus.Delivered: return "Delivered";
        default: throw new ArgumentOutOfRangeException(nameof(status));
    }
}
```

**Do this:**
```csharp
string GetStatusMessage(OrderStatus status) => status switch
{
    OrderStatus.Pending   => "Waiting for processing",
    OrderStatus.Shipped   => "On its way",
    OrderStatus.Delivered => "Delivered",
    _ => throw new ArgumentOutOfRangeException(nameof(status)),
};
```

**Why:** Switch expressions (C# 8+) are expression-bodied, exhaustiveness-checked, and eliminate repetitive `case`/`return` syntax. The compiler warns if an enum arm is missing.
