# Eval: Query on unindexed column

## Language: typescript

## Context
Frequent queries filter on columns that are not indexed, causing full table scans.

## Code Under Review

```typescript
// file: src/repositories/product-repo.ts
import { db } from '../database';

async function findByCategory(category: string): Promise<Product[]> {
  return db('products')
    .where('category_name', category)
    .orderBy('created_at', 'desc');
}

async function searchByDescription(term: string): Promise<Product[]> {
  return db('products')
    .whereILike('description', `%${term}%`)
    .limit(50);
}
```

## Expected Behavior
Reviewer should flag queries on likely-unindexed columns (category_name, description with LIKE).
