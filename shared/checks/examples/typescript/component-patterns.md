# Component Patterns (TypeScript)

## composition-over-inheritance

**Instead of:**
```typescript
function SettingsPage() {
  return (
    <PageLayout>
      <h1>Settings</h1>
      <SettingsForm />
      <DangerZone />
    </PageLayout>
  );
}
```

**Do this:**
```typescript
function SettingsPage() {
  return (
    <PageLayout
      header={<PageHeader title="Settings" />}
      footer={<DangerZone />}
    >
      <SettingsForm />
    </PageLayout>
  );
}
```

**Why:** Slot-based composition decouples layout from content, making `PageLayout` reusable without internal knowledge of its children.

## custom-hooks

**Instead of:**
```typescript
function UserProfile({ id }: { id: string }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    setLoading(true);
    fetchUser(id).then(setUser).finally(() => setLoading(false));
  }, [id]);
  if (loading) return <Spinner />;
  return <ProfileCard user={user!} />;
}
```

**Do this:**
```typescript
function useUser(id: string) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    setLoading(true);
    fetchUser(id).then(setUser).finally(() => setLoading(false));
  }, [id]);
  return { user, loading } as const;
}

function UserProfile({ id }: { id: string }) {
  const { user, loading } = useUser(id);
  if (loading) return <Spinner />;
  return <ProfileCard user={user!} />;
}
```

**Why:** Extracting data-fetching into a hook separates stateful logic from presentation, enabling reuse and independent testing.

## controlled-components

**Instead of:**
```typescript
function SearchInput() {
  const ref = useRef<HTMLInputElement>(null);
  const handleSubmit = () => {
    doSearch(ref.current!.value);
  };
  return <input ref={ref} />;
}
```

**Do this:**
```typescript
function SearchInput({ onSearch }: { onSearch: (q: string) => void }) {
  const [query, setQuery] = useState("");
  return (
    <input
      value={query}
      onChange={(e) => setQuery(e.target.value)}
      onKeyDown={(e) => e.key === "Enter" && onSearch(query)}
    />
  );
}
```

**Why:** Controlled inputs keep React as the single source of truth, making state predictable and enabling features like debounce or validation.

## render-props-vs-hooks

**Instead of:**
```typescript
<MouseTracker
  render={({ x, y }) => (
    <Cursor x={x} y={y} />
  )}
/>
```

**Do this:**
```typescript
function Cursor() {
  const { x, y } = useMousePosition();
  return <div style={{ transform: `translate(${x}px, ${y}px)` }} />;
}
```

**Why:** Custom hooks replaced render props for sharing stateful logic, removing the nesting and improving readability.
