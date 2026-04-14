# Eval: Weak cryptographic algorithm usage

## Language: typescript

## Context
Code uses MD5 for password hashing instead of a modern algorithm like bcrypt.

## Code Under Review

```typescript
// file: src/auth/password.ts
import { createHash } from 'crypto';

function hashPassword(password: string): string {
  return createHash('md5').update(password).digest('hex');
}

function verifyPassword(password: string, hash: string): boolean {
  const computed = createHash('md5').update(password).digest('hex');
  return computed === hash;
}
```

## Expected Behavior
Reviewer should flag MD5 usage for password hashing as a weak cryptographic choice.
