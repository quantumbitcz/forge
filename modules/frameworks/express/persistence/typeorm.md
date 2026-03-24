# Express + TypeORM

> Express-specific patterns for TypeORM. Extends generic Express conventions.
> Generic Express patterns are NOT repeated here.

## Integration Setup

```bash
npm install typeorm reflect-metadata pg
npm install -D @types/pg ts-node
```

`tsconfig.json` must have:
```json
{ "emitDecoratorMetadata": true, "experimentalDecorators": true }
```

## DataSource Initialization

```typescript
// src/lib/dataSource.ts
import 'reflect-metadata';
import { DataSource } from 'typeorm';
import { User } from '../entity/User';

export const AppDataSource = new DataSource({
  type: 'postgres',
  url: process.env.DATABASE_URL,
  synchronize: false,          // never true in production
  logging: process.env.NODE_ENV === 'development',
  entities: [User],
  migrations: ['src/migration/*.ts'],
});
```

## App Bootstrap

```typescript
// src/app.ts
import express from 'express';
import { AppDataSource } from './lib/dataSource';

export async function bootstrap() {
  await AppDataSource.initialize();
  const app = express();
  // ... register routes
  return app;
}
```

## Repository Injection

Use `AppDataSource.getRepository()` inside request handlers or service constructors — never use `getRepository()` global shim:

```typescript
// src/service/UserService.ts
export class UserService {
  constructor(private readonly repo = AppDataSource.getRepository(User)) {}

  async findById(id: string) {
    return this.repo.findOne({ where: { id } });
  }

  async create(data: CreateUserDto) {
    return this.repo.save(this.repo.create(data));
  }
}
```

## Entity Subscriber (audit log)

```typescript
import { EntitySubscriberInterface, InsertEvent, EventSubscriber } from 'typeorm';

@EventSubscriber()
export class UserSubscriber implements EntitySubscriberInterface<User> {
  listenTo() { return User; }

  async afterInsert(event: InsertEvent<User>) {
    await event.manager.getRepository(AuditLog).save({
      action: 'USER_CREATED', entityId: event.entity.id,
    });
  }
}
```

Register subscriber on the DataSource: `subscribers: [UserSubscriber]`.

## Migration CLI (ts-node)

`package.json` scripts:
```json
{
  "typeorm": "ts-node -r tsconfig-paths/register ./node_modules/typeorm/cli",
  "migration:generate": "npm run typeorm -- migration:generate src/migration/$NAME -d src/lib/dataSource.ts",
  "migration:run": "npm run typeorm -- migration:run -d src/lib/dataSource.ts",
  "migration:revert": "npm run typeorm -- migration:revert -d src/lib/dataSource.ts"
}
```

## Scaffolder Patterns

```yaml
patterns:
  data_source: "src/lib/dataSource.ts"
  entity: "src/entity/{Entity}.ts"
  service: "src/service/{Entity}Service.ts"
  migration: "src/migration/{timestamp}-{Description}.ts"
  subscriber: "src/subscriber/{Entity}Subscriber.ts"
```

## Additional Dos/Don'ts

- DO set `synchronize: false` in all environments — use migrations exclusively
- DO initialize DataSource once at startup and export the instance
- DO use `repo.create()` + `repo.save()` rather than `repo.insert()` to trigger lifecycle hooks
- DON'T use `getRepository()` global from `typeorm` package — it's removed in v0.3+
- DON'T use `@OneToMany` eagerly without `relations` query option — silent N+1 risk
