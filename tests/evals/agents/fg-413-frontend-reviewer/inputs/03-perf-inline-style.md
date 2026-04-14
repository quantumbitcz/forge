# Eval: Object allocations in JSX causing unnecessary re-renders

## Language: typescript

## Context
Component creates new objects on every render in JSX props, preventing React.memo optimization.

## Code Under Review

```typescript
// file: src/components/UserList.tsx
import React from 'react';

interface User { id: string; name: string; }

export function UserList({ users }: { users: User[] }) {
  return (
    <ul>
      {users.map(user => (
        <li
          key={user.id}
          style={{ color: 'blue', fontSize: 14, padding: 8 }}
          onClick={() => console.log(user.id)}
        >
          {user.name}
        </li>
      ))}
    </ul>
  );
}
```

## Expected Behavior
Reviewer should flag inline object/function allocations in render path causing potential re-render issues.
