# Eval: Circular dependency between modules

## Language: typescript

## Context
Module A imports Module B, and Module B imports Module A, creating a circular dependency.

## Code Under Review

```typescript
// file: src/modules/order/order-service.ts
import { PaymentService } from '../payment/payment-service';

export class OrderService {
  constructor(private paymentService: PaymentService) {}

  async createOrder(items: Item[]): Promise<Order> {
    const order = new Order(items);
    await this.paymentService.charge(order.total);
    return order;
  }
}

// file: src/modules/payment/payment-service.ts
import { OrderService } from '../order/order-service';

export class PaymentService {
  constructor(private orderService: OrderService) {}

  async refund(orderId: string): Promise<void> {
    const order = await this.orderService.getOrder(orderId);
    await this.processRefund(order.total);
  }
}
```

## Expected Behavior
Reviewer should flag circular dependency between order and payment modules.
