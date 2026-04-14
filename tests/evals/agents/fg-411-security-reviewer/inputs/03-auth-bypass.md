# Eval: Authentication bypass via missing auth check

## Language: typescript

## Context
Admin endpoint lacks authentication middleware, allowing unauthenticated access.

## Code Under Review

```typescript
// file: src/routes/admin.ts
import { Router } from 'express';
import { deleteUser, resetDatabase } from '../admin-service';

const router = Router();

// Public - no auth middleware
router.delete('/api/admin/users/:id', async (req, res) => {
  await deleteUser(req.params.id);
  res.json({ success: true });
});

router.post('/api/admin/reset-db', async (req, res) => {
  await resetDatabase();
  res.json({ success: true });
});

export default router;
```

## Expected Behavior
Reviewer should flag missing authentication middleware on admin endpoints.
