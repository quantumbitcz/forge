# Null Safety Patterns (Kotlin)

## safe-call-pattern

**Instead of:**
```kotlin
fun getCity(user: User): String {
    if (user.address != null) {
        if (user.address.city != null) {
            return user.address.city.uppercase()
        }
    }
    return "UNKNOWN"
}
```

**Do this:**
```kotlin
fun getCity(user: User): String =
    user.address?.city?.uppercase() ?: "UNKNOWN"
```

**Why:** Safe-call chaining with an elvis fallback eliminates nested null checks and expresses the happy path in a single expression.

## exhaustive-when

**Instead of:**
```kotlin
fun render(state: UiState): View {
    if (state is UiState.Loading) return spinner()
    if (state is UiState.Error) return errorBanner(state.msg)
    return content((state as UiState.Success).data)
}
```

**Do this:**
```kotlin
fun render(state: UiState): View = when (state) {
    is UiState.Loading -> spinner()
    is UiState.Error   -> errorBanner(state.msg)
    is UiState.Success -> content(state.data)
}
```

**Why:** Exhaustive `when` on sealed types gives a compile-time guarantee that every variant is handled, so adding a new subclass becomes a build error instead of a runtime bug.

## let-binding

**Instead of:**
```kotlin
fun sendNotification(user: User) {
    if (user.email != null) {
        val trimmed = user.email.trim()
        if (trimmed.isNotEmpty()) {
            mailer.send(trimmed, buildBody(user))
        }
    }
}
```

**Do this:**
```kotlin
fun sendNotification(user: User) {
    user.email?.trim()?.takeIf { it.isNotEmpty() }?.let { email ->
        mailer.send(email, buildBody(user))
    }
}
```

**Why:** Scoping with `let` keeps the non-null value named and confined, avoiding accidental reuse of the nullable reference later in the function.

## elvis-default

**Instead of:**
```kotlin
fun resolveTimeout(config: Config?): Duration {
    var timeout = DEFAULT_TIMEOUT
    if (config != null && config.timeoutMs != null) {
        timeout = config.timeoutMs.milliseconds
    }
    return timeout
}
```

**Do this:**
```kotlin
fun resolveTimeout(config: Config?): Duration =
    config?.timeoutMs?.milliseconds ?: DEFAULT_TIMEOUT
```

**Why:** The elvis operator replaces mutable-variable-plus-conditional with a single immutable expression, making the default value immediately visible.
