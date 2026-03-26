# Firebase Auth — Best Practices

## Overview

Firebase Authentication is a managed identity service from Google providing email/password,
social login (Google, Apple, Facebook, GitHub), phone number, and anonymous authentication
with tight integration into the Firebase ecosystem (Firestore, Cloud Functions, Hosting).
Use Firebase Auth for mobile-first and web applications on GCP/Firebase where real-time
SDKs and zero-infrastructure auth are priorities. Avoid it when you need full OIDC/SAML
provider capabilities, fine-grained RBAC beyond custom claims, or multi-cloud portability.
Consider Auth0 or Keycloak for complex enterprise SSO requirements.

## Architecture Patterns

### Client SDK Authentication (Recommended)
```javascript
import { getAuth, signInWithPopup, GoogleAuthProvider } from "firebase/auth";

const auth = getAuth();
const provider = new GoogleAuthProvider();
provider.addScope("profile");

const result = await signInWithPopup(auth, provider);
const user = result.user;
const token = await user.getIdToken();
// Send token to backend in Authorization header
```

### Backend Token Verification
```javascript
const admin = require("firebase-admin");
admin.initializeApp();

async function verifyToken(req, res, next) {
  const idToken = req.headers.authorization?.replace("Bearer ", "");
  if (!idToken) return res.status(401).json({ error: "Missing token" });

  const decoded = await admin.auth().verifyIdToken(idToken);
  req.uid = decoded.uid;
  req.claims = decoded;
  next();
}
```

### Custom Claims for Authorization
```javascript
// Set custom claims (admin SDK — server only)
await admin.auth().setCustomUserClaims(uid, {
  role: "admin",
  orgId: "org_123",
  permissions: ["read", "write", "manage"]
});

// Access in security rules or backend
// Firestore: request.auth.token.role == "admin"
// Backend: decoded.role === "admin"
```

### Multi-tenancy (Identity Platform)
```javascript
// Google Cloud Identity Platform extends Firebase Auth with tenancy
const tenantAuth = admin.auth().tenantManager().authForTenant("tenant-id");
const user = await tenantAuth.createUser({ email, password });
```

### Anti-pattern — storing roles in Firestore and checking per request: Custom claims are propagated inside the ID token and verified locally without a database read. Storing roles in Firestore forces a read on every authenticated request, adding latency and cost. Use custom claims for authorization data that changes infrequently.

## Configuration

**Firebase project initialization:**
```javascript
import { initializeApp } from "firebase/app";
import { getAuth, connectAuthEmulator } from "firebase/auth";

const app = initializeApp({
  apiKey: "AIza...",
  authDomain: "my-project.firebaseapp.com",
  projectId: "my-project"
});

const auth = getAuth(app);
if (process.env.NODE_ENV === "development") {
  connectAuthEmulator(auth, "http://localhost:9099");
}
```

**Authorized domains (Firebase Console):**
Only add domains you control. Remove `localhost` for production projects — use a separate Firebase project for development.

**Session management:**
```javascript
// Set token persistence
import { setPersistence, browserLocalPersistence } from "firebase/auth";
await setPersistence(auth, browserLocalPersistence);
// Options: browserLocalPersistence (default), browserSessionPersistence, inMemoryPersistence
```

## Performance

**Token caching:** Firebase SDK caches ID tokens and auto-refreshes before expiry (1 hour). Never call `getIdToken(true)` on every request — the forced refresh adds latency and hits Firebase rate limits.

**Minimize custom claims size:** Custom claims are included in every ID token. Keep them under 1000 bytes total. Store large authorization data elsewhere (Firestore) and reference it.

**Batch user operations (Admin SDK):**
```javascript
// Import up to 1000 users at once
await admin.auth().importUsers(users, { hash: { algorithm: "BCRYPT" } });

// List users in batches
const listResult = await admin.auth().listUsers(1000, nextPageToken);
```

**Avoid blocking functions for non-critical checks:** Blocking Cloud Functions (beforeCreate, beforeSignIn) add latency to every auth operation. Use them only for essential validation.

## Security

**Never expose the Admin SDK in client-side code.** The Admin SDK bypasses all security rules and has full access to all Firebase services.

**Validate ID tokens on every backend request:**
```javascript
// Always verify — never trust client-supplied claims without verification
const decoded = await admin.auth().verifyIdToken(idToken);
// Check custom claims for authorization
if (decoded.role !== "admin") throw new ForbiddenError();
```

**Enable email enumeration protection:** In Firebase Console → Authentication → Settings, enable email enumeration protection to prevent attackers from discovering registered emails.

**Enforce MFA for sensitive operations:**
```javascript
import { multiFactor, PhoneMultiFactorGenerator } from "firebase/auth";

const mfaUser = multiFactor(user);
const session = await mfaUser.getSession();
// Enroll phone as second factor
```

**Rate limiting:** Firebase Auth has built-in rate limits, but implement application-level rate limiting on your backend for password reset and email verification endpoints.

## Testing

**Firebase Emulator Suite:**
```bash
firebase emulators:start --only auth
```
```javascript
import { connectAuthEmulator } from "firebase/auth";
connectAuthEmulator(auth, "http://localhost:9099");

// Create test users programmatically
await createUserWithEmailAndPassword(auth, "test@example.com", "password123");
```

**Security rules testing with @firebase/rules-unit-testing:**
```javascript
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";

const testEnv = await initializeTestEnvironment({ projectId: "test" });
const alice = testEnv.authenticatedContext("alice", { role: "admin" });
const bob = testEnv.unauthenticatedContext();
```

Never run auth tests against production Firebase. Always use the emulator or a dedicated test project.

## Dos
- Use the Firebase Emulator Suite for all local development — it supports auth, Firestore, and Functions together.
- Use custom claims for role-based access control — they're included in the ID token and verified locally.
- Validate ID tokens on every backend request using the Admin SDK — never trust client-supplied user data.
- Enable email enumeration protection in production to prevent user discovery attacks.
- Use separate Firebase projects for development, staging, and production.
- Implement proper sign-out that clears all auth state: `signOut(auth)` on client, invalidate server sessions.
- Use `onAuthStateChanged` for reactive auth state management instead of polling `currentUser`.

## Don'ts
- Don't expose Firebase Admin SDK or service account credentials in client-side code.
- Don't store roles or permissions in Firestore and fetch them on every request — use custom claims.
- Don't force-refresh tokens (`getIdToken(true)`) on every API call — the SDK auto-refreshes before expiry.
- Don't skip ID token verification on the backend — client tokens can be forged.
- Don't use anonymous auth for accessing sensitive data — it provides no identity verification.
- Don't put large payloads in custom claims — they're included in every token and limited to 1000 bytes.
- Don't use the same Firebase project for production and development — configuration mistakes in dev affect prod.
