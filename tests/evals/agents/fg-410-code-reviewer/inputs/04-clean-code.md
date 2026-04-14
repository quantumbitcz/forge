# Eval: Clean code with no issues

## Language: typescript

## Context
Well-structured, idiomatic TypeScript code with proper error handling and naming.

## Code Under Review

```typescript
// file: src/services/order-service.ts
interface Order {
  id: string;
  items: OrderItem[];
  status: OrderStatus;
}

type OrderStatus = 'pending' | 'confirmed' | 'shipped';

interface OrderItem {
  productId: string;
  quantity: number;
  price: number;
}

function calculateTotal(order: Order): number {
  return order.items.reduce(
    (sum, item) => sum + item.price * item.quantity,
    0,
  );
}

function isShippable(order: Order): boolean {
  return order.status === 'confirmed' && order.items.length > 0;
}
```

## Expected Behavior
No findings expected. Clean, well-structured code.
