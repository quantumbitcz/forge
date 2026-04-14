# Eval: Swallowed exception in catch block

## Language: typescript

## Context
Catch block silently swallows the error without logging or re-throwing.

## Code Under Review

```typescript
// file: src/api-client.ts
async function fetchUser(id: string): Promise<User | null> {
  try {
    const response = await fetch(`/api/users/${id}`);
    return await response.json();
  } catch (e) {
    return null;
  }
}

async function deleteAccount(id: string): Promise<void> {
  try {
    await fetch(`/api/users/${id}`, { method: 'DELETE' });
  } catch (e) {
    // TODO: handle later
  }
}
```

## Expected Behavior
Reviewer should flag empty catch blocks that swallow errors silently.
