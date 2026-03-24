# Express + OAuth2 / JWT (passport-jwt / jose)

> Express-specific patterns for JWT-based auth with passport-jwt and JWKS validation. Extends generic Express conventions.

## Integration Setup

```bash
npm install passport passport-jwt jose jwks-rsa
npm install --save-dev @types/passport @types/passport-jwt
```

## Framework-Specific Patterns

### JWKS-backed passport-jwt strategy

```typescript
// src/auth/passport.ts
import passport from "passport";
import { Strategy as JwtStrategy, ExtractJwt } from "passport-jwt";
import jwksRsa from "jwks-rsa";

passport.use(
  new JwtStrategy(
    {
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      audience: process.env.OAUTH2_AUDIENCE,
      issuer: process.env.OAUTH2_ISSUER,
      algorithms: ["RS256"],
      secretOrKeyProvider: jwksRsa.passportJwtSecret({
        cache: true,
        rateLimit: true,
        jwksRequestsPerMinute: 5,
        jwksUri: `${process.env.OAUTH2_ISSUER}/.well-known/jwks.json`,
      }),
    },
    (payload, done) => done(null, payload)
  )
);
```

### Middleware chain

```typescript
// src/auth/middleware.ts
import passport from "passport";
import { Request, Response, NextFunction } from "express";

export const authenticate = passport.authenticate("jwt", { session: false });

export function requireScope(...scopes: string[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    const userScopes: string[] = (req.user as any)?.scope?.split(" ") ?? [];
    const missing = scopes.filter((s) => !userScopes.includes(s));
    if (missing.length > 0) {
      return res.status(403).json({ error: `Missing scopes: ${missing.join(", ")}` });
    }
    next();
  };
}
```

### Token validation with jose (JWKS, no passport)

```typescript
// src/auth/jwt.ts — lightweight alternative without passport
import { createRemoteJWKSet, jwtVerify } from "jose";

const JWKS = createRemoteJWKSet(
  new URL(`${process.env.OAUTH2_ISSUER}/.well-known/jwks.json`)
);

export async function verifyToken(token: string) {
  const { payload } = await jwtVerify(token, JWKS, {
    issuer: process.env.OAUTH2_ISSUER,
    audience: process.env.OAUTH2_AUDIENCE,
  });
  return payload;
}
```

### Protected routes

```typescript
// src/routes/users.ts
import { authenticate, requireScope } from "../auth/middleware";

router.get("/me", authenticate, (req, res) => {
  res.json({ sub: (req.user as any).sub });
});

router.delete("/admin/users/:id", authenticate, requireScope("admin"), userController.delete);
```

## Scaffolder Patterns

```
src/
  auth/
    passport.ts           # passport-jwt strategy + JWKS config
    middleware.ts         # authenticate, requireScope
    jwt.ts                # jose jwtVerify (lightweight path)
  app.ts                  # passport.initialize() registration
```

## Dos

- Use `jwks-rsa` caching to avoid JWKS fetch on every request — default cache is 10 minutes
- Validate `aud` and `iss` in strategy options — never rely on signature alone
- Use `{ session: false }` in `passport.authenticate` for stateless JWT APIs
- Propagate typed user via Express `Request` augmentation (`declare global { namespace Express { interface User {...} } }`)

## Don'ts

- Don't use `HS256` with a shared secret for public-facing APIs — use JWKS/RS256
- Don't place `passport.authenticate` in global middleware — apply per-router for clarity
- Don't expose the raw JWT payload in API responses — project only the fields the client needs
- Don't skip `rateLimit: true` on the JWKS client — unthrottled JWKS fetches can trigger IdP rate limits
