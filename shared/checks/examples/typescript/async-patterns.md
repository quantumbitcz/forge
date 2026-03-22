# Async Patterns (TypeScript)

## async-await-error-handling

**Instead of:**
```typescript
async function fetchUser(id: string) {
  const res = await fetch(`/api/users/${id}`);
  return res.json();
}
```

**Do this:**
```typescript
async function fetchUser(id: string): Promise<User> {
  const res = await fetch(`/api/users/${id}`);
  if (!res.ok) {
    throw new ApiError(`Failed to fetch user ${id}`, res.status);
  }
  return res.json() as Promise<User>;
}
```

**Why:** Unchecked responses silently swallow HTTP errors like 404 or 500, producing undefined data downstream.

## promise-all

**Instead of:**
```typescript
const user = await fetchUser(id);
const posts = await fetchPosts(id);
const comments = await fetchComments(id);
```

**Do this:**
```typescript
const [user, posts, comments] = await Promise.all([
  fetchUser(id),
  fetchPosts(id),
  fetchComments(id),
]);
```

**Why:** Sequential awaits on independent requests multiply latency; `Promise.all` runs them concurrently.

## avoid-floating-promises

**Instead of:**
```typescript
function handleClick() {
  saveData(formValues);
}
```

**Do this:**
```typescript
function handleClick() {
  saveData(formValues).catch((err) => {
    reportError(err);
  });
}
```

**Why:** A floating promise swallows rejections silently, making failures invisible to users and error trackers.

## abort-controller

**Instead of:**
```typescript
useEffect(() => {
  fetch(`/api/items/${id}`).then((r) => r.json()).then(setItems);
}, [id]);
```

**Do this:**
```typescript
useEffect(() => {
  const controller = new AbortController();
  fetch(`/api/items/${id}`, { signal: controller.signal })
    .then((r) => r.json())
    .then(setItems)
    .catch((e) => { if (e.name !== "AbortError") throw e; });
  return () => controller.abort();
}, [id]);
```

**Why:** Without cancellation, stale responses from earlier renders can overwrite newer state.
