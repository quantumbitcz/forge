# NestJS + Prisma

> NestJS-specific patterns for Prisma ORM. Extends generic NestJS conventions.
> Generic NestJS patterns (modules, guards, interceptors) are NOT repeated here.

## Integration Setup

```bash
npm install @prisma/client
npm install -D prisma
npx prisma init
```

## PrismaService (OnModuleInit)

```typescript
// src/prisma/prisma.service.ts
import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit(): Promise<void> {
    await this.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
```

## PrismaModule (Global)

```typescript
// src/prisma/prisma.module.ts
import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

Import `PrismaModule` once in `AppModule`. Because it is `@Global()`, all feature modules can inject `PrismaService` without importing `PrismaModule` again.

## Service Usage

```typescript
// src/users/users.service.ts
@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async findOne(id: string): Promise<UserResponseDto> {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new NotFoundException(`User ${id} not found`);
    return plainToInstance(UserResponseDto, user);
  }

  async create(dto: CreateUserDto): Promise<UserResponseDto> {
    const user = await this.prisma.user.create({ data: dto });
    return plainToInstance(UserResponseDto, user);
  }
}
```

## Error Handling

Map Prisma errors to NestJS HTTP exceptions in a global filter:

```typescript
// src/common/filters/prisma-exception.filter.ts
import { Catch, ArgumentsHost, HttpStatus } from '@nestjs/common';
import { BaseExceptionFilter } from '@nestjs/core';
import { PrismaClientKnownRequestError } from '@prisma/client/runtime/library';
import { Response } from 'express';

@Catch(PrismaClientKnownRequestError)
export class PrismaExceptionFilter extends BaseExceptionFilter {
  catch(exception: PrismaClientKnownRequestError, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    if (exception.code === 'P2002') {
      response.status(HttpStatus.CONFLICT).json({
        statusCode: 409,
        message: 'Unique constraint violation',
        fields: (exception.meta as any)?.target,
      });
      return;
    }
    if (exception.code === 'P2025') {
      response.status(HttpStatus.NOT_FOUND).json({
        statusCode: 404,
        message: 'Record not found',
      });
      return;
    }

    super.catch(exception, host);
  }
}
```

Register in `main.ts`:
```typescript
const { httpAdapter } = app.get(HttpAdapterHost);
app.useGlobalFilters(new PrismaExceptionFilter(httpAdapter));
```

## Transactions

```typescript
const result = await this.prisma.$transaction(async (tx) => {
  const user = await tx.user.create({ data: { name, email } });
  await tx.auditLog.create({ data: { action: 'USER_CREATED', userId: user.id } });
  return user;
});
```

## Health Check

```typescript
// Using @nestjs/terminus
import { PrismaHealthIndicator } from '@nestjs/terminus';

@Controller('health')
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private prisma: PrismaHealthIndicator,
  ) {}

  @Get()
  @HealthCheck()
  check() {
    return this.health.check([
      () => this.prisma.pingCheck('database'),
    ]);
  }
}
```

## Scaffolder Patterns

```yaml
patterns:
  prisma_service: "src/prisma/prisma.service.ts"
  prisma_module: "src/prisma/prisma.module.ts"
  prisma_filter: "src/common/filters/prisma-exception.filter.ts"
  schema: "prisma/schema.prisma"
  seed: "prisma/seed.ts"
```

## Additional Dos/Don'ts

- DO use `PrismaService extends PrismaClient` — no need to create a separate wrapper
- DO make `PrismaModule` global (`@Global()`) so all feature modules can inject `PrismaService`
- DO use `$transaction` for multi-step writes — atomicity is not automatic
- DO handle `P2002` (unique) and `P2025` (not found) in a global filter
- DON'T use `prisma.$queryRaw` without tagged template literals — use template literals to prevent injection
- DON'T call `prisma.model.findMany()` without pagination on unbounded tables
- DON'T import `PrismaModule` in every feature module — `@Global()` makes it available everywhere
