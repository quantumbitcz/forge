# NestJS + typedoc

> Extends `modules/code-quality/typedoc.md` with NestJS-specific integration.
> Generic typedoc conventions (installation, typedoc.json, CI) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev typedoc typedoc-plugin-markdown
```

**`typedoc.json` for NestJS:**

```json
{
  "$schema": "https://typedoc.org/schema.json",
  "entryPoints": [
    "src/*/controllers",
    "src/*/services",
    "src/*/dto",
    "src/*/interfaces"
  ],
  "entryPointStrategy": "expand",
  "out": "docs/api",
  "tsconfig": "./tsconfig.json",
  "name": "NestJS API",
  "readme": "README.md",
  "includeVersion": true,
  "excludePrivate": true,
  "excludeInternal": true,
  "exclude": [
    "src/**/*.module.ts",
    "src/**/*.spec.ts",
    "src/**/*.e2e-spec.ts",
    "src/main.ts",
    "src/**/*.entity.ts",     // persistence — document in persistence layer
    "src/**/*.guard.ts",      // internal infrastructure
    "src/**/*.interceptor.ts",
    "src/**/*.filter.ts"
  ],
  "categorizeByGroup": true,
  "categoryOrder": ["Controllers", "Services", "DTOs", "Interfaces", "*"]
}
```

## Framework-Specific Patterns

### Documenting Controllers as API Contracts

NestJS controllers define the HTTP API surface. Document each handler's route, parameters, and response shapes:

```ts
/**
 * User management endpoints.
 * @category Controllers
 */
@Controller("users")
export class UsersController {
  /**
   * Creates a new user account.
   *
   * @route POST /users
   * @param dto - User creation payload
   * @returns Created user with ID assigned
   * @throws ConflictException if email already exists
   * @throws BadRequestException if DTO validation fails
   */
  @Post()
  create(@Body() dto: CreateUserDto): Promise<UserResponseDto> { ... }
}
```

### Documenting Module Boundaries

Document `@Module()` metadata to make the module graph navigable in generated docs:

```ts
/**
 * User domain module.
 *
 * @remarks
 * Provides {@link UsersService} to other modules via `exports`.
 * Requires {@link DatabaseModule} for persistence.
 * @module
 */
@Module({ ... })
export class UsersModule {}
```

### DTOs as API Contracts

DTOs are the public API contract between client and server. Document the validation constraints:

```ts
/**
 * Payload for creating a new user.
 * @category DTOs
 */
export class CreateUserDto {
  /**
   * User's email address. Must be unique across the system.
   * @example "user@example.com"
   */
  @IsEmail()
  email: string;
}
```

## Additional Dos

- Include `src/*/dto/` in entry points — DTOs define the HTTP contract consumed by API clients and should be fully documented.
- Exclude `*.module.ts`, `*.guard.ts`, `*.interceptor.ts`, and `*.filter.ts` — these are internal infrastructure, not public API surface.
- Add `@module` tag to `@Module()` classes to generate a module-level summary in the docs.

## Additional Don'ts

- Don't include `*.entity.ts` in TypeDoc — entity documentation belongs to the persistence layer, not the HTTP API contract.
- Don't document `@Injectable()` providers that are implementation details — document the service interface (`IUsersService`) instead if one exists.
- Don't generate TypeDoc for `guards/`, `interceptors/`, and `filters/` unless they are part of a shared library — they are framework infrastructure, not API surface.
