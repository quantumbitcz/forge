# Testing Patterns (Python)

## pytest-fixtures

**Instead of:**
```python
def test_process_order():
    db = Database(":memory:")
    db.connect()
    user = db.create_user("Ada")
    order = process_order(db, user, item="widget")
    assert order.status == "confirmed"
    db.close()
```

**Do this:**
```python
@pytest.fixture
def db():
    conn = Database(":memory:")
    conn.connect()
    yield conn
    conn.close()

def test_process_order(db):
    user = db.create_user("Ada")
    order = process_order(db, user, item="widget")
    assert order.status == "confirmed"
```

**Why:** Fixtures isolate setup and teardown, ensuring cleanup runs even when the test fails and enabling reuse across tests.

## parametrize

**Instead of:**
```python
def test_validate_email_valid():
    assert validate_email("a@b.com") is True

def test_validate_email_no_at():
    assert validate_email("ab.com") is False

def test_validate_email_empty():
    assert validate_email("") is False
```

**Do this:**
```python
@pytest.mark.parametrize("email, expected", [
    ("a@b.com", True),
    ("ab.com", False),
    ("", False),
    ("@missing-local.com", False),
])
def test_validate_email(email: str, expected: bool):
    assert validate_email(email) is expected
```

**Why:** `parametrize` tests multiple inputs with one function, making it trivial to add cases and clearly showing which input failed.

## conftest-patterns

**Instead of:**
```python
# tests/test_api.py
@pytest.fixture
def client():
    app = create_app(testing=True)
    return app.test_client()

# tests/test_auth.py  (duplicated)
@pytest.fixture
def client():
    app = create_app(testing=True)
    return app.test_client()
```

**Do this:**
```python
# tests/conftest.py
@pytest.fixture
def app():
    return create_app(testing=True)

@pytest.fixture
def client(app):
    return app.test_client()
```

**Why:** `conftest.py` shares fixtures across an entire test directory without imports, eliminating duplication and drift.

## assertion-messages

**Instead of:**
```python
def test_balance_after_withdrawal():
    account = Account(balance=100)
    account.withdraw(30)
    assert account.balance == 70
```

**Do this:**
```python
def test_balance_after_withdrawal():
    account = Account(balance=100)
    account.withdraw(30)
    assert account.balance == 70, (
        f"Expected 70 after withdrawing 30 from 100, got {account.balance}"
    )
```

**Why:** A custom message explains the business expectation in CI logs, saving the reader from reverse-engineering the assertion.
