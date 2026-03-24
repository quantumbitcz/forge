# NestJS + Mongoose

> NestJS-specific patterns for Mongoose. Extends generic NestJS conventions.
> Generic NestJS patterns are NOT repeated here.

## Integration Setup

```bash
npm install @nestjs/mongoose mongoose
```

## MongooseModule Registration

```typescript
// app.module.ts
@Module({
  imports: [
    MongooseModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        uri: config.get<string>('MONGODB_URI'),
        serverSelectionTimeoutMS: 5000,
        socketTimeoutMS: 45000,
      }),
    }),
  ],
})
export class AppModule {}
```

## Schema and Model Definition

Use `@nestjs/mongoose` decorators — do NOT use raw Mongoose `Schema` constructor in NestJS projects:

```typescript
// users/schemas/user.schema.ts
import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type UserDocument = HydratedDocument<User>;

@Schema({ timestamps: true, versionKey: false })
export class User {
  @Prop({ required: true, maxlength: 100 })
  name: string;

  @Prop({ required: true, unique: true, lowercase: true })
  email: string;

  @Prop({ type: String, enum: UserRole, default: UserRole.USER })
  role: UserRole;

  @Prop({ select: false })   // exclude from default projections
  passwordHash?: string;
}

export const UserSchema = SchemaFactory.createForClass(User);

// Add indexes declaratively
UserSchema.index({ email: 1 }, { unique: true });
```

## Feature Module Registration

```typescript
// users/users.module.ts
@Module({
  imports: [MongooseModule.forFeature([{ name: User.name, schema: UserSchema }])],
  controllers: [UsersController],
  providers: [UsersService],
})
export class UsersModule {}
```

## Service with Model Injection

```typescript
// users/users.service.ts
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

@Injectable()
export class UsersService {
  constructor(
    @InjectModel(User.name) private readonly userModel: Model<UserDocument>,
  ) {}

  async findOne(id: string): Promise<UserResponseDto> {
    const user = await this.userModel.findById(id).exec();
    if (!user) throw new NotFoundException(`User ${id} not found`);
    return plainToInstance(UserResponseDto, user.toObject());
  }

  async create(dto: CreateUserDto): Promise<UserResponseDto> {
    const created = await this.userModel.create(dto);
    return plainToInstance(UserResponseDto, created.toObject());
  }

  async findPaginated(page: number, limit: number) {
    const [data, total] = await Promise.all([
      this.userModel.find().skip((page - 1) * limit).limit(limit).lean().exec(),
      this.userModel.countDocuments().exec(),
    ]);
    return { data, total, page, limit };
  }
}
```

## Error Handling

```typescript
// src/common/filters/mongo-exception.filter.ts
import { Catch, ArgumentsHost, HttpStatus } from '@nestjs/common';
import { BaseExceptionFilter } from '@nestjs/core';
import { MongoServerError } from 'mongodb';
import { Error as MongooseError } from 'mongoose';

@Catch(MongoServerError, MongooseError.ValidationError)
export class MongoExceptionFilter extends BaseExceptionFilter {
  catch(exception: MongoServerError | MongooseError.ValidationError, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse();

    if (exception instanceof MongoServerError && exception.code === 11000) {
      response.status(HttpStatus.CONFLICT).json({
        statusCode: 409,
        message: 'Duplicate key violation',
        field: Object.keys((exception as any).keyValue)[0],
      });
      return;
    }

    super.catch(exception, host);
  }
}
```

## Subdocuments and Nested Schemas

```typescript
@Schema({ _id: false })
export class AddressSchema {
  @Prop({ required: true })
  street: string;

  @Prop({ required: true })
  city: string;
}

const AddressSchemaFactory = SchemaFactory.createForClass(AddressSchema);

@Schema()
export class User {
  @Prop({ type: AddressSchemaFactory })
  address?: AddressSchema;
}
```

## Scaffolder Patterns

```yaml
patterns:
  schema: "src/{feature}/schemas/{feature}.schema.ts"
  service: "src/{feature}/{feature}.service.ts"
  module: "src/{feature}/{feature}.module.ts"
  filter: "src/common/filters/mongo-exception.filter.ts"
```

## Additional Dos/Don'ts

- DO use `@nestjs/mongoose` `@Schema`/`@Prop` decorators — do not construct raw `Schema` instances
- DO use `.lean()` on read-only queries for plain JS objects (faster, no Mongoose document overhead)
- DO call `.exec()` to get real Promises from Mongoose queries
- DO use `{ select: false }` on sensitive `@Prop` fields (e.g., `passwordHash`)
- DON'T use `findByIdAndUpdate()` without `{ new: true, runValidators: true }` options
- DON'T rely on `autoIndex: true` in production — manage indexes explicitly with `UserSchema.index()`
- DON'T leak Mongoose documents from service methods — call `.toObject()` or use `plainToInstance`
