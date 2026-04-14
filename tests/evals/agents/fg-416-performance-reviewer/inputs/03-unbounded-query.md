# Eval: Unbounded query without pagination

## Language: typescript

## Context
Query returns all rows from a potentially large table without limit or pagination.

## Code Under Review

```typescript
// file: src/repositories/audit-repo.ts
import { db } from '../database';

async function getAllLogs(): Promise<AuditLog[]> {
  return db('audit_logs').select('*').orderBy('created_at', 'desc');
}

async function getEventsByType(type: string): Promise<Event[]> {
  return db('events').where('type', type);
}
```

## Expected Behavior
Reviewer should flag unbounded queries that could return millions of rows without limit/pagination.
