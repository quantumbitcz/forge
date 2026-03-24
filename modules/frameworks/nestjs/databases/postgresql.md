# NestJS + PostgreSQL (TypeORM / Prisma)

> NestJS database setup for PostgreSQL. Covers TypeOrmModule and PrismaModule patterns with health checks.

## Integration Setup

```bash
# TypeORM
npm install @nestjs/typeorm typeorm pg

# Prisma (alternative)
npm install @prisma/client
npm install -D prisma
npx prisma init
```

## Framework-Specific Patterns

### TypeORM — `AppModule` registration
```typescript
// app.module.ts
import { TypeOrmModule } from '@nestjs/typeorm';

@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        url: config.get('DATABASE_URL'),
        entities: [__dirname + '/**/*.entity{.ts,.js}'],
        migrations: [__dirname + '/migrations/*{.ts,.js}'],
        migrationsRun: false,           // run manually or in bootstrap
        synchronize: false,             // never true in production
        ssl: config.get('DB_SSL') === 'true' ? { rejectUnauthorized: false } : false,
      }),
      inject: [ConfigService],
    }),
  ],
})
export class AppModule {}
```

### Prisma — custom `PrismaService`
```typescript
// prisma/prisma.service.ts
import { Injectable, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
  async onModuleInit() { await this.$connect(); }
}
```

```typescript
// prisma/prisma.module.ts
@Global()
@Module({ providers: [PrismaService], exports: [PrismaService] })
export class PrismaModule {}
```

### Health check (TypeORM)
```typescript
// health/health.module.ts
import { TypeOrmHealthIndicator, TerminusModule } from '@nestjs/terminus';

@Controller('health')
export class HealthController {
  constructor(private db: TypeOrmHealthIndicator, private health: HealthCheckService) {}

  @Get()
  @HealthCheck()
  check() {
    return this.health.check([() => this.db.pingCheck('database')]);
  }
}
```

## Scaffolder Patterns
```
src/
  app.module.ts
  prisma/
    prisma.service.ts
    prisma.module.ts
  health/
    health.controller.ts
    health.module.ts
  users/
    users.module.ts
    users.repository.ts   # wraps PrismaService or TypeORM repository
    users.service.ts
    users.entity.ts       # TypeORM entity (or prisma schema handles this)
```

## Dos
- Use `TypeOrmModule.forRootAsync` with `ConfigService` — never hardcode connection strings
- Set `synchronize: false` in all non-local environments; use migrations instead
- Mark `PrismaService` as `@Global()` so it can be injected without re-importing `PrismaModule`
- Add a `/health` endpoint with `@nestjs/terminus` for readiness/liveness probes

## Don'ts
- Don't use `synchronize: true` in staging or production — it can drop columns
- Don't inject `PrismaClient` or `DataSource` directly in controllers; go through a repository
- Don't swallow database errors — let them propagate and catch at the exception filter layer
- Don't skip connection pooling config for high-traffic services (`extra.max` in TypeORM)
