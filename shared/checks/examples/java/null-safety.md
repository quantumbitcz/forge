# Null Safety Patterns (Java)

## optional-usage

**Instead of:**
```java
public String getCityName(User user) {
    if (user != null && user.getAddress() != null) {
        return user.getAddress().getCity();
    }
    return "Unknown";
}
```

**Do this:**
```java
public String getCityName(User user) {
    return Optional.ofNullable(user)
        .map(User::getAddress)
        .map(Address::getCity)
        .orElse("Unknown");
}
```

**Why:** `Optional` chaining makes the nullable traversal explicit and eliminates the risk of forgetting an intermediate null check when the object graph grows.

## null-check-before-use

**Instead of:**
```java
public void processOrder(Order order) {
    // NPE if customer is null
    var email = order.getCustomer().getEmail();
    notificationService.send(email, buildReceipt(order));
}
```

**Do this:**
```java
public void processOrder(Order order) {
    var customer = Objects.requireNonNull(order.getCustomer(),
        () -> "Order %s has no customer".formatted(order.getId()));
    notificationService.send(customer.getEmail(), buildReceipt(order));
}
```

**Why:** `Objects.requireNonNull` fails fast with a descriptive message at the point where the contract is violated, rather than producing a cryptic NPE several lines later.

## objects-requirenonnull

**Instead of:**
```java
public UserService(UserRepository repo, EventPublisher events) {
    if (repo == null) throw new IllegalArgumentException("repo must not be null");
    if (events == null) throw new IllegalArgumentException("events must not be null");
    this.repo = repo;
    this.events = events;
}
```

**Do this:**
```java
public UserService(UserRepository repo, EventPublisher events) {
    this.repo = Objects.requireNonNull(repo, "repo");
    this.events = Objects.requireNonNull(events, "events");
}
```

**Why:** `Objects.requireNonNull` is the idiomatic one-liner for constructor null guards, reducing boilerplate while producing a clear `NullPointerException` with the parameter name.

## optional-chaining

**Instead of:**
```java
public BigDecimal getDiscountRate(Long customerId) {
    Customer c = customerRepo.findById(customerId).orElse(null);
    if (c == null) return BigDecimal.ZERO;
    LoyaltyTier tier = c.getLoyaltyTier();
    if (tier == null) return BigDecimal.ZERO;
    return tier.getDiscountRate();
}
```

**Do this:**
```java
public BigDecimal getDiscountRate(Long customerId) {
    return customerRepo.findById(customerId)
        .map(Customer::getLoyaltyTier)
        .map(LoyaltyTier::getDiscountRate)
        .orElse(BigDecimal.ZERO);
}
```

**Why:** Unwrapping an `Optional` only to re-check for null defeats the purpose; staying in the `Optional` pipeline keeps every step safe and the fallback explicit.
