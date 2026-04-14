# Eval: Well-optimized query patterns

## Language: typescript

## Context
Queries with proper pagination, selective columns, and batch loading.

## Code Under Review

```typescript
// file: src/repositories/user-repo.ts
import { db } from '../database';

async function findUsers(page: number, pageSize: number): Promise<User[]> {
  return db('users')
    .select('id', 'name', 'email')
    .orderBy('created_at', 'desc')
    .limit(pageSize)
    .offset(page * pageSize);
}

async function findWithOrders(userIds: string[]): Promise<UserWithOrders[]> {
  const users = await db('users').whereIn('id', userIds);
  const orders = await db('orders').whereIn('user_id', userIds);
  return mergeUsersWithOrders(users, orders);
}
```

## Expected Behavior
No performance findings expected. Proper pagination, column selection, and batch loading.
