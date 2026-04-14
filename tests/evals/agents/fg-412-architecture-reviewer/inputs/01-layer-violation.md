# Eval: Layer violation -- domain imports infrastructure

## Language: kotlin

## Context
Domain layer directly imports infrastructure/persistence classes, violating clean architecture boundaries.

## Code Under Review

```kotlin
// file: src/main/kotlin/domain/OrderService.kt
package com.app.domain

import com.app.infrastructure.JpaOrderRepository
import com.app.infrastructure.RedisCache
import jakarta.persistence.EntityManager

class OrderService(
    private val repository: JpaOrderRepository,
    private val cache: RedisCache,
    private val entityManager: EntityManager,
) {
    fun placeOrder(order: Order): OrderId {
        entityManager.flush()
        return repository.save(order).id
    }
}
```

## Expected Behavior
Reviewer should flag domain layer importing infrastructure classes (JPA, Redis, EntityManager).
