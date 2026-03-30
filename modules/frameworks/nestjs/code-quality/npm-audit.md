# NestJS + npm-audit

> Extends `modules/code-quality/npm-audit.md` with NestJS-specific integration.
> Generic npm-audit conventions (audit levels, fix strategies, CI integration) are NOT repeated here.

## Integration Setup

```json
{
  "scripts": {
    "audit:prod": "npm audit --omit=dev --audit-level=high",
    "audit:full": "npm audit --audit-level=moderate",
    "audit:ci": "npm audit --omit=dev --audit-level=high --json > audit-report.json"
  }
}
```

## Framework-Specific Patterns

### NestJS Core Package Surface

NestJS has a large dependency surface. Prioritize auditing packages that handle untrusted input:

| Package | Risk Area | Priority |
|---|---|---|
| `@nestjs/core` | DI container, request pipeline | High |
| `@nestjs/platform-express` / `platform-fastify` | HTTP adapter — bundles Express/Fastify | High |
| `class-validator` | DTO validation — user input | High |
| `class-transformer` | Object transformation — prototype pollution vector | Critical |
| `@nestjs/jwt` / `jsonwebtoken` | Token verification | Critical |
| `@nestjs/passport` | Auth strategies | High |
| `@nestjs/swagger` | Swagger doc generation | Medium |
| `rxjs` | Observable streams — DoS via large payloads | Medium |

### `class-transformer` Prototype Pollution

`class-transformer` has a history of prototype pollution CVEs when transforming untrusted JSON. Pin the version and audit immediately on new advisories:

```bash
# Check for class-transformer vulnerabilities specifically
npm audit --json | jq '.vulnerabilities["class-transformer"]'
```

Always use `excludeExtraneousValues: true` in `plainToInstance` calls — reduces the attack surface of prototype pollution:

```ts
import { plainToInstance } from "class-transformer";
const dto = plainToInstance(CreateUserDto, body, { excludeExtraneousValues: true });
```

### Production Audit Scope

NestJS CLI tools (`@nestjs/cli`, `@compodoc/compodoc`) are dev-only. Use `--omit=dev` in production audits:

```bash
npm audit --omit=dev --audit-level=high
```

## Additional Dos

- Audit `class-transformer` and `class-validator` immediately on new advisories — they process untrusted JSON from HTTP request bodies.
- Set `--audit-level=high` as minimum for APIs with `@nestjs/passport` or JWT — auth package vulnerabilities are critical regardless of CVSS score.
- Include `@nestjs/platform-express` in audit monitoring — it bundles the underlying HTTP server and inherits its vulnerabilities.

## Additional Don'ts

- Don't use `npm audit fix --force` on `@nestjs/core` or platform adapters — major version bumps of NestJS packages are breaking changes that require migration guides.
- Don't skip auditing `rxjs` — Observable-based patterns in NestJS can be exploited via memory exhaustion if untrusted data drives observable streams without size limits.
- Don't use `--audit-level=critical` alone for NestJS APIs — `class-transformer` prototype pollution CVEs are typically rated `high`, not `critical`.
