# Express + Mongoose

> Express-specific patterns for Mongoose. Extends generic Express conventions.
> Generic Express patterns are NOT repeated here.

## Integration Setup

```bash
npm install mongoose
npm install -D @types/mongoose   # only needed for older Mongoose; v6+ ships types
```

## Connection Lifecycle

```typescript
// src/lib/mongoose.ts
import mongoose from 'mongoose';

export async function connectDatabase(): Promise<void> {
  mongoose.set('strictQuery', true);
  await mongoose.connect(process.env.MONGODB_URI!, {
    serverSelectionTimeoutMS: 5000,
    socketTimeoutMS: 45000,
  });
  console.log('MongoDB connected:', mongoose.connection.host);
}

export async function disconnectDatabase(): Promise<void> {
  await mongoose.disconnect();
}
```

Bootstrap:
```typescript
// src/app.ts
await connectDatabase();
const app = express();
```

## Model Registration

Define models in dedicated files and import them from a central index — this prevents model re-registration in hot-reload environments:

```typescript
// src/models/User.ts
import { Schema, model, Document } from 'mongoose';

export interface IUser extends Document {
  name: string;
  email: string;
  createdAt: Date;
}

const UserSchema = new Schema<IUser>(
  { name: { type: String, required: true }, email: { type: String, required: true, unique: true } },
  { timestamps: true }
);

export const User = model<IUser>('User', UserSchema);
```

```typescript
// src/models/index.ts — re-export all models
export { User } from './User';
```

## Plugin System

```typescript
// src/plugins/auditPlugin.ts
import { Schema } from 'mongoose';

export function auditPlugin(schema: Schema): void {
  schema.add({ updatedBy: { type: String } });
  schema.pre('save', function (next) {
    this.updatedBy = getCurrentUser();  // from context / AsyncLocalStorage
    next();
  });
}

// Apply globally
mongoose.plugin(auditPlugin);
```

## Graceful Shutdown

```typescript
process.on('SIGTERM', async () => {
  await disconnectDatabase();
  server.close(() => process.exit(0));
});
```

## Error Handling

```typescript
import { MongoServerError } from 'mongodb';

export function mongoErrorHandler(err: unknown, req: Request, res: Response, next: NextFunction) {
  if (err instanceof MongoServerError && err.code === 11000) {
    return res.status(409).json({ error: 'Duplicate key', field: Object.keys(err.keyValue)[0] });
  }
  next(err);
}
```

## Scaffolder Patterns

```yaml
patterns:
  connection: "src/lib/mongoose.ts"
  model: "src/models/{Entity}.ts"
  models_index: "src/models/index.ts"
  plugin: "src/plugins/{name}Plugin.ts"
```

## Additional Dos/Don'ts

- DO export models from a central `index.ts` to avoid `OverwriteModelError` in Jest/hot-reload
- DO set `strictQuery: true` to silence Mongoose 7 deprecation warning
- DO apply global plugins before connecting (`mongoose.plugin()`)
- DON'T use `mongoose.connect()` multiple times — check `mongoose.connection.readyState` first
- DON'T use `findByIdAndUpdate()` without `{ new: true, runValidators: true }` options
- DON'T rely on `autoIndex: true` in production — manage indexes explicitly
