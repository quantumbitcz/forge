# Async Patterns (Python)

## asyncio-gather

**Instead of:**
```python
async def fetch_all(ids: list[str]) -> list[User]:
    results = []
    for uid in ids:
        results.append(await fetch_user(uid))
    return results
```

**Do this:**
```python
async def fetch_all(ids: list[str]) -> list[User]:
    return await asyncio.gather(*(fetch_user(uid) for uid in ids))
```

**Why:** Sequential awaits in a loop serialize independent I/O; `gather` runs them concurrently on the event loop.

## task-groups

**Instead of:**
```python
async def ingest(urls: list[str]) -> None:
    tasks = [asyncio.create_task(download(u)) for u in urls]
    await asyncio.gather(*tasks)
```

**Do this:**
```python
async def ingest(urls: list[str]) -> None:
    async with asyncio.TaskGroup() as tg:
        for url in urls:
            tg.create_task(download(url))
```

**Why:** `TaskGroup` (3.11+) cancels all sibling tasks on first failure and raises an `ExceptionGroup`, preventing fire-and-forget leaks.

## async-context-manager

**Instead of:**
```python
async def get_connection():
    conn = await pool.acquire()
    return conn
    # caller must remember to release
```

**Do this:**
```python
@asynccontextmanager
async def get_connection():
    conn = await pool.acquire()
    try:
        yield conn
    finally:
        await pool.release(conn)
```

**Why:** An async context manager ties resource cleanup to scope exit, making it impossible to forget releasing the connection.

## avoid-blocking

**Instead of:**
```python
async def read_config() -> dict:
    with open("config.json") as f:
        return json.load(f)
```

**Do this:**
```python
async def read_config() -> dict:
    content = await asyncio.to_thread(Path("config.json").read_text)
    return json.loads(content)
```

**Why:** Synchronous file I/O blocks the event loop, stalling all other coroutines until the read completes.
