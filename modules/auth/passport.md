# Passport.js — Best Practices

## Overview

Passport.js is a Node.js authentication middleware supporting 500+ strategies (local, OAuth2,
SAML, OpenID Connect, JWT, API keys). Use it when building Express/Fastify/Koa backends in
Node.js that need pluggable authentication strategies. Passport excels at composing multiple
auth methods in one application (e.g., local login + Google OAuth + API key). Avoid Passport
when using a managed identity provider (Auth0, Cognito) that handles the full flow, or when
a simpler JWT middleware suffices without the strategy abstraction.

## Architecture Patterns

### Local Strategy (Email + Password)
```javascript
import passport from "passport";
import { Strategy as LocalStrategy } from "passport-local";
import bcrypt from "bcrypt";

passport.use(new LocalStrategy(
  { usernameField: "email" },
  async (email, password, done) => {
    const user = await userRepository.findByEmail(email);
    if (!user) return done(null, false, { message: "Invalid credentials" });

    const valid = await bcrypt.compare(password, user.passwordHash);
    if (!valid) return done(null, false, { message: "Invalid credentials" });

    return done(null, user);
  }
));
```

### OAuth2 Strategy (Google)
```javascript
import { Strategy as GoogleStrategy } from "passport-google-oauth20";

passport.use(new GoogleStrategy({
    clientID: process.env.GOOGLE_CLIENT_ID,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET,
    callbackURL: "/auth/google/callback"
  },
  async (accessToken, refreshToken, profile, done) => {
    let user = await userRepository.findByGoogleId(profile.id);
    if (!user) {
      user = await userRepository.create({
        googleId: profile.id,
        email: profile.emails[0].value,
        name: profile.displayName
      });
    }
    return done(null, user);
  }
));
```

### JWT Strategy (Stateless API Auth)
```javascript
import { Strategy as JwtStrategy, ExtractJwt } from "passport-jwt";

passport.use(new JwtStrategy({
    jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
    secretOrKey: process.env.JWT_SECRET,
    algorithms: ["HS256"]
  },
  async (payload, done) => {
    const user = await userRepository.findById(payload.sub);
    if (!user) return done(null, false);
    return done(null, user);
  }
));
```

### Session Serialization (for session-based auth)
```javascript
passport.serializeUser((user, done) => done(null, user.id));
passport.deserializeUser(async (id, done) => {
  const user = await userRepository.findById(id);
  done(null, user);
});
```

### Anti-pattern — using `passport.authenticate` without error handling in the callback: The default behavior on failure is to return a 401 with no message. Always use custom callbacks or `failureRedirect`/`failureMessage` options to provide meaningful feedback.

## Configuration

**Express integration:**
```javascript
import express from "express";
import session from "express-session";
import passport from "passport";
import RedisStore from "connect-redis";

const app = express();

app.use(session({
  store: new RedisStore({ client: redisClient }),
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: { secure: true, httpOnly: true, sameSite: "lax", maxAge: 24 * 60 * 60 * 1000 }
}));

app.use(passport.initialize());
app.use(passport.session());  // only for session-based auth
```

**Route protection middleware:**
```javascript
function requireAuth(req, res, next) {
  if (req.isAuthenticated()) return next();
  res.status(401).json({ error: "Authentication required" });
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.isAuthenticated()) return res.status(401).json({ error: "Authentication required" });
    if (!roles.includes(req.user.role)) return res.status(403).json({ error: "Insufficient permissions" });
    next();
  };
}
```

**Multiple strategies on one route:**
```javascript
app.post("/api/data",
  passport.authenticate(["jwt", "bearer"], { session: false }),
  dataController.list
);
```

## Performance

**Avoid deserializing the full user on every request:** Store only the user ID in the session and load the full user object only when needed. Consider caching deserialized users in Redis.

**Use `session: false` for API routes:** Session-based auth adds cookie overhead and session store lookups. For stateless APIs, use JWT or bearer token strategies with `{ session: false }`.

**Lazy strategy loading:** Only require and configure strategies you actually use. Each strategy adds startup overhead and dependencies.

## Security

**Hash passwords with bcrypt (cost factor >= 12):**
```javascript
const hash = await bcrypt.hash(password, 12);
```

**Use generic error messages:** Return "Invalid credentials" for both wrong email and wrong password — don't reveal which field was incorrect.

**CSRF protection for session-based auth:**
```javascript
import csrf from "csurf";
app.use(csrf({ cookie: true }));
```

**Rate limit authentication endpoints:**
```javascript
import rateLimit from "express-rate-limit";
const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 10 });
app.use("/auth/login", authLimiter);
```

**Secure session cookies:** Always set `secure: true`, `httpOnly: true`, and `sameSite: "lax"` in production.

## Testing

```javascript
import request from "supertest";

describe("Authentication", () => {
  it("should login with valid credentials", async () => {
    const res = await request(app)
      .post("/auth/login")
      .send({ email: "test@example.com", password: "password123" });
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("user");
  });

  it("should reject invalid credentials", async () => {
    const res = await request(app)
      .post("/auth/login")
      .send({ email: "test@example.com", password: "wrong" });
    expect(res.status).toBe(401);
  });
});
```

Test each strategy independently. Mock external OAuth providers in unit tests (use `nock` to intercept HTTP). For integration tests, use the actual OAuth flow with test credentials or a mock OAuth server.

## Dos
- Use `passport-local` with bcrypt (cost >= 12) for email/password authentication.
- Return generic "Invalid credentials" messages — never reveal whether the email or password was wrong.
- Use `session: false` for API routes to avoid session store overhead.
- Implement rate limiting on login endpoints to prevent brute-force attacks.
- Store sessions in Redis or a database — never use the default in-memory store in production.
- Use separate strategies for different auth methods (local, OAuth, JWT) rather than one mega-strategy.
- Always use HTTPS in production — session cookies and OAuth redirects require TLS.

## Don'ts
- Don't store passwords in plain text — always hash with bcrypt or argon2.
- Don't use the default `MemoryStore` for sessions — it leaks memory and doesn't scale.
- Don't skip CSRF protection for session-based auth routes — forms can be submitted cross-origin.
- Don't trust `req.user` without checking `req.isAuthenticated()` first — it may be undefined.
- Don't hardcode OAuth client secrets in source code — use environment variables.
- Don't use `passport.authenticate` without error handling — the default 401 response lacks context.
- Don't mix session-based and stateless auth on the same routes without clear separation — it causes confusing behavior.
