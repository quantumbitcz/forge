# Eval: Memory leak from uncleared intervals and listeners

## Language: typescript

## Context
Component sets up intervals and event listeners without cleanup.

## Code Under Review

```typescript
// file: src/services/poller.ts
class DataPoller {
  private cache: Map<string, any> = new Map();

  start(): void {
    setInterval(async () => {
      const data = await fetchData();
      for (const item of data) {
        this.cache.set(item.id, item);
      }
    }, 1000);

    process.on('message', (msg: any) => {
      this.cache.set(msg.id, msg);
    });
  }
}
```

## Expected Behavior
Reviewer should flag the growing unbounded cache and uncleared interval/listener as memory leak risks.
