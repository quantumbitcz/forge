# Readability Patterns (Kotlin)

## nesting

**Instead of:**
```kotlin
fun processOrder(order: Order): Receipt {
    if (order.items.isNotEmpty()) {
        if (order.isPaid()) {
            if (inventory.allAvailable(order.items)) {
                val shipment = shipping.create(order)
                return Receipt(order.id, shipment.trackingId)
            } else {
                throw OutOfStockException(order.id)
            }
        } else {
            throw PaymentRequiredException(order.id)
        }
    } else {
        throw EmptyOrderException(order.id)
    }
}
```

**Do this:**
```kotlin
fun processOrder(order: Order): Receipt {
    require(order.items.isNotEmpty()) { "Order ${order.id} has no items" }
    check(order.isPaid()) { "Order ${order.id} is not paid" }
    check(inventory.allAvailable(order.items)) { "Stock unavailable for ${order.id}" }

    val shipment = shipping.create(order)
    return Receipt(order.id, shipment.trackingId)
}
```

**Why:** Flattening nested branches into sequential preconditions keeps the indentation at one level and makes the happy path a straight line from top to bottom.

## naming

**Instead of:**
```kotlin
fun calc(ls: List<Item>): Double {
    var res = 0.0
    for (l in ls) {
        val d = l.p * l.q
        if (l.dc) res += d * 0.9 else res += d
    }
    return res
}
```

**Do this:**
```kotlin
fun calculateOrderTotal(items: List<Item>): Double {
    var total = 0.0
    for (item in items) {
        val linePrice = item.price * item.quantity
        total += if (item.discountEligible) linePrice * DISCOUNT_FACTOR else linePrice
    }
    return total
}
```

**Why:** Descriptive names eliminate the need for mental mapping between abbreviations and concepts, letting readers understand logic without cross-referencing other code.

## guard-clauses

**Instead of:**
```kotlin
fun sendInvite(user: User, event: Event): InviteResult {
    if (user.isActive) {
        if (!event.isFull()) {
            if (!event.hasAttendee(user.id)) {
                event.addAttendee(user.id)
                mailer.sendInvite(user.email, event)
                return InviteResult.Sent
            } else {
                return InviteResult.AlreadyInvited
            }
        } else {
            return InviteResult.EventFull
        }
    } else {
        return InviteResult.InactiveUser
    }
}
```

**Do this:**
```kotlin
fun sendInvite(user: User, event: Event): InviteResult {
    if (!user.isActive) return InviteResult.InactiveUser
    if (event.isFull()) return InviteResult.EventFull
    if (event.hasAttendee(user.id)) return InviteResult.AlreadyInvited

    event.addAttendee(user.id)
    mailer.sendInvite(user.email, event)
    return InviteResult.Sent
}
```

**Why:** Guard clauses at the top dispose of edge cases immediately, so the remaining function body only contains the primary logic at a single indentation level.

## extract-function

**Instead of:**
```kotlin
fun importCsv(file: File): ImportResult {
    val lines = file.readLines().drop(1)
    val records = mutableListOf<Record>()
    val errors = mutableListOf<String>()
    for (line in lines) {
        val cols = line.split(",")
        if (cols.size < 4) { errors.add("Bad column count: $line"); continue }
        val amount = cols[2].toBigDecimalOrNull()
        if (amount == null) { errors.add("Bad amount: ${cols[2]}"); continue }
        if (amount <= BigDecimal.ZERO) { errors.add("Negative amount: $amount"); continue }
        records.add(Record(cols[0], cols[1], amount, cols[3]))
    }
    return ImportResult(records, errors)
}
```

**Do this:**
```kotlin
fun importCsv(file: File): ImportResult {
    val lines = file.readLines().drop(1)
    val (records, errors) = lines.map { parseLine(it) }.partition { it.isSuccess }
    return ImportResult(records.map { it.getOrThrow() }, errors.map { it.exceptionOrNull()!!.message!! })
}

private fun parseLine(line: String): Result<Record> = runCatching {
    val cols = line.split(",")
    require(cols.size >= 4) { "Bad column count: $line" }
    val amount = requireNotNull(cols[2].toBigDecimalOrNull()) { "Bad amount: ${cols[2]}" }
    require(amount > BigDecimal.ZERO) { "Negative amount: $amount" }
    Record(cols[0], cols[1], amount, cols[3])
}
```

**Why:** Extracting the per-line parsing into its own function makes each piece independently testable, names the operation, and keeps the main function focused on orchestration.
