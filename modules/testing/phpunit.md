# PHPUnit Best Practices

> Support tier: contract-verified

## Overview
PHPUnit is the standard testing framework for PHP. Use it for unit and integration tests in PHP applications (Laravel, Symfony, WordPress). PHPUnit excels at data providers, test doubles, and integration with CI/CD. Avoid it for browser E2E testing (use Playwright/Cypress) or load testing (use k6).

## Conventions

### Test Structure
```php
class UserServiceTest extends TestCase
{
    private UserService $service;
    private UserRepository&MockObject $repository;

    protected function setUp(): void
    {
        $this->repository = $this->createMock(UserRepository::class);
        $this->service = new UserService($this->repository);
    }

    public function testCreateUserWithValidData(): void
    {
        $this->repository->expects($this->once())
            ->method('save')
            ->willReturn(new User(id: 1, email: 'alice@example.com'));

        $user = $this->service->createUser('alice@example.com', 'Alice');

        $this->assertSame('alice@example.com', $user->email);
        $this->assertSame(1, $user->id);
    }

    #[DataProvider('invalidEmailProvider')]
    public function testCreateUserRejectsInvalidEmail(string $email): void
    {
        $this->expectException(ValidationException::class);
        $this->service->createUser($email, 'Alice');
    }

    public static function invalidEmailProvider(): array
    {
        return [
            'empty' => [''],
            'no at sign' => ['alice.example.com'],
            'spaces' => ['alice @example.com'],
        ];
    }
}
```

## Configuration

```xml
<!-- phpunit.xml -->
<phpunit bootstrap="vendor/autoload.php" colors="true" stopOnFailure="false">
    <testsuites>
        <testsuite name="Unit">
            <directory>tests/Unit</directory>
        </testsuite>
        <testsuite name="Integration">
            <directory>tests/Integration</directory>
        </testsuite>
    </testsuites>
    <coverage>
        <include>
            <directory>src</directory>
        </include>
    </coverage>
</phpunit>
```

## Dos
- Use `#[DataProvider]` attributes (PHPUnit 10+) for parameterized tests — they're cleaner than loops.
- Use `createMock()` and `createStub()` for test doubles — type-safe and IDE-friendly.
- Use `setUp()` for shared test configuration — it runs before each test method.
- Use descriptive test names: `testCreateUserWithValidData` over `testCreate`.
- Use `assertSame` (strict) over `assertEquals` (loose) — it catches type coercion bugs.
- Use `expectException()` for testing error paths — it's cleaner than try/catch in tests.
- Separate unit tests (`tests/Unit/`) from integration tests (`tests/Integration/`).

## Don'ts
- Don't use `@test` annotations — use `test` method prefix for discoverability.
- Don't use `$this->assertTrue($a === $b)` — use `$this->assertSame($a, $b)` for clear failure messages.
- Don't share state between test methods — each method should be independent.
- Don't test framework behavior (Laravel validation rules, Symfony serializer) — test your business logic.
- Don't mock what you don't own — wrap third-party services in your own interface and mock that.
- Don't use database in unit tests — use mocks; save real DB for integration tests.
- Don't ignore PHPUnit deprecation warnings — upgrade test code before forced migration.
