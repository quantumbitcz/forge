# Eval: Clean architecture with proper layer separation

## Language: kotlin

## Context
Domain service depends only on abstractions, with proper port/adapter separation.

## Code Under Review

```kotlin
// file: src/main/kotlin/domain/OrderService.kt
package com.app.domain

class OrderService(
    private val orderRepository: OrderRepository,
    private val paymentGateway: PaymentGateway,
) {
    fun placeOrder(command: PlaceOrderCommand): OrderId {
        val order = Order.create(command.items)
        orderRepository.save(order)
        paymentGateway.charge(order.total)
        return order.id
    }
}

interface OrderRepository {
    fun save(order: Order): Order
    fun findById(id: OrderId): Order?
}

interface PaymentGateway {
    fun charge(amount: Money)
}
```

## Expected Behavior
No findings expected. Proper clean architecture with domain depending only on abstractions.
