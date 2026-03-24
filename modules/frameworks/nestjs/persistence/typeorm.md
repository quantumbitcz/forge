# NestJS + TypeORM

> NestJS-specific patterns for TypeORM. Extends generic NestJS conventions.
> Generic NestJS patterns are NOT repeated here.

## Integration Setup

```bash
npm install @nestjs/typeorm typeorm reflect-metadata pg
npm install -D @types/pg
```

`tsconfig.json` must have:
```json
{ "emitDecoratorMetadata": true, "experimentalDecorators": true }
```

## TypeOrmModule Registration

```typescript
// app.module.ts
@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        url: config.get<string>('DATABASE_URL'),
        entities: [__dirname + '/**/*.entity{.ts,.js}'],
        migrations: [__dirname + '/migrations/*{.ts,.js}'],
        synchronize: false,          // NEVER true in production
        logging: config.get('NODE_ENV') === 'development',
      }),
    }),
  ],
})
export class AppModule {}
```

## Feature Module Repository Registration

```typescript
// users/users.module.ts
@Module({
  imports: [TypeOrmModule.forFeature([UserEntity])],
  controllers: [UsersController],
  providers: [UsersService],
})
export class UsersModule {}
```

## Entity Definition

```typescript
// users/user.entity.ts
import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn } from 'typeorm';

@Entity('users')
export class UserEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ length: 100 })
  name: string;

  @Column({ unique: true })
  email: string;

  @Column({ type: 'enum', enum: UserRole, default: UserRole.USER })
  role: UserRole;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
```

## Repository Injection

```typescript
// users/users.service.ts
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly userRepo: Repository<UserEntity>,
  ) {}

  async findOne(id: string): Promise<UserResponseDto> {
    const user = await this.userRepo.findOne({ where: { id } });
    if (!user) throw new NotFoundException(`User ${id} not found`);
    return plainToInstance(UserResponseDto, user);
  }

  async create(dto: CreateUserDto): Promise<UserResponseDto> {
    const entity = this.userRepo.create(dto);
    const saved = await this.userRepo.save(entity);
    return plainToInstance(UserResponseDto, saved);
  }
}
```

## Custom Repository Pattern

Wrap the built-in repository for domain-specific queries:

```typescript
// users/users.repository.ts
@Injectable()
export class UsersRepository {
  constructor(
    @InjectRepository(UserEntity)
    private readonly repo: Repository<UserEntity>,
  ) {}

  async findByEmail(email: string): Promise<UserEntity | null> {
    return this.repo.findOne({ where: { email } });
  }

  async findActiveWithOrders(page: number, limit: number) {
    return this.repo
      .createQueryBuilder('user')
      .leftJoinAndSelect('user.orders', 'order')
      .where('user.active = :active', { active: true })
      .skip((page - 1) * limit)
      .take(limit)
      .getManyAndCount();
  }
}
```

Register `UsersRepository` in `providers` of `UsersModule`.

## Migration CLI

`package.json` scripts:
```json
{
  "typeorm": "ts-node -r tsconfig-paths/register ./node_modules/typeorm/cli -d src/data-source.ts",
  "migration:generate": "npm run typeorm -- migration:generate src/migrations/$NAME",
  "migration:run": "npm run typeorm -- migration:run",
  "migration:revert": "npm run typeorm -- migration:revert"
}
```

## Scaffolder Patterns

```yaml
patterns:
  entity: "src/{feature}/{feature}.entity.ts"
  repository: "src/{feature}/{feature}.repository.ts"
  migration: "src/migrations/{timestamp}-{Description}.ts"
  data_source: "src/data-source.ts"
```

## Additional Dos/Don'ts

- DO use `TypeOrmModule.forFeature([Entity])` in each feature module — this scopes the repository injection
- DO use `repo.create()` + `repo.save()` to trigger lifecycle hooks; avoid `repo.insert()` for inserts
- DO use `createQueryBuilder` for complex joins — avoid N+1 by joining relations in the query
- DON'T set `synchronize: true` — always use migrations
- DON'T use the legacy `getRepository()` global from `typeorm` — it is removed in v0.3+
- DON'T use `@OneToMany` with eager loading implicitly — specify `relations: ['orders']` in find options
- DON'T leak `UserEntity` objects from service methods — map to response DTOs
