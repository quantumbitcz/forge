# Eval: SQL injection via string concatenation

## Language: typescript

## Context
Database query built by concatenating user input directly into SQL string.

## Code Under Review

```typescript
// file: src/repositories/user-repo.ts
import { db } from '../database';

async function findUser(username: string): Promise<User | null> {
  const query = `SELECT * FROM users WHERE username = '${username}'`;
  const result = await db.raw(query);
  return result.rows[0] ?? null;
}

async function searchUsers(term: string): Promise<User[]> {
  const sql = "SELECT * FROM users WHERE name LIKE '%" + term + "%'";
  return (await db.raw(sql)).rows;
}
```

## Expected Behavior
Reviewer should flag SQL injection vulnerabilities from string concatenation in queries.
