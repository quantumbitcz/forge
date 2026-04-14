# Eval: Form inputs without associated labels

## Language: typescript

## Context
Form renders input elements without proper labels or aria-label attributes.

## Code Under Review

```typescript
// file: src/components/LoginForm.tsx
import React from 'react';

export function LoginForm() {
  return (
    <form>
      <input type="email" placeholder="Email" />
      <input type="password" placeholder="Password" />
      <button type="submit">Log in</button>
    </form>
  );
}
```

## Expected Behavior
Reviewer should flag input elements without associated label elements or aria-label attributes.
