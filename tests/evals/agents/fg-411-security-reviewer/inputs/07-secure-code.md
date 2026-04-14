# Eval: Secure code with proper practices

## Language: typescript

## Context
Well-secured endpoint with parameterized queries, input validation, and auth middleware.

## Code Under Review

```typescript
// file: src/routes/users.ts
import { Router } from 'express';
import { authMiddleware } from '../middleware/auth';
import { db } from '../database';
import { z } from 'zod';

const router = Router();
const userSchema = z.object({
  name: z.string().min(1).max(100),
  email: z.string().email(),
});

router.get('/api/users/:id', authMiddleware, async (req, res) => {
  const user = await db('users').where('id', req.params.id).first();
  if (!user) return res.status(404).json({ error: 'Not found' });
  res.json(user);
});
```

## Expected Behavior
No security findings expected. Parameterized query, auth middleware, input validation all present.
