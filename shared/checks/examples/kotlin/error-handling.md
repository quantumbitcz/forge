# Error Handling Patterns (Kotlin)

## domain-exceptions

**Instead of:**
```kotlin
fun findOrder(id: OrderId): Order {
    val row = repo.findById(id)
        ?: throw RuntimeException("Not found: $id")
    if (row.cancelled) throw RuntimeException("Order cancelled")
    return row.toDomain()
}
```

**Do this:**
```kotlin
fun findOrder(id: OrderId): Order {
    val row = repo.findById(id)
        ?: throw OrderNotFoundException(id)
    if (row.cancelled) throw OrderCancelledException(id)
    return row.toDomain()
}
```

**Why:** Domain-specific exception types let callers handle each failure case independently and produce meaningful API error responses without parsing message strings.

## sealed-result

**Instead of:**
```kotlin
fun transfer(from: AccountId, to: AccountId, amount: Money): Boolean {
    return try {
        ledger.debit(from, amount)
        ledger.credit(to, amount)
        true
    } catch (e: Exception) {
        logger.error("Transfer failed", e)
        false
    }
}
```

**Do this:**
```kotlin
sealed interface TransferResult {
    data class Success(val txId: TxId) : TransferResult
    data class InsufficientFunds(val available: Money) : TransferResult
    data class AccountLocked(val until: Instant) : TransferResult
}

fun transfer(from: AccountId, to: AccountId, amount: Money): TransferResult {
    val balance = ledger.balance(from)
    if (balance < amount) return TransferResult.InsufficientFunds(balance)
    val txId = ledger.execute(from, to, amount)
    return TransferResult.Success(txId)
}
```

**Why:** A sealed result hierarchy forces callers to handle every outcome at compile time and carries structured data per variant, whereas a boolean or a caught exception loses context.

## early-return-pattern

**Instead of:**
```kotlin
fun processPayment(request: PaymentRequest): PaymentResponse {
    if (request.amount > BigDecimal.ZERO) {
        if (request.currency in SUPPORTED_CURRENCIES) {
            if (rateLimiter.tryAcquire(request.merchantId)) {
                return gateway.charge(request)
            } else {
                throw RateLimitExceededException(request.merchantId)
            }
        } else {
            throw UnsupportedCurrencyException(request.currency)
        }
    } else {
        throw InvalidAmountException(request.amount)
    }
}
```

**Do this:**
```kotlin
fun processPayment(request: PaymentRequest): PaymentResponse {
    require(request.amount > BigDecimal.ZERO) { "Amount must be positive" }
    check(request.currency in SUPPORTED_CURRENCIES) { "Unsupported: ${request.currency}" }
    if (!rateLimiter.tryAcquire(request.merchantId))
        throw RateLimitExceededException(request.merchantId)

    return gateway.charge(request)
}
```

**Why:** Early returns flatten deeply nested conditionals into a linear sequence of preconditions, making the happy path obvious and each validation independently readable.

## named-constants

**Instead of:**
```kotlin
fun retryOperation(block: () -> Unit) {
    repeat(3) { attempt ->
        try {
            block(); return
        } catch (e: TransientException) {
            Thread.sleep(1000L * (attempt + 1))
        }
    }
    throw RetriesExhaustedException()
}
```

**Do this:**
```kotlin
private const val MAX_RETRIES = 3
private const val BACKOFF_BASE_MS = 1000L

fun retryOperation(block: () -> Unit) {
    repeat(MAX_RETRIES) { attempt ->
        try {
            block(); return
        } catch (e: TransientException) {
            Thread.sleep(BACKOFF_BASE_MS * (attempt + 1))
        }
    }
    throw RetriesExhaustedException()
}
```

**Why:** Named constants document intent (what the number means) and provide a single change-point when tuning, eliminating scattered magic literals.
