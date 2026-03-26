# Firestore Best Practices

## Overview
Firestore (Cloud Firestore) is a serverless, auto-scaling NoSQL document database from Google Cloud / Firebase. Use it for mobile/web applications needing real-time sync, offline support, and seamless Firebase integration (Auth, Cloud Functions, Hosting). Avoid Firestore for complex relational queries with joins, analytics workloads, or when vendor lock-in to Google Cloud is unacceptable. Consider MongoDB for self-hosted document needs, or PostgreSQL when you need relational capabilities.

## Architecture Patterns

**Document + collection hierarchy:**
```javascript
// Collection → Document → Subcollection → Document
// users/{userId}/orders/{orderId}/items/{itemId}

const userRef = doc(db, 'users', userId);
const ordersRef = collection(db, 'users', userId, 'orders');
```

**Data modeling — denormalize for read patterns:**
```javascript
// Embed when data is always read together and bounded
{
  id: "order_123",
  userId: "user_456",
  items: [
    { sku: "WIDGET-1", name: "Widget", qty: 2, price: 9.99 },
    { sku: "GADGET-7", name: "Gadget", qty: 1, price: 49.99 }
  ],
  total: 69.97,
  // Denormalized user name for display (avoid extra read)
  userName: "Alice Smith"
}
```

**Real-time listeners:**
```javascript
const unsubscribe = onSnapshot(
  query(collection(db, 'messages'), where('roomId', '==', roomId), orderBy('createdAt', 'desc'), limit(50)),
  (snapshot) => {
    snapshot.docChanges().forEach((change) => {
      if (change.type === 'added') addMessage(change.doc.data());
      if (change.type === 'modified') updateMessage(change.doc.data());
      if (change.type === 'removed') removeMessage(change.doc.id);
    });
  }
);
```

**Composite indexes (required for compound queries):**
```javascript
// Firestore requires a composite index for this query
// Create via Firebase Console or firestore.indexes.json
query(collection(db, 'orders'),
  where('status', '==', 'active'),
  where('total', '>', 100),
  orderBy('total', 'desc')
);
```

**Anti-pattern — deeply nested subcollections for data queried across parents:** Firestore queries don't span subcollections by default. If you need "all orders across all users," use a top-level `orders` collection with a `userId` field, not `users/{id}/orders`.

## Configuration

**Firebase initialization:**
```javascript
import { initializeApp } from 'firebase/app';
import { getFirestore, connectFirestoreEmulator } from 'firebase/firestore';

const app = initializeApp({ projectId: 'my-project', /* ... */ });
const db = getFirestore(app);

// Local development with emulator
if (process.env.NODE_ENV === 'development') {
  connectFirestoreEmulator(db, 'localhost', 8080);
}
```

**Firestore indexes (`firestore.indexes.json`):**
```json
{
  "indexes": [
    {
      "collectionGroup": "orders",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    }
  ]
}
```

**Security rules (`firestore.rules`):**
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    match /users/{userId}/orders/{orderId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow create: if request.auth != null && request.auth.uid == userId
                    && request.resource.data.total is number;
    }
  }
}
```

## Performance

**Document size limits:** Max 1 MB per document, max 20k fields. Keep documents lean — split large data into subcollections.

**Query limitations:**
- One `!=` or `not-in` per query
- `in` operator supports up to 30 values
- Range filters (`<`, `>`) on one field only per query
- `OR` queries via `or()` (limited to 30 disjunctions)

**Batch writes (atomic, up to 500 operations):**
```javascript
const batch = writeBatch(db);
items.forEach(item => batch.set(doc(collection(db, 'items')), item));
await batch.commit();
```

**Pagination with cursors (not offset):**
```javascript
const first = query(collection(db, 'orders'), orderBy('createdAt'), limit(25));
const snapshot = await getDocs(first);
const lastDoc = snapshot.docs[snapshot.docs.length - 1];

const next = query(collection(db, 'orders'), orderBy('createdAt'), startAfter(lastDoc), limit(25));
```

**Avoid hotspots:** Documents updated very frequently (> 1 write/sec sustained) become hot and throttle. Distribute writes using sharded counters or Cloud Functions aggregation.

## Security

**Security rules are mandatory:** Without rules, Firestore is either fully open or fully closed. Never deploy with `allow read, write: if true`.

**Validate data shape in rules:**
```
allow create: if request.resource.data.keys().hasAll(['name', 'email'])
              && request.resource.data.name is string
              && request.resource.data.email is string;
```

**Use Firebase Auth integration:** `request.auth.uid` is the authenticated user's ID — use it for ownership checks, not a client-supplied `userId` field.

**Server-side access with Admin SDK bypasses rules:**
```javascript
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();
// Admin SDK has full access — use only in trusted server environments
```

## Testing

**Firebase Emulator Suite for local testing:**
```bash
firebase emulators:start --only firestore
```
```javascript
import { connectFirestoreEmulator } from 'firebase/firestore';
connectFirestoreEmulator(db, 'localhost', 8080);
```

**Security rules testing:**
```javascript
import { assertSucceeds, assertFails, initializeTestEnvironment } from '@firebase/rules-unit-testing';

const testEnv = await initializeTestEnvironment({ projectId: 'test' });
const alice = testEnv.authenticatedContext('alice');
await assertSucceeds(alice.firestore().collection('users').doc('alice').get());
await assertFails(alice.firestore().collection('users').doc('bob').set({ name: 'hack' }));
```

Test with the emulator for security rules validation, offline behavior, and real-time listener accuracy. Never run tests against production Firestore.

## Dos
- Design data models around your query patterns — Firestore has no joins, so denormalize for read efficiency.
- Use the Firebase Emulator Suite for all local development and testing — it's free and fast.
- Deploy security rules with every deployment — treat them as code, version-controlled alongside your app.
- Use `onSnapshot` for real-time UIs — Firestore's real-time sync is its strongest feature.
- Use batch writes for multi-document operations — they're atomic and reduce network round trips.
- Use cursor-based pagination (`startAfter`) — offset-based pagination doesn't exist in Firestore.
- Use collection group queries when you need to query across subcollections with the same name.

## Don'ts
- Don't deploy with `allow read, write: if true` — this exposes all data to the internet.
- Don't embed unbounded arrays in documents — they grow past 1 MB and cause read/write failures.
- Don't use subcollections when you need cross-parent queries — use top-level collections with reference fields.
- Don't write to a single document more than once per second sustained — use sharded counters for high-write fields.
- Don't use Firestore for analytics or aggregation-heavy workloads — export to BigQuery for analytics.
- Don't fetch entire collections when you need a subset — always use `where()` and `limit()` to constrain reads.
- Don't trust client-supplied data without security rule validation — clients can send arbitrary JSON.
