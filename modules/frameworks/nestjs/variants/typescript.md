# NestJS + TypeScript Variant

> TypeScript-specific patterns for NestJS projects. Extends `modules/languages/typescript.md` and `modules/frameworks/nestjs/conventions.md`.

## tsconfig Requirements

```json
{
  "compilerOptions": {
    "strict": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "target": "ES2021",
    "module": "commonjs",
    "outDir": "./dist",
    "rootDir": "./src",
    "paths": {
      "@app/*": ["src/*"],
      "@common/*": ["src/common/*"]
    }
  }
}
```

`emitDecoratorMetadata: true` is **required** — NestJS DI uses runtime type metadata to resolve provider types.

## Strict Typing Patterns

### Typed Config Service

```typescript
// config/configuration.ts
export interface AppConfig {
  port: number;
  database: {
    url: string;
    poolSize: number;
  };
  jwt: {
    secret: string;
    expiresIn: string;
  };
}

export default (): AppConfig => ({
  port: parseInt(process.env.PORT ?? '3000', 10),
  database: {
    url: process.env.DATABASE_URL!,
    poolSize: parseInt(process.env.DB_POOL_SIZE ?? '10', 10),
  },
  jwt: {
    secret: process.env.JWT_SECRET!,
    expiresIn: process.env.JWT_EXPIRES_IN ?? '1h',
  },
});
```

Usage in services:
```typescript
this.configService.get<AppConfig['database']['url']>('database.url')
```

### Typed Request User

```typescript
// types/auth.types.ts
export interface AuthUser {
  userId: string;
  email: string;
  role: Role;
}

// types/express.d.ts
import { AuthUser } from './auth.types';
declare global {
  namespace Express {
    interface User extends AuthUser {}
  }
}
```

### Typed Decorators

Custom parameter decorator with explicit typing:
```typescript
// decorators/current-user.decorator.ts
export const CurrentUser = createParamDecorator(
  (data: keyof AuthUser | undefined, ctx: ExecutionContext): AuthUser | AuthUser[keyof AuthUser] => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user as AuthUser;
    return data ? user[data] : user;
  },
);

// Usage in controller
@Get('me')
getMe(@CurrentUser() user: AuthUser) { ... }

@Get('me/email')
getEmail(@CurrentUser('email') email: string) { ... }
```

### DTO Type Safety

```typescript
// Prefer mapped types over manual duplication
import { PartialType, PickType, OmitType, IntersectionType } from '@nestjs/swagger';

export class UpdateUserDto extends PartialType(CreateUserDto) {}

export class UserLoginDto extends PickType(CreateUserDto, ['email', 'password'] as const) {}

export class UserResponseDto extends OmitType(UserEntity, ['passwordHash'] as const) {}
```

### Generic Paginated Response

```typescript
// common/dto/paginated-response.dto.ts
export class PaginatedResponseDto<T> {
  @ApiProperty({ isArray: true })
  data: T[];

  @ApiProperty()
  total: number;

  @ApiProperty()
  page: number;

  @ApiProperty()
  limit: number;
}

// Usage
async findAll(page: number, limit: number): Promise<PaginatedResponseDto<UserResponseDto>> {
  const [items, total] = await this.repo.findAndCount({ skip: (page - 1) * limit, take: limit });
  return { data: items.map((u) => plainToInstance(UserResponseDto, u)), total, page, limit };
}
```

## Module Augmentation Best Practices

- Group all type augmentation in `src/types/` — one file per concern
- Import augmentation files in `main.ts` or `tsconfig.json` `include` array
- Never use `as any` to bypass type errors in service or controller code

## Async Patterns

- Use `firstValueFrom()` / `lastValueFrom()` from `rxjs` to convert NestJS `Observable` returns to Promises in async services
- Prefer `async/await` in service methods; reserve Observables for stream-oriented microservice handlers

## Dos

- Set `emitDecoratorMetadata: true` — DI resolution depends on it
- Use `PartialType`, `PickType`, `OmitType` from `@nestjs/swagger` for DTO composition
- Create typed config interfaces and use `configService.get<Type>('key')` — never cast to `any`
- Augment Express `Request` interface for `req.user` typing — eliminates `as any` in controllers

## Don'ts

- Don't use `any` in DTO, service, or guard code — use `unknown` and narrow it
- Don't share `tsconfig.json` `paths` without configuring `module-alias` or `tsconfig-paths` at runtime
- Don't import from deep relative paths across module boundaries — use barrel `index.ts` or path aliases
