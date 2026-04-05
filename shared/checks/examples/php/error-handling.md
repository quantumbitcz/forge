# Error Handling Patterns (PHP)

## typed-exceptions

**Instead of:**
```php
function getUser(int $id): array {
    $user = $this->db->find('users', $id);
    if (!$user) {
        throw new \Exception("User not found");
    }
    return $user;
}
```

**Do this:**
```php
function getUser(int $id): User {
    $user = $this->repository->find($id);
    if ($user === null) {
        throw new UserNotFoundException($id);
    }
    return $user;
}
```

**Why:** Domain-specific exceptions let callers catch precisely the failure they can handle. Catching `\Exception` is a catch-all that masks unrelated bugs.

## nullable-return-types

**Instead of:**
```php
function findDiscount(string $code) {
    $discount = $this->repo->findByCode($code);
    if ($discount) {
        return $discount;
    }
    return false;  // Mixed return types
}
```

**Do this:**
```php
function findDiscount(string $code): ?Discount {
    return $this->repo->findByCode($code);
}
```

**Why:** Nullable return types (`?Type`) replace mixed `false`/`null`/object returns with a single, typed contract. Callers use `=== null` instead of loose boolean checks.

## try-finally-cleanup

**Instead of:**
```php
function processFile(string $path): void {
    $handle = fopen($path, 'r');
    $data = fread($handle, filesize($path));
    process($data);
    fclose($handle);  // Skipped if process() throws
}
```

**Do this:**
```php
function processFile(string $path): void {
    $handle = fopen($path, 'r');
    if ($handle === false) {
        throw new FileAccessException("Cannot open: $path");
    }
    try {
        $data = fread($handle, filesize($path));
        process($data);
    } finally {
        fclose($handle);
    }
}
```

**Why:** `finally` guarantees resource cleanup regardless of exceptions. PHP lacks destructors for stack-allocated resources, so explicit `finally` blocks are the idiomatic RAII equivalent.
