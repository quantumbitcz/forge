# Eval: N+1 query pattern in loop

## Language: typescript

## Context
Handler fetches a list, then queries each item individually in a loop.

## Code Under Review

```typescript
// file: src/services/report-service.ts
import { db } from '../database';

async function generateReport(): Promise<ReportRow[]> {
  const orders = await db('orders').select('*');
  const rows: ReportRow[] = [];

  for (const order of orders) {
    const customer = await db('customers')
      .where('id', order.customer_id)
      .first();
    const items = await db('order_items')
      .where('order_id', order.id);
    rows.push({ order, customer, items });
  }

  return rows;
}
```

## Expected Behavior
Reviewer should flag N+1 query pattern: fetching customers and items one-by-one inside a loop.
