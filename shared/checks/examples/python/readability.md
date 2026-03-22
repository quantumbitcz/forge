# Readability Patterns (Python)

## nesting

**Instead of:**
```python
def process(items: list[Item]) -> list[Result]:
    results = []
    for item in items:
        if item.is_active:
            if item.value > threshold:
                results.append(transform(item))
    return results
```

**Do this:**
```python
def process(items: list[Item]) -> list[Result]:
    return [
        transform(item)
        for item in items
        if item.is_active and item.value > threshold
    ]
```

**Why:** List comprehensions with inline filters flatten nested loops into a single declarative expression.

## naming

**Instead of:**
```python
d = {}
for x in lst:
    k = x.split(":")[0]
    d[k] = d.get(k, 0) + 1
```

**Do this:**
```python
frequency: dict[str, int] = {}
for entry in log_lines:
    level = entry.split(":")[0]
    frequency[level] = frequency.get(level, 0) + 1
```

**Why:** Names that reflect the domain (`frequency`, `level`) let the reader understand intent without tracing the data flow.

## guard-clauses

**Instead of:**
```python
def send_notification(user: User, message: str) -> None:
    if user.is_active:
        if user.email_verified:
            if not user.is_muted:
                mailer.send(user.email, message)
```

**Do this:**
```python
def send_notification(user: User, message: str) -> None:
    if not user.is_active:
        return
    if not user.email_verified:
        return
    if user.is_muted:
        return
    mailer.send(user.email, message)
```

**Why:** Guard clauses eliminate nesting by returning early for invalid states, keeping the happy path left-aligned.

## walrus-operator

**Instead of:**
```python
match = pattern.search(line)
if match:
    process(match.group(1))
```

**Do this:**
```python
if match := pattern.search(line):
    process(match.group(1))
```

**Why:** The walrus operator (`:=`) assigns and tests in one expression, removing the redundant temporary variable above the conditional.
