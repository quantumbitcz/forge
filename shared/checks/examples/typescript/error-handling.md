# Error Handling Patterns (TypeScript)

## custom-error-classes

**Instead of:**
```typescript
throw new Error("User not found");
```

**Do this:**
```typescript
class NotFoundError extends Error {
  constructor(public readonly entity: string, public readonly id: string) {
    super(`${entity} ${id} not found`);
    this.name = "NotFoundError";
  }
}

throw new NotFoundError("User", userId);
```

**Why:** Typed errors let callers distinguish failure modes with `instanceof` instead of parsing message strings.

## result-pattern

**Instead of:**
```typescript
function parseConfig(raw: string): Config {
  if (!raw) throw new Error("empty config");
  return JSON.parse(raw) as Config;
}
```

**Do this:**
```typescript
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

function parseConfig(raw: string): Result<Config> {
  if (!raw) return { ok: false, error: new Error("empty config") };
  return { ok: true, value: JSON.parse(raw) as Config };
}
```

**Why:** Result types make the failure path explicit in the return type, forcing callers to handle both cases.

## error-boundary

**Instead of:**
```typescript
function Dashboard() {
  const data = useSuspenseQuery(dashboardQuery);
  return <DashboardView data={data} />;
}
```

**Do this:**
```typescript
function Dashboard() {
  return (
    <ErrorBoundary fallback={<DashboardError />}>
      <Suspense fallback={<DashboardSkeleton />}>
        <DashboardContent />
      </Suspense>
    </ErrorBoundary>
  );
}
```

**Why:** Without an error boundary, a single failed query crashes the entire component tree above it.

## exhaustive-switch

**Instead of:**
```typescript
function statusLabel(s: Status): string {
  switch (s) {
    case "active": return "Active";
    case "inactive": return "Inactive";
    default: return "Unknown";
  }
}
```

**Do this:**
```typescript
function statusLabel(s: Status): string {
  switch (s) {
    case "active": return "Active";
    case "inactive": return "Inactive";
    case "pending": return "Pending";
    default: {
      const _exhaustive: never = s;
      throw new Error(`Unhandled status: ${_exhaustive}`);
    }
  }
}
```

**Why:** The `never` assignment causes a compile error when a new union member is added but not handled.
