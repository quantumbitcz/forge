# Testing Patterns (C#)

## fluent-assertions

**Instead of:**
```csharp
[Fact]
public void CreateOrder_SetsDefaults()
{
    var order = Order.Create("item-1", 2);
    Assert.NotNull(order);
    Assert.Equal(OrderStatus.Pending, order.Status);
    Assert.Equal(2, order.Quantity);
}
```

**Do this:**
```csharp
[Fact]
public void CreateOrder_SetsDefaults()
{
    var order = Order.Create("item-1", quantity: 2);

    order.Should().NotBeNull();
    order.Status.Should().Be(OrderStatus.Pending);
    order.Quantity.Should().Be(2);
}
```

**Why:** FluentAssertions produces human-readable failure messages (`Expected order.Status to be Pending, but found Shipped`) instead of generic `Assert.Equal failed` output, making test failures self-diagnosing.

## test-builder-pattern

**Instead of:**
```csharp
[Fact]
public void DiscountApplied_WhenPremiumUser()
{
    var user = new User { Id = 1, Name = "Test", Email = "t@t.com",
        Plan = Plan.Premium, CreatedAt = DateTime.UtcNow.AddYears(-1),
        IsVerified = true, Country = "US" };
    var cart = new Cart { UserId = 1, Items = new List<CartItem>
        { new CartItem { ProductId = 1, Price = 100m, Qty = 1 } } };

    var total = _svc.CalculateTotal(user, cart);
    Assert.Equal(90m, total);
}
```

**Do this:**
```csharp
[Fact]
public void DiscountApplied_WhenPremiumUser()
{
    var user = new UserBuilder().WithPlan(Plan.Premium).Build();
    var cart = new CartBuilder().WithItem(price: 100m).Build();

    var total = _svc.CalculateTotal(user, cart);

    total.Should().Be(90m);
}
```

**Why:** Test builders hide irrelevant fields and highlight what matters for each test case. When a constructor changes, you fix one builder instead of hundreds of test methods.
