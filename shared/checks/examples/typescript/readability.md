# Readability Patterns (TypeScript)

## nesting

**Instead of:**
```typescript
function process(items: Item[]) {
  if (items.length > 0) {
    for (const item of items) {
      if (item.isActive) {
        if (item.value > threshold) {
          results.push(transform(item));
        }
      }
    }
  }
  return results;
}
```

**Do this:**
```typescript
function process(items: Item[]) {
  return items
    .filter((item) => item.isActive)
    .filter((item) => item.value > threshold)
    .map(transform);
}
```

**Why:** Chained array methods flatten nested conditionals into a linear, declarative pipeline that reads top to bottom.

## naming

**Instead of:**
```typescript
const d = new Date();
const fn = (x: number) => x * TAX;
const temp = users.filter((u) => u.a);
```

**Do this:**
```typescript
const now = new Date();
const applyTax = (price: number) => price * TAX_RATE;
const activeUsers = users.filter((user) => user.isActive);
```

**Why:** Descriptive names eliminate the need for comments and let readers understand intent without jumping to definitions.

## guard-clauses

**Instead of:**
```typescript
function getDiscount(user: User): number {
  if (user.isVerified) {
    if (user.subscription === "premium") {
      return 0.2;
    } else {
      return 0.1;
    }
  } else {
    return 0;
  }
}
```

**Do this:**
```typescript
function getDiscount(user: User): number {
  if (!user.isVerified) return 0;
  if (user.subscription === "premium") return 0.2;
  return 0.1;
}
```

**Why:** Guard clauses handle edge cases first and exit early, keeping the main logic at the top indentation level.

## type-narrowing

**Instead of:**
```typescript
function render(input: string | string[]) {
  const items = typeof input === "string" ? [input] : input;
  return items.map((i) => `<li>${i}</li>`).join("");
}
```

**Do this:**
```typescript
function render(input: string | string[]): string {
  if (typeof input === "string") {
    return `<li>${input}</li>`;
  }
  return input.map((item) => `<li>${item}</li>`).join("");
}
```

**Why:** Explicit narrowing with control flow lets TypeScript infer the exact type in each branch, avoiding manual coercion.
