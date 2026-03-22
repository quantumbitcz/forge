# Error Handling Patterns (Python)

## specific-exceptions

**Instead of:**
```python
try:
    user = fetch_user(user_id)
except Exception:
    return None
```

**Do this:**
```python
try:
    user = fetch_user(user_id)
except UserNotFoundError:
    logger.warning("User %s not found", user_id)
    return None
```

**Why:** Catching bare `Exception` swallows programming errors like `TypeError` and `KeyError`, hiding bugs behind silent failures.

## context-managers

**Instead of:**
```python
f = open("data.json")
data = json.load(f)
f.close()
```

**Do this:**
```python
with open("data.json") as f:
    data = json.load(f)
```

**Why:** The `with` statement guarantees the file is closed even when `json.load` raises, preventing resource leaks.

## custom-exceptions

**Instead of:**
```python
raise ValueError("insufficient funds")
```

**Do this:**
```python
class InsufficientFundsError(Exception):
    def __init__(self, balance: Decimal, amount: Decimal) -> None:
        self.balance = balance
        self.amount = amount
        super().__init__(f"Balance {balance} < requested {amount}")
```

**Why:** Domain-specific exceptions carry structured data and let callers handle business errors separately from validation errors.

## exception-chaining

**Instead of:**
```python
try:
    result = external_api.call(payload)
except requests.HTTPError:
    raise ServiceError("API call failed")
```

**Do this:**
```python
try:
    result = external_api.call(payload)
except requests.HTTPError as exc:
    raise ServiceError("API call failed") from exc
```

**Why:** `from exc` preserves the original traceback in `__cause__`, so debugging shows the full chain instead of just the wrapper.
