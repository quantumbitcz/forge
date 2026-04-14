# Eval: Duplicated logic violating DRY principle

## Language: typescript

## Context
Two functions with nearly identical validation logic that should be extracted.

## Code Under Review

```typescript
// file: src/handlers.ts
function createUser(data: any): boolean {
  if (!data.name || data.name.length < 2) return false;
  if (!data.email || !data.email.includes('@')) return false;
  if (!data.age || data.age < 18) return false;
  return saveUser(data);
}

function updateUser(id: string, data: any): boolean {
  if (!data.name || data.name.length < 2) return false;
  if (!data.email || !data.email.includes('@')) return false;
  if (!data.age || data.age < 18) return false;
  return patchUser(id, data);
}
```

## Expected Behavior
Reviewer should flag the duplicated validation logic across createUser and updateUser.
