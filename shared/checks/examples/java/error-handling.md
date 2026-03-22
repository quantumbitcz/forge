# Error Handling Patterns (Java)

## specific-exceptions

**Instead of:**
```java
public User findUser(UUID id) {
    try {
        return repo.findById(id).orElseThrow();
    } catch (Exception e) {
        log.error("Error", e);
        throw new RuntimeException(e);
    }
}
```

**Do this:**
```java
public User findUser(UUID id) {
    return repo.findById(id)
        .orElseThrow(() -> new UserNotFoundException(id));
}
```

**Why:** Catching generic `Exception` swallows programming errors and obscures the root cause; throwing a domain-specific exception lets callers react precisely and produces actionable log output.

## try-with-resources

**Instead of:**
```java
public List<String> readLines(Path path) throws IOException {
    BufferedReader reader = Files.newBufferedReader(path);
    try {
        return reader.lines().toList();
    } finally {
        reader.close(); // silent leak if close() itself throws
    }
}
```

**Do this:**
```java
public List<String> readLines(Path path) throws IOException {
    try (var reader = Files.newBufferedReader(path)) {
        return reader.lines().toList();
    }
}
```

**Why:** Try-with-resources guarantees the reader is closed even when both the body and close throw, properly suppressing the secondary exception instead of losing the primary one.

## custom-exception-hierarchy

**Instead of:**
```java
// caller has no way to distinguish causes
throw new RuntimeException("Insufficient funds");
throw new RuntimeException("Account locked until " + until);
throw new RuntimeException("Daily limit exceeded");
```

**Do this:**
```java
public sealed abstract class PaymentException extends RuntimeException
    permits InsufficientFundsException, AccountLockedException, DailyLimitExceededException {
    protected PaymentException(String message) { super(message); }
}

public final class InsufficientFundsException extends PaymentException {
    private final BigDecimal available;
    public InsufficientFundsException(BigDecimal available) {
        super("Insufficient funds: %s available".formatted(available));
        this.available = available;
    }
    public BigDecimal getAvailable() { return available; }
}
```

**Why:** A sealed exception hierarchy lets callers pattern-match exhaustively (Java 21+), carries structured context per failure type, and prevents ad-hoc subclassing outside the domain.

## early-return-pattern

**Instead of:**
```java
public OrderResponse placeOrder(OrderRequest request) {
    if (request.getItems() != null && !request.getItems().isEmpty()) {
        if (inventoryService.allAvailable(request.getItems())) {
            if (paymentService.authorize(request.getPayment())) {
                var order = orderService.create(request);
                return OrderResponse.success(order.getId());
            } else {
                return OrderResponse.paymentFailed();
            }
        } else {
            return OrderResponse.outOfStock();
        }
    } else {
        return OrderResponse.emptyCart();
    }
}
```

**Do this:**
```java
public OrderResponse placeOrder(OrderRequest request) {
    if (request.getItems() == null || request.getItems().isEmpty())
        return OrderResponse.emptyCart();
    if (!inventoryService.allAvailable(request.getItems()))
        return OrderResponse.outOfStock();
    if (!paymentService.authorize(request.getPayment()))
        return OrderResponse.paymentFailed();

    var order = orderService.create(request);
    return OrderResponse.success(order.getId());
}
```

**Why:** Inverting conditions into early returns removes nesting levels, puts error paths up front, and leaves the happy path as the un-indented final block.
