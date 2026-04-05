# Testing Patterns (PHP)

## data-providers

**Instead of:**
```php
public function testValidatesEmail(): void {
    $this->assertTrue(Validator::isEmail('user@example.com'));
    $this->assertFalse(Validator::isEmail('not-an-email'));
    $this->assertFalse(Validator::isEmail(''));
    $this->assertTrue(Validator::isEmail('a@b.co'));
}
```

**Do this:**
```php
#[DataProvider('emailProvider')]
public function testValidatesEmail(string $input, bool $expected): void {
    $this->assertSame($expected, Validator::isEmail($input));
}

public static function emailProvider(): array {
    return [
        'valid standard email' => ['user@example.com', true],
        'missing @ symbol'     => ['not-an-email', false],
        'empty string'         => ['', false],
        'minimal valid email'  => ['a@b.co', true],
    ];
}
```

**Why:** Data providers separate test logic from test data. Each case runs independently with a descriptive label, so failures pinpoint exactly which input broke.

## mock-interfaces

**Instead of:**
```php
public function testNotifiesUser(): void {
    // Testing with real email sender
    $service = new OrderService(new SmtpMailer());
    $service->complete($orderId);
    // No way to verify email was sent
}
```

**Do this:**
```php
public function testNotifiesUserOnCompletion(): void {
    $mailer = $this->createMock(MailerInterface::class);
    $mailer->expects($this->once())
        ->method('send')
        ->with(
            $this->equalTo('user@example.com'),
            $this->stringContains('Order completed'),
        );

    $service = new OrderService($mailer);
    $service->complete($this->orderId);
}
```

**Why:** PHPUnit mocks verify interaction contracts between components. `expects($this->once())` asserts the method was called exactly once with the expected arguments, without side effects.
