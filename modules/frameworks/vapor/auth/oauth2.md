# OAuth2 / JWT with Vapor

## Integration Setup

```swift
// Package.swift
.package(url: "https://github.com/vapor/jwt.git", from: "4.2.2"),
// targets:
.product(name: "JWT", package: "jwt"),
```

```swift
// configure.swift
// HMAC (symmetric)
await app.jwt.keys.add(hmac: "secret", digestAlgorithm: .sha256)
// RS256 (asymmetric — preferred for production)
let privateKey = try RSAKey.private(pem: Environment.get("JWT_PRIVATE_KEY")!)
await app.jwt.keys.add(rsa: privateKey, digestAlgorithm: .sha256)
```

## Framework-Specific Patterns

### JWTPayload
```swift
struct AccessTokenPayload: JWTPayload {
    var subject:    SubjectClaim           // "sub" — user ID
    var expiration: ExpirationClaim        // "exp"
    var issuer:     IssuerClaim            // "iss"
    var roles:      [String]

    func verify(using signer: JWTSigner) throws {
        try expiration.verifyNotExpired()
        guard issuer.value == "my-app" else { throw JWTError.claimVerificationFailure(failedClaim: issuer, reason: "invalid issuer") }
    }
}
```

### Issuing Tokens
```swift
let payload = AccessTokenPayload(
    subject:    .init(value: user.id!.uuidString),
    expiration: .init(value: Date().addingTimeInterval(900)),   // 15 min
    issuer:     .init(value: "my-app"),
    roles:      user.roles
)
let token = try req.jwt.sign(payload)
```

### Middleware Guard
```swift
struct JWTMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let payload = try req.jwt.verify(as: AccessTokenPayload.self)
        req.storage[AccessTokenPayloadKey.self] = payload
        return try await next.respond(to: req)
    }
}

// Route protection
let protected = app.grouped(JWTMiddleware())
protected.get("profile") { req in /* ... */ }
```

### JWKS (public key distribution for resource servers)
```swift
app.get(".well-known", "jwks.json") { req async throws in
    try await req.application.jwt.keys.jwks()
}
```

## Scaffolder Patterns

```yaml
patterns:
  payload:    "Sources/App/Auth/{Name}Payload.swift"
  middleware: "Sources/App/Middleware/JWTMiddleware.swift"
  controller: "Sources/App/Controllers/AuthController.swift"
```

## Additional Dos/Don'ts

- DO use RS256 asymmetric keys in production; HMAC is only acceptable for single-service tokens
- DO set short `exp` (15 min) for access tokens; use separate refresh tokens stored server-side
- DO verify `iss`, `aud`, and `exp` claims in every `verify()` implementation
- DO rotate signing keys; expose JWKS endpoint for downstream services
- DON'T store sensitive data in JWT payload — it is base64-encoded, not encrypted
- DON'T implement custom crypto; use Vapor's `jwt` package which wraps Swift Crypto
- DON'T accept tokens without verifying the signing algorithm (`alg: none` attack)
