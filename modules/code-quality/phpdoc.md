# phpdoc

## Overview

phpDocumentor generates API documentation from PHP source files using PHPDoc comment blocks (`/** */`). Install via Composer or download as a PHAR. Configure through `phpdoc.xml` or `phpdoc.dist.xml`. PHPDoc tags include `@param`, `@return`, `@throws`, `@property`, `@method`, `@var`, `@author`, and `@since`. phpDocumentor 3 supports modern PHP features including union types, named arguments, and attributes.

## Architecture Patterns

### Installation & Setup

```bash
# Composer (recommended for project-local install)
composer require --dev phpdocumentor/phpdocumentor

# PHAR (portable, no Composer required)
wget https://phpdoc.org/phpDocumentor.phar
chmod +x phpDocumentor.phar
mv phpDocumentor.phar /usr/local/bin/phpdoc

# Run
vendor/bin/phpdoc
# or
phpdoc
```

**`phpdoc.xml` configuration:**
```xml
<?xml version="1.0" encoding="UTF-8" ?>
<phpdocumentor
    configVersion="3"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns="https://www.phpdoc.org"
    xsi:noNamespaceSchemaLocation="https://docs.phpdoc.org/latest/phpdoc.xsd"
>
    <title>My Application API</title>

    <paths>
        <docs>docs/api</docs>
        <cache>.phpdoc/cache</cache>
    </paths>

    <version number="1.0.0">
        <api>
            <source dsn=".">
                <path>src</path>
            </source>
            <ignore hidden="true">
                <path>src/Internal</path>
                <path>**/*.test.php</path>
            </ignore>
            <extensions>
                <extension>php</extension>
            </extensions>
            <visibility>public</visibility>
            <default-package-name>MyApp</default-package-name>
        </api>
        <guide>
            <source dsn=".">
                <path>docs/guides</path>
            </source>
        </guide>
    </version>

    <template name="default" />
</phpdocumentor>
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing class docblock | Public class without `/** */` block | WARNING |
| Missing `@param` | Public method parameter without `@param` | WARNING |
| Missing `@return` | Non-void public method without `@return` | WARNING |
| Missing `@throws` | Method throwing an exception without `@throws` | WARNING |
| Type mismatch | `@param string` on a typed `int` parameter | WARNING |

### Configuration Patterns

**Class and method documentation:**
```php
<?php

namespace MyApp\Users;

/**
 * Manages user lifecycle operations.
 *
 * Coordinates creation, retrieval, update, and deletion of user records.
 * All operations are transactional — partial failures roll back automatically.
 *
 * @package MyApp\Users
 * @since 1.0
 */
class UserService
{
    /**
     * Creates a new user account.
     *
     * The generated password is hashed using bcrypt with cost 12.
     * An activation email is dispatched asynchronously after creation.
     *
     * @param string $email    The user's email address (must be unique).
     * @param string $password The plain-text password (min 8 chars, not stored).
     * @param array<string, mixed> $meta Optional metadata (e.g. ['role' => 'admin']).
     *
     * @return User The newly created and persisted user.
     *
     * @throws DuplicateEmailException If a user with the same email already exists.
     * @throws ValidationException     If email format is invalid or password is too short.
     *
     * @example
     * ```php
     * $user = $service->create('alice@example.com', 'SecurePass1!');
     * echo $user->getId(); // 42
     * ```
     */
    public function create(string $email, string $password, array $meta = []): User
    {
```

**Property documentation:**
```php
/**
 * The maximum number of login attempts before account lockout.
 *
 * @var int
 */
private int $maxAttempts = 5;
```

**Interface documentation:**
```php
/**
 * Contract for classes that can serialize objects to string representations.
 *
 * @template T
 */
interface Serializable
{
    /**
     * Serializes the given object.
     *
     * @param T $object The object to serialize.
     * @return string The serialized representation.
     * @throws SerializationException If the object cannot be represented.
     */
    public function serialize(mixed $object): string;
}
```

**PHPDoc for magic methods:**
```php
/**
 * @method static User findById(int $id)
 * @method static User[] findByRole(string $role)
 * @property-read int $id
 * @property string $email
 */
class User extends Model {}
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Install dependencies
  run: composer install --no-dev

- name: Generate phpDocumentor docs
  run: vendor/bin/phpdoc

- name: Upload docs artifact
  uses: actions/upload-artifact@v4
  with:
    name: phpdoc
    path: docs/api/

- name: Deploy to GitHub Pages
  if: github.ref == 'refs/heads/main'
  uses: peaceiris/actions-gh-pages@v4
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./docs/api
```

## Performance

- phpDocumentor 3 uses a cache directory (`.phpdoc/cache`) for incremental builds — subsequent runs are significantly faster.
- Exclude non-source directories (`tests/`, `vendor/`, `var/`) via `<ignore>` in `phpdoc.xml` to reduce parse time.
- Run `phpdoc --template none` to validate without generating HTML output (useful for CI lint-only passes).
- For large applications (500+ classes), limit the `<visibility>` to `public` — generating private/protected docs doubles parse time.

## Security

- phpDocumentor generates static HTML — no runtime security surface.
- Avoid documenting credentials, tokens, or internal service endpoints in `@example` blocks.
- `<visibility>public</visibility>` in `phpdoc.xml` prevents internal implementation details from appearing in published docs.
- Do not add phpDocumentor to production Composer autoload — use `--dev` flag.

## Testing

```bash
# Generate docs with default config
vendor/bin/phpdoc

# Run with explicit config file
vendor/bin/phpdoc --config phpdoc.xml

# Validate config and exit (no output)
vendor/bin/phpdoc --template none

# Show verbose output for debugging
vendor/bin/phpdoc -v

# Target a specific directory
vendor/bin/phpdoc -d src/Users -t docs/users-api
```

## Dos

- Configure `phpdoc.xml` and commit it to version control — avoid relying on CLI flags in CI.
- Document all `@throws` annotations for checked business exceptions — callers depend on this for try/catch decisions.
- Use `array<string, mixed>` generics syntax for typed arrays — phpDocumentor 3 renders them correctly.
- Set `<visibility>public</visibility>` in `phpdoc.xml` for libraries distributed to external consumers.
- Add a `<guide>` section with Markdown files explaining architecture and usage flows beyond the raw API.
- Keep `phpdoc.xml` source paths narrow (e.g., `src/`) to exclude generated code, vendor, and tests.

## Don'ts

- Don't use `@param mixed` without description — if the type is truly mixed, document when each type variant is expected.
- Don't skip `@return` on methods returning complex structures — IDE type inference and doc readers depend on it.
- Don't commit `.phpdoc/cache` to version control — it contains generated cache files that change on every run.
- Don't use `@author` tags on individual methods — project-level attribution belongs in `composer.json` and the class/file docblock.
- Don't duplicate PHP 8 native types in docblocks (e.g., `@param string $name` when the signature already declares `string $name`) — only add `@param` when the docblock adds information the type hint does not.
- Don't run phpDocumentor from a global PHAR in CI — pin via Composer to ensure reproducible builds.
