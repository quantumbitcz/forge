# AI Code Patterns Reference

Reference for AI-specific code generation bug patterns. Based on Stack Overflow research (January 2026, 10,847 PRs, 1,200 repos) showing AI-generated code has 1.7x more bugs than human-written code, with specific patterns in logic errors, performance anti-patterns, concurrency bugs, and security vulnerabilities.

## How to Use This Reference

- **Review agents** (fg-410, fg-411, fg-416): Use these patterns as additional detection heuristics during REVIEWING stage. AI-* categories supplement existing categories with root cause metadata.
- **Implementer** (fg-300): When fixing AI-* findings, apply the fix pattern described for each category.
- **Retrospective** (fg-700): Track recurring AI-* categories in `ai_quality_tracking` for SCOUT-AI PREEMPT promotion.

## Severity-to-Score Mapping

| Category | Default Severity | Score Impact |
|----------|-----------------|-------------|
| AI-LOGIC-NULL | WARNING | -5 |
| AI-LOGIC-BOUNDARY | WARNING | -5 |
| AI-LOGIC-CONDITION | WARNING | -5 |
| AI-LOGIC-TYPE-COERCE | INFO | -2 |
| AI-LOGIC-RETURN | WARNING | -5 |
| AI-LOGIC-STATE | WARNING | -5 |
| AI-LOGIC-ASYNC | INFO | -2 |
| AI-LOGIC-EDGE | INFO | -2 |
| AI-PERF-N-PLUS-ONE | WARNING | -5 |
| AI-PERF-EXCESSIVE-IO | WARNING | -5 |
| AI-PERF-MEMORY-LEAK | WARNING | -5 |
| AI-PERF-QUADRATIC | WARNING | -5 |
| AI-PERF-REDUNDANT-RENDER | INFO | -2 |
| AI-PERF-BLOCKING | WARNING | -5 |
| AI-PERF-BUNDLE | INFO | -2 |
| AI-CONCURRENCY-RACE | CRITICAL | -20 |
| AI-CONCURRENCY-DEADLOCK | CRITICAL | -20 |
| AI-CONCURRENCY-ATOMICITY | WARNING | -5 |
| AI-CONCURRENCY-STARVATION | INFO | -2 |
| AI-CONCURRENCY-LOST-UPDATE | WARNING | -5 |
| AI-SEC-INJECTION | CRITICAL | -20 |
| AI-SEC-HARDCODED-SECRET | CRITICAL | -20 |
| AI-SEC-INSECURE-DEFAULT | WARNING | -5 |
| AI-SEC-MISSING-AUTH | CRITICAL | -20 |
| AI-SEC-VERBOSE-ERROR | WARNING | -5 |
| AI-SEC-DESERIALIZATION | CRITICAL | -20 |

---

## AI-LOGIC-* (8 categories)

### AI-LOGIC-NULL

**Description:** Null/undefined dereference in chained access or after conditional checks.

**Why AI generates this:** AI trusts "happy path" training data and skips null guards for deeply nested properties. Models generate code that works for the example input but crashes on null/undefined.

**Detection:** L3 (reviewer heuristic). Severity: WARNING.

**Fix pattern:** Add optional chaining (`?.`), null checks, or early returns for null cases.

**Example:**
```typescript
// Before (AI-generated)
const name = user.profile.address.city;

// After (fixed)
const name = user?.profile?.address?.city ?? 'Unknown';
```

### AI-LOGIC-BOUNDARY

**Description:** Off-by-one errors in loops, array access, pagination.

**Why AI generates this:** AI often generates `i <= length` instead of `i < length` or starts counters at wrong index. Training data contains both correct and incorrect boundary patterns.

**Detection:** L3 (reviewer heuristic). Severity: WARNING.

**Fix pattern:** Verify loop bounds against collection length. Use range-based iteration where available.

**Example:**
```java
// Before (AI-generated)
for (int i = 0; i <= list.size(); i++) { list.get(i); }

// After (fixed)
for (int i = 0; i < list.size(); i++) { list.get(i); }
```

### AI-LOGIC-CONDITION

**Description:** Inverted or incomplete boolean conditions.

**Why AI generates this:** AI generates `if (x && y)` when `if (x || y)` was needed, or misses negation. Models struggle with complex boolean logic involving multiple conditions.

**Detection:** L3 (reviewer heuristic). Severity: WARNING.

**Fix pattern:** Review boolean expressions against requirements. Add truth table comments for complex conditions.

**Example:**
```python
# Before (AI-generated)
if user.is_admin and user.is_active:  # Should be OR for access check

# After (fixed)
if user.is_admin or user.is_active:
```

### AI-LOGIC-TYPE-COERCE

**Description:** Implicit type coercion bugs (e.g., `==` instead of `===`, string+number concatenation).

**Why AI generates this:** AI training on mixed-quality code normalizes loose comparisons. Models replicate patterns from older JavaScript/Python code.

**Detection:** L3 (reviewer heuristic). Severity: INFO.

**Fix pattern:** Use strict equality operators. Add explicit type conversions.

**Example:**
```javascript
// Before (AI-generated)
if (count == "0") { ... }

// After (fixed)
if (count === 0) { ... }
```

### AI-LOGIC-RETURN

**Description:** Return statement in finally block or early return swallowing errors.

**Why AI generates this:** AI copies try/catch/finally templates without understanding return semantics. The finally return overrides the try/catch return value.

**Detection:** L1 pattern (e.g., `TS-AI-LOGIC-001`). Severity: WARNING.

**Fix pattern:** Move the return outside the try/catch/finally or use a result variable.

**Example:**
```typescript
// Before (AI-generated)
try { return parse(data); } catch(e) { log(e); } finally { return null; }

// After (fixed)
let result = null;
try { result = parse(data); } catch(e) { log(e); }
return result;
```

### AI-LOGIC-STATE

**Description:** Stale state reference in closures, React hooks with missing deps, or mutation of shared state.

**Why AI generates this:** AI generates closures that capture variables by reference without considering lifecycle. Common in React useEffect with missing dependency arrays.

**Detection:** L3 (reviewer heuristic). Severity: WARNING.

**Fix pattern:** Add proper dependency arrays. Use ref for mutable values in closures. Avoid mutating shared state.

**Example:**
```typescript
// Before (AI-generated)
useEffect(() => { fetchData(userId); }, []); // Missing userId dep

// After (fixed)
useEffect(() => { fetchData(userId); }, [userId]);
```

### AI-LOGIC-ASYNC

**Description:** Fire-and-forget async operations -- mutation without await, unhandled promise rejections.

**Why AI generates this:** AI generates async code that looks synchronous, omitting await on database writes or API calls. Training data often shows simplified examples without error handling.

**Detection:** L1 pattern (e.g., `TS-AI-LOGIC-002`). Severity: INFO.

**Fix pattern:** Add `await` to all async mutation operations. Handle promise rejections.

**Example:**
```typescript
// Before (AI-generated)
async function handleOrder(order: Order) {
  orderRepo.save(order); // Missing await
  return { status: 'ok' };
}

// After (fixed)
async function handleOrder(order: Order) {
  await orderRepo.save(order);
  return { status: 'ok' };
}
```

### AI-LOGIC-EDGE

**Description:** Missing edge case handling (empty collections, zero-length strings, NaN, negative indices).

**Why AI generates this:** AI generates code for the common case and misses boundary inputs. Models optimize for the "happy path" from training examples.

**Detection:** L3 (reviewer heuristic). Severity: INFO.

**Fix pattern:** Add guards for empty inputs, null, zero, and negative values. Consider using assertion libraries.

**Example:**
```python
# Before (AI-generated)
def average(numbers):
    return sum(numbers) / len(numbers)

# After (fixed)
def average(numbers):
    if not numbers:
        return 0.0
    return sum(numbers) / len(numbers)
```

---

## AI-PERF-* (7 categories)

### AI-PERF-N-PLUS-ONE

**Description:** Database query inside a loop (for each item, fetch related data individually).

**Why AI generates this:** AI translates requirements literally into per-item queries instead of batch operations. Training data frequently shows simple single-item lookup examples.

**Detection:** L1 pattern (e.g., `KT-AI-PERF-001`, `JV-AI-PERF-001`). Severity: WARNING.

**Fix pattern:** Batch the operation with findAllById(), IN clause, or JOIN query.

**Example:**
```kotlin
// Before (AI-generated)
for (id in ids) { val user = userRepository.findById(id) }

// After (fixed)
val users = userRepository.findAllById(ids)
```

### AI-PERF-EXCESSIVE-IO

**Description:** Repeated file/network reads for the same data without caching.

**Why AI generates this:** AI generates fresh I/O calls per function invocation instead of reading once and passing the result. Each function is generated independently.

**Detection:** L3 (reviewer heuristic). Severity: WARNING.

**Fix pattern:** Read once and pass result. Use caching for repeated access. Consider dependency injection.

**Example:**
```python
# Before (AI-generated)
def get_setting(key):
    config = json.load(open('config.json'))  # Read every call
    return config[key]

# After (fixed)
_config = None
def get_setting(key):
    global _config
    if _config is None:
        _config = json.load(open('config.json'))
    return _config[key]
```

### AI-PERF-MEMORY-LEAK

**Description:** Unclosed resources (streams, connections, event listeners) or accumulating data in long-lived collections.

**Why AI generates this:** AI generates resource acquisition without cleanup in error paths. Models focus on the success path and miss resource lifecycle management.

**Detection:** L3 (reviewer heuristic). Severity: WARNING.

**Fix pattern:** Use try-with-resources, context managers, or RAII. Remove event listeners in cleanup. Bound collection sizes.

**Example:**
```java
// Before (AI-generated)
Connection conn = DriverManager.getConnection(url);
Statement stmt = conn.createStatement();

// After (fixed)
try (Connection conn = DriverManager.getConnection(url);
     Statement stmt = conn.createStatement()) { ... }
```

### AI-PERF-QUADRATIC

**Description:** Nested loops over the same collection or repeated linear searches where a map/set lookup would suffice.

**Why AI generates this:** AI generates nested iterations from training on small-scale examples where O(n^2) is not noticeable.

**Detection:** L3 (reviewer heuristic). Severity: WARNING.

**Fix pattern:** Pre-build a Map/Set for lookups. Use index-based access instead of linear search.

**Example:**
```typescript
// Before (AI-generated)
for (const order of orders) {
  const user = users.find(u => u.id === order.userId); // O(n*m)
}

// After (fixed)
const userMap = new Map(users.map(u => [u.id, u]));
for (const order of orders) {
  const user = userMap.get(order.userId); // O(n+m)
}
```

### AI-PERF-REDUNDANT-RENDER

**Description:** Inline object/array props in JSX causing unnecessary re-renders.

**Why AI generates this:** AI generates `style={{...}}` or `data={[...]}` directly in render return. Training data shows inline styles as the simplest approach.

**Detection:** L1 pattern (e.g., `TS-AI-PERF-002`). Severity: INFO.

**Fix pattern:** Extract to const outside component or use useMemo/CSS classes.

**Example:**
```tsx
// Before (AI-generated)
<Card style={{ margin: 10, padding: 5 }}>Content</Card>

// After (fixed)
const cardStyle = { margin: 10, padding: 5 };
<Card style={cardStyle}>Content</Card>
```

### AI-PERF-BLOCKING

**Description:** Synchronous blocking calls in async contexts (e.g., `fs.readFileSync` in Node.js server, `time.sleep` in Python async).

**Why AI generates this:** AI mixes sync/async patterns from different training examples. Models often choose the simpler synchronous API.

**Detection:** L1 pattern (e.g., `TS-AI-PERF-003`, `PY-AI-PERF-001`). Severity: WARNING.

**Fix pattern:** Use async alternatives (fs.promises, asyncio.sleep). Run blocking code in thread pool if necessary.

**Example:**
```typescript
// Before (AI-generated)
const data = fs.readFileSync('/etc/config.json', 'utf8');

// After (fixed)
const data = await fs.promises.readFile('/etc/config.json', 'utf8');
```

### AI-PERF-BUNDLE

**Description:** Full library imports instead of tree-shakeable per-function imports.

**Why AI generates this:** AI uses the simplest import form from documentation examples. Full imports are shorter and appear more frequently in training data.

**Detection:** L1 pattern (e.g., `TS-AI-PERF-001`). Severity: INFO.

**Fix pattern:** Use per-function imports or ESM tree-shakeable package.

**Example:**
```typescript
// Before (AI-generated)
import _ from 'lodash';
_.debounce(fn, 300);

// After (fixed)
import debounce from 'lodash/debounce';
debounce(fn, 300);
```

---

## AI-CONCURRENCY-* (5 categories)

### AI-CONCURRENCY-RACE

**Description:** Shared mutable state accessed from multiple threads/goroutines without synchronization.

**Why AI generates this:** AI generates class-level mutable collections or goroutine closures capturing loop variables. Training data rarely shows concurrent access patterns.

**Detection:** L1 pattern (e.g., `KT-AI-CONC-001`, `GO-AI-CONC-001`). Severity: CRITICAL.

**Fix pattern:** Use ConcurrentHashMap, synchronized wrappers, or immutable data structures. Pass loop variables as function parameters.

**Example:**
```go
// Before (AI-generated)
for _, item := range items {
    go func() { handle(item) }()  // item captured by reference
}

// After (fixed)
for _, item := range items {
    go func(v Item) { handle(v) }(item)
}
```

### AI-CONCURRENCY-DEADLOCK

**Description:** Lock acquisition in inconsistent order across code paths.

**Why AI generates this:** AI generates separate synchronized blocks that can deadlock when called in different sequences. Models lack global awareness of lock ordering.

**Detection:** L3 (reviewer heuristic). Severity: CRITICAL.

**Fix pattern:** Establish consistent lock ordering. Use tryLock with timeout. Consider lock-free alternatives.

**Example:**
```java
// Before (AI-generated)
// Thread 1: lock(A) then lock(B)
// Thread 2: lock(B) then lock(A) -- DEADLOCK

// After (fixed)
// Both threads: lock(A) then lock(B) -- consistent order
```

### AI-CONCURRENCY-ATOMICITY

**Description:** Non-atomic check-then-act sequences (e.g., `if (!exists) { create() }`).

**Why AI generates this:** AI generates two-step operations as separate calls without considering interleaving. TOCTOU (time-of-check-to-time-of-use) patterns are common.

**Detection:** L3 (reviewer heuristic). Severity: WARNING.

**Fix pattern:** Use atomic operations (putIfAbsent, compareAndSet). Use database constraints (UNIQUE). Use optimistic locking.

**Example:**
```java
// Before (AI-generated)
if (!map.containsKey(key)) { map.put(key, value); }

// After (fixed)
map.putIfAbsent(key, value);
```

### AI-CONCURRENCY-STARVATION

**Description:** Unbounded work queues, missing backpressure, or priority inversion.

**Why AI generates this:** AI generates producer-consumer patterns without capacity limits or fairness guarantees. Simple examples in training data rarely address backpressure.

**Detection:** L3 (reviewer heuristic). Severity: INFO.

**Fix pattern:** Use bounded queues. Add backpressure mechanisms. Configure fair locks.

**Example:**
```java
// Before (AI-generated)
BlockingQueue<Task> queue = new LinkedBlockingQueue<>(); // Unbounded

// After (fixed)
BlockingQueue<Task> queue = new LinkedBlockingQueue<>(1000); // Bounded
```

### AI-CONCURRENCY-LOST-UPDATE

**Description:** Read-modify-write without optimistic locking or CAS.

**Why AI generates this:** AI generates update patterns that silently overwrite concurrent changes. Models produce straightforward CRUD without considering concurrency.

**Detection:** L3 (reviewer heuristic). Severity: WARNING.

**Fix pattern:** Use @Version for JPA optimistic locking. Use CAS for atomic updates. Use database-level locks for critical sections.

**Example:**
```kotlin
// Before (AI-generated)
val account = repo.findById(id)
account.balance -= amount
repo.save(account) // Lost update if concurrent

// After (fixed)
@Version var version: Long = 0  // Add to entity
// JPA will throw OptimisticLockException on concurrent modification
```

---

## AI-SEC-* (6 categories)

### AI-SEC-INJECTION

**Description:** SQL/NoSQL/command injection via string interpolation (f-strings, template literals, .format()).

**Why AI generates this:** AI generates parameterized-looking code that actually concatenates user input. Training data contains both safe and unsafe query patterns.

**Detection:** L1 pattern (e.g., `PY-AI-SEC-001`). Severity: CRITICAL.

**Fix pattern:** Always use parameterized queries. Never interpolate user input into SQL.

**Example:**
```python
# Before (AI-generated)
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")

# After (fixed)
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
```

### AI-SEC-HARDCODED-SECRET

**Description:** Hardcoded JWT tokens, API keys, passwords in source code.

**Why AI generates this:** AI embeds sample credentials from training data that may be valid or serve as templates for real secrets. Models copy example tokens verbatim.

**Detection:** L1 pattern (universal `{LANG}-AI-SEC-001`). Severity: CRITICAL.

**Fix pattern:** Remove hardcoded secrets. Load from environment variables or secret managers.

**Example:**
```typescript
// Before (AI-generated)
const token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0";

// After (fixed)
const token = process.env.JWT_TOKEN;
```

### AI-SEC-INSECURE-DEFAULT

**Description:** Permissive CORS (`origin: "*"`), disabled CSRF, debug mode in production configs.

**Why AI generates this:** AI copies tutorial defaults that prioritize ease of setup over security. Documentation examples frequently use permissive settings.

**Detection:** L1 pattern (e.g., `{LANG}-AI-SEC-002`). Severity: WARNING.

**Fix pattern:** Restrict CORS to specific origins. Enable CSRF. Disable debug mode in production.

**Example:**
```typescript
// Before (AI-generated)
app.use(cors({ origin: "*" }));

// After (fixed)
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(',') }));
```

### AI-SEC-MISSING-AUTH

**Description:** Missing authentication/authorization checks on endpoints or operations.

**Why AI generates this:** AI generates functional endpoints without access control when the requirement does not explicitly mention security. Models focus on business logic.

**Detection:** L3 (reviewer heuristic). Severity: CRITICAL.

**Fix pattern:** Add authentication middleware. Verify authorization for each operation. Apply principle of least privilege.

**Example:**
```typescript
// Before (AI-generated)
app.delete('/api/users/:id', async (req, res) => { ... });

// After (fixed)
app.delete('/api/users/:id', authenticate, authorize('admin'), async (req, res) => { ... });
```

### AI-SEC-VERBOSE-ERROR

**Description:** Full error objects, stack traces, or internal details sent in API responses.

**Why AI generates this:** AI generates catch blocks that return the raw error for debugging convenience. Training data shows error handling focused on development, not production.

**Detection:** L1 pattern (e.g., `{LANG}-AI-SEC-003`). Severity: WARNING.

**Fix pattern:** Return generic error messages to clients. Log full details server-side.

**Example:**
```typescript
// Before (AI-generated)
catch(err) { res.json({ error: err }); }

// After (fixed)
catch(err) {
  logger.error('Request failed', err);
  res.status(500).json({ error: 'Internal server error' });
}
```

### AI-SEC-DESERIALIZATION

**Description:** Unsafe deserialization of untrusted input (yaml.load, marshal, Java ObjectInputStream).

**Why AI generates this:** AI uses the simplest deserialization call without considering trust boundaries. Safe alternatives require more code.

**Detection:** L1 pattern (e.g., `PY-AI-SEC-002`). Severity: CRITICAL.

**Fix pattern:** Use safe alternatives (yaml.safe_load, JSON). Validate input before deserialization. Avoid deserializing untrusted data.

**Example:**
```python
# Before (AI-generated)
config = yaml.load(user_input)

# After (fixed)
config = yaml.safe_load(user_input)
```

---

## Configuration

```yaml
ai_quality:
  enabled: true              # Master toggle (default: true)
  categories:                # Which AI-* prefixes to enable (default: all 4)
    - AI-LOGIC
    - AI-PERF
    - AI-SEC
    - AI-CONCURRENCY
  l1_patterns: true          # Enable L1 regex patterns (default: true)
  scout_learning: true       # Enable SCOUT-AI PREEMPT promotion (default: true)
  severity_overrides:        # Override default severity for specific categories
    AI-LOGIC-ASYNC: WARNING  # Promote from INFO to WARNING
```

All `ai_quality.*` config values have safe defaults. Invalid config produces WARNING + fallback, not PREFLIGHT failure.
