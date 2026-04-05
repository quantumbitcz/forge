# Readability Patterns (PHP)

## match-expression

**Instead of:**
```php
function getStatusLabel(string $status): string {
    switch ($status) {
        case 'pending':
            return 'Waiting';
        case 'active':
            return 'Active';
        case 'cancelled':
            return 'Cancelled';
        default:
            throw new \InvalidArgumentException("Unknown status: $status");
    }
}
```

**Do this:**
```php
function getStatusLabel(string $status): string {
    return match ($status) {
        'pending'   => 'Waiting',
        'active'    => 'Active',
        'cancelled' => 'Cancelled',
        default     => throw new \InvalidArgumentException("Unknown status: $status"),
    };
}
```

**Why:** `match` (PHP 8.0+) uses strict comparison, is expression-based, and throws `UnhandledMatchError` when no arm matches — eliminating fall-through bugs inherent to `switch`.

## named-arguments

**Instead of:**
```php
$user = new User('Alice', 'alice@example.com', true, false, 25);
```

**Do this:**
```php
$user = new User(
    name: 'Alice',
    email: 'alice@example.com',
    isActive: true,
    isAdmin: false,
    age: 25,
);
```

**Why:** Named arguments (PHP 8.0+) make constructor calls self-documenting. Boolean and numeric positional arguments are unreadable without jumping to the function signature.

## readonly-properties

**Instead of:**
```php
class Money {
    private int $amount;
    private string $currency;

    public function __construct(int $amount, string $currency) {
        $this->amount = $amount;
        $this->currency = $currency;
    }

    public function getAmount(): int { return $this->amount; }
    public function getCurrency(): string { return $this->currency; }
}
```

**Do this:**
```php
class Money {
    public function __construct(
        public readonly int $amount,
        public readonly string $currency,
    ) {}
}
```

**Why:** Constructor promotion with `readonly` (PHP 8.1+) eliminates boilerplate property declarations and getters. Immutability is enforced at the language level.
