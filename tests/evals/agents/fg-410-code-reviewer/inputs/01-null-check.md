# Eval: Nullable dereference without null check

## Language: typescript

## Context
Function accesses properties on a possibly-null value without guarding.

## Code Under Review

```typescript
// file: src/user-service.ts
interface User {
  id: string;
  profile: { name: string; email: string } | null;
}

function getDisplayName(user: User): string {
  return user.profile.name.toUpperCase();
}

function sendWelcome(user: User): void {
  const email = user.profile.email;
  console.log(`Sending welcome to ${email}`);
}
```

## Expected Behavior
Reviewer should flag nullable dereference on `user.profile.name` and `user.profile.email` without a null check.
