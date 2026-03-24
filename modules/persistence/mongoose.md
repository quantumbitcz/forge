# Mongoose Best Practices

## Overview
Mongoose is the standard ODM for MongoDB in Node.js, providing schema validation, middleware hooks, and a rich query API on top of the MongoDB driver. Use it for document-oriented data where schema flexibility matters and relationships are embedded or referenced loosely. Avoid it when you need strict relational integrity, complex joins across many collections, or when the application benefits more from the raw MongoDB driver's performance.

## Architecture Patterns

### Schema Design
```typescript
import { Schema, model, Document, Types } from "mongoose";

interface IOrderItem {
  productId: Types.ObjectId;
  name:      string;
  quantity:  number;
  price:     number;
}

interface IOrder extends Document {
  userId:    Types.ObjectId;
  items:     IOrderItem[];
  total:     number;
  status:    "pending" | "processing" | "shipped" | "cancelled";
  createdAt: Date;
}

const orderItemSchema = new Schema<IOrderItem>({
  productId: { type: Schema.Types.ObjectId, ref: "Product", required: true },
  name:      { type: String, required: true },
  quantity:  { type: Number, required: true, min: 1 },
  price:     { type: Number, required: true, min: 0 },
}, { _id: false });  // embedded subdocument — no separate _id

const orderSchema = new Schema<IOrder>({
  userId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
  items:  [orderItemSchema],
  total:  { type: Number, required: true, min: 0 },
  status: { type: String, enum: ["pending", "processing", "shipped", "cancelled"],
            default: "pending", index: true },
}, { timestamps: true });

orderSchema.index({ userId: 1, status: 1 });  // compound index

export const Order = model<IOrder>("Order", orderSchema);
```

### Middleware (Pre/Post Hooks)
```typescript
// Pre-save: compute derived fields, hash passwords
orderSchema.pre("save", function(next) {
  if (this.isModified("items")) {
    this.total = this.items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  }
  next();
});

// Post-save: trigger side effects (notifications, audit log)
orderSchema.post("save", async function(doc) {
  await AuditLog.create({ entityId: doc._id, action: "order.saved" });
});

// Pre-deleteOne: cascade cleanup
orderSchema.pre("deleteOne", { document: true }, async function() {
  await Shipment.deleteMany({ orderId: this._id });
});
```

### Virtuals
```typescript
// Virtual: computed property not stored in DB
orderSchema.virtual("itemCount").get(function() {
  return this.items.reduce((sum, item) => sum + item.quantity, 0);
});

// Virtual populate: reference population without storing array
userSchema.virtual("orders", {
  ref:         "Order",
  localField:  "_id",
  foreignField: "userId",
  justOne:     false,
});

orderSchema.set("toJSON",   { virtuals: true });
orderSchema.set("toObject", { virtuals: true });
```

### Population (References)
```typescript
// populate: resolves ObjectId references in separate query
const order = await Order.findById(id)
  .populate("userId", "name email")          // select specific fields
  .populate("items.productId", "name sku")   // nested population
  .lean();                                   // plain JS object — faster

// Multiple nested population
const orders = await Order.find({ status: "pending" })
  .populate({ path: "userId", select: "name" })
  .lean();
```

## Configuration

```typescript
// db.ts
import mongoose from "mongoose";

const options: mongoose.ConnectOptions = {
  maxPoolSize:          10,
  minPoolSize:          2,
  serverSelectionTimeoutMS: 5000,
  socketTimeoutMS:      45000,
  heartbeatFrequencyMS: 10000,
};

export async function connectDB(): Promise<void> {
  mongoose.set("strictQuery", true);   // reject unknown fields
  await mongoose.connect(process.env.MONGODB_URI!, options);
}

// Graceful shutdown
process.on("SIGTERM", async () => {
  await mongoose.connection.close();
  process.exit(0);
});
```

## Performance

### Lean Queries
```typescript
// lean(): returns plain JS objects — 3-5x faster than full Mongoose documents
// Use when you don't need document methods, virtuals, or change tracking
const orders = await Order.find({ status: "pending" })
  .select("_id total status createdAt")
  .lean<IOrder[]>();
```

### Compound Indexes and Discriminator Indexes
```typescript
// Compound index for common query patterns
orderSchema.index({ userId: 1, createdAt: -1 });  // sort by latest per user
orderSchema.index({ status: 1, createdAt: 1 }, { expireAfterSeconds: 86400 });  // TTL index

// Covered query: index includes all projected fields (no document fetch)
orderSchema.index({ userId: 1, status: 1, total: 1 });  // covers { userId, status } queries projecting total
```

### Aggregation Pipeline
```typescript
// Prefer aggregation over multiple find() calls for reporting
const summary = await Order.aggregate([
  { $match: { userId: userId, status: { $ne: "cancelled" } } },
  { $group: {
    _id:        "$status",
    count:      { $sum: 1 },
    totalValue: { $sum: "$total" },
  }},
  { $sort: { count: -1 } },
]);
```

## Security

```typescript
// SAFE: Mongoose always uses parameterized driver operations
Order.findOne({ email: userInput })

// PROTECT against query injection — sanitize objects from user input
import mongoSanitize from "express-mongo-sanitize";
app.use(mongoSanitize());  // strips $ and . from req.body/params/query

// UNSAFE: never pass raw user objects directly into queries
// Order.find(req.body)  // allows { $where: "..." } injection!

// Validate with schema strictness
const orderSchema = new Schema({ ... }, { strict: true });  // rejects unknown fields
```

## Testing

```typescript
import { MongoMemoryServer } from "mongodb-memory-server";
import mongoose from "mongoose";

describe("Order model", () => {
  let mongod: MongoMemoryServer;

  beforeAll(async () => {
    mongod = await MongoMemoryServer.create();
    await mongoose.connect(mongod.getUri());
  });

  afterAll(async () => {
    await mongoose.disconnect();
    await mongod.stop();
  });

  afterEach(async () => {
    await Order.deleteMany({});  // clean between tests
  });

  test("pre-save hook computes total", async () => {
    const order = new Order({
      userId: new mongoose.Types.ObjectId(),
      items: [{ productId: new mongoose.Types.ObjectId(), name: "Widget", quantity: 2, price: 15 }],
      total: 0,
    });
    await order.save();
    expect(order.total).toBe(30);
  });
});
```

## Dos
- Use `{ timestamps: true }` in schema options for automatic `createdAt`/`updatedAt` fields.
- Use `.lean()` for read-only queries — significantly reduces memory and CPU overhead.
- Define compound indexes that match your query patterns — MongoDB can only use one index per query.
- Use `mongoose.set("strictQuery", true)` to reject fields not in the schema.
- Use `express-mongo-sanitize` middleware to prevent NoSQL injection from user-supplied objects.
- Use `{ _id: false }` on embedded subdocuments that don't need their own ID.
- Use discriminators for document type hierarchies instead of a single schema with many optional fields.

## Don'ts
- Don't use `find()` inside other `find()` callbacks in loops — causes N+1 MongoDB round trips.
- Don't pass raw request body objects directly into `Model.find()` — NoSQL injection risk.
- Don't use `populate()` for large collections — prefer aggregation pipelines for reporting.
- Don't skip adding indexes — MongoDB will do full collection scans without them.
- Don't rely on hooks for critical business logic — they are harder to test in isolation and can be skipped.
- Don't use `Model.update()` (deprecated) — use `updateOne()`, `updateMany()`, or `findOneAndUpdate()`.
- Don't store large binary blobs in MongoDB documents — use GridFS or external object storage instead.
