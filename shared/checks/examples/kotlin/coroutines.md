# Coroutine Patterns (Kotlin)

## structured-concurrency

**Instead of:**
```kotlin
fun fetchDashboard(userId: String) {
    GlobalScope.launch {
        val profile = userService.getProfile(userId)
        val orders = orderService.getRecent(userId)
        emit(DashboardData(profile, orders))
    }
}
```

**Do this:**
```kotlin
suspend fun fetchDashboard(userId: String): DashboardData =
    coroutineScope {
        val profile = async { userService.getProfile(userId) }
        val orders = async { orderService.getRecent(userId) }
        DashboardData(profile.await(), orders.await())
    }
```

**Why:** `coroutineScope` ties child coroutines to the caller's lifecycle so failures propagate and cancellation is automatic, whereas `GlobalScope` leaks work that outlives its purpose.

## blocking-calls

**Instead of:**
```kotlin
suspend fun readConfig(): Config {
    val text = File("app.yml").readText()   // blocks the dispatcher thread
    return yaml.decodeFromString(text)
}
```

**Do this:**
```kotlin
suspend fun readConfig(): Config =
    withContext(Dispatchers.IO) {
        val text = File("app.yml").readText()
        yaml.decodeFromString(text)
    }
```

**Why:** Blocking I/O on `Dispatchers.Default` (or an event-loop thread) starves the shared pool; `withContext(Dispatchers.IO)` moves the work to a thread designed for blocking.

## withcontext-io

**Instead of:**
```kotlin
suspend fun saveReport(report: Report) {
    launch(Dispatchers.IO) {
        db.insert(report)
        fileStore.upload(report.toPdf())
    }
}
```

**Do this:**
```kotlin
suspend fun saveReport(report: Report) {
    withContext(Dispatchers.IO) {
        db.insert(report)
        fileStore.upload(report.toPdf())
    }
}
```

**Why:** `withContext` suspends the caller until the block completes and propagates exceptions normally, while `launch` fires-and-forgets, hiding failures and breaking sequential expectations.

## supervisorscope

**Instead of:**
```kotlin
suspend fun notifyAll(userIds: List<String>) = coroutineScope {
    userIds.forEach { id ->
        launch { notificationService.send(id) }  // one failure cancels all
    }
}
```

**Do this:**
```kotlin
suspend fun notifyAll(userIds: List<String>) = supervisorScope {
    userIds.map { id ->
        async {
            runCatching { notificationService.send(id) }
        }
    }.awaitAll()
}
```

**Why:** `supervisorScope` isolates child failures so one user's notification error does not cancel the remaining sends, which is the correct semantics for fan-out best-effort work.
