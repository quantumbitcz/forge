# NestJS + prettier

> Extends `modules/code-quality/prettier.md` with NestJS-specific integration.
> Generic prettier conventions (config format, ignore patterns, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev prettier
```

**`.prettierrc.json` for NestJS:**

```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2,
  "arrowParens": "always",
  "decoratorsBeforeExport": true
}
```

**`.prettierignore`:**

```
dist/
coverage/
*.generated.ts
node_modules/
```

**`package.json` scripts:**

```json
{
  "scripts": {
    "format": "prettier --write \"src/**/*.ts\" \"test/**/*.ts\"",
    "format:check": "prettier --check \"src/**/*.ts\" \"test/**/*.ts\""
  },
  "lint-staged": {
    "*.{ts,json}": ["prettier --write"]
  }
}
```

## Framework-Specific Patterns

### Decorator Formatting

NestJS files heavily use class decorators. Prettier formats them consistently — stacked decorators each get their own line:

```ts
// Prettier-formatted NestJS controller
@ApiTags("users")
@Controller("users")
@UseGuards(JwtAuthGuard)
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get(":id")
  @ApiOperation({ summary: "Get user by ID" })
  findOne(@Param("id") id: string): Promise<UserDto> {
    return this.usersService.findOne(id);
  }
}
```

### DTO Class Formatting

`class-validator` DTOs use multiple decorators per property. Prettier keeps them readable:

```ts
export class CreateUserDto {
  @IsEmail()
  @IsNotEmpty()
  email: string;

  @IsString()
  @MinLength(8)
  @MaxLength(64)
  password: string;
}
```

### Test File Convention

NestJS generates e2e spec files in `test/` and unit specs alongside source in `src/`. Include both directories in format scripts.

## Additional Dos

- Set `printWidth: 100` for NestJS projects — decorator chains make 80-character limits impractical without artificial line breaks.
- Format both `src/` and `test/` directories — e2e spec files in `test/` are often left unformatted, diverging from source style.
- Use `lint-staged` for NestJS projects — it prevents decorator-heavy files from creating large formatting-only commits.

## Additional Don'ts

- Don't set `singleQuote: false` in NestJS projects that use Angular-style templates — inconsistent quoting across the stack adds cognitive overhead.
- Don't run Prettier on generated Swagger/OpenAPI JSON artifacts in `docs/` — they are auto-generated and large; formatting adds no value.
