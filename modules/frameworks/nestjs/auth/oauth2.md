# NestJS + OAuth2 / JWT (Passport)

> NestJS-specific patterns for JWT-based auth with `@nestjs/passport`, `passport-jwt`, and JWKS.
> Extends generic NestJS conventions.

## Integration Setup

```bash
npm install @nestjs/passport passport passport-jwt jwks-rsa @nestjs/jwt
npm install -D @types/passport-jwt
```

## AuthModule

```typescript
// auth/auth.module.ts
@Module({
  imports: [
    JwtModule.registerAsync({
      global: true,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>('JWT_SECRET'),
        signOptions: { expiresIn: '1h' },
      }),
    }),
    PassportModule.register({ defaultStrategy: 'jwt' }),
  ],
  providers: [JwtStrategy, AuthService],
  exports: [AuthService],
})
export class AuthModule {}
```

## JWT Strategy (JWKS or Symmetric)

### Symmetric (internal services)
```typescript
// auth/strategies/jwt.strategy.ts
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('JWT_SECRET'),
    });
  }

  async validate(payload: JwtPayload): Promise<AuthUser> {
    return { userId: payload.sub, email: payload.email, role: payload.role };
  }
}
```

### JWKS (external IdP: Auth0, Keycloak)
```typescript
@Injectable()
export class JwksStrategy extends PassportStrategy(Strategy, 'jwks') {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      audience: config.get<string>('OAUTH2_AUDIENCE'),
      issuer: config.get<string>('OAUTH2_ISSUER'),
      algorithms: ['RS256'],
      secretOrKeyProvider: jwksRsa.passportJwtSecret({
        cache: true,
        rateLimit: true,
        jwksRequestsPerMinute: 5,
        jwksUri: `${config.get('OAUTH2_ISSUER')}/.well-known/jwks.json`,
      }),
    });
  }

  async validate(payload: JwtPayload): Promise<AuthUser> {
    return { userId: payload.sub, email: payload.email, role: payload.role };
  }
}
```

## Global Auth Guard with @Public() Escape Hatch

```typescript
// auth/decorators/public.decorator.ts
export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

// auth/guards/jwt-auth.guard.ts
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private reflector: Reflector) {
    super();
  }

  canActivate(context: ExecutionContext): boolean | Promise<boolean> | Observable<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;
    return super.canActivate(context);
  }
}
```

Register globally:
```typescript
// app.module.ts
{
  provide: APP_GUARD,
  useClass: JwtAuthGuard,
}
```

## Role-Based Access Control

```typescript
// auth/decorators/roles.decorator.ts
export const Roles = (...roles: Role[]) => SetMetadata('roles', roles);

// auth/guards/roles.guard.ts
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<Role[]>('roles', [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!requiredRoles) return true;
    const { user } = context.switchToHttp().getRequest<Request>();
    return requiredRoles.includes((user as AuthUser).role);
  }
}
```

Usage:
```typescript
@Get('admin/stats')
@Roles(Role.ADMIN)
adminStats() { ... }

@Get('health')
@Public()
healthCheck() { ... }
```

## Request Typing

Extend Express `Request` to avoid `as any` casts:
```typescript
// types/express.d.ts
declare global {
  namespace Express {
    interface User extends AuthUser {}
  }
}
```

Then in controllers: `const user = req.user` is typed as `AuthUser`.

## Token Refresh Pattern

```typescript
// auth/auth.service.ts
async refreshTokens(refreshToken: string): Promise<TokenPair> {
  const payload = await this.jwtService.verifyAsync(refreshToken, {
    secret: this.config.get('JWT_REFRESH_SECRET'),
  });
  const user = await this.usersService.findOne(payload.sub);
  if (!user) throw new UnauthorizedException();
  return this.generateTokens(user);
}
```

## Scaffolder Patterns

```
src/
  auth/
    auth.module.ts
    auth.service.ts
    strategies/
      jwt.strategy.ts
    guards/
      jwt-auth.guard.ts
      roles.guard.ts
    decorators/
      public.decorator.ts
      roles.decorator.ts
  types/
    express.d.ts             # Request.user type augmentation
```

## Dos

- Register `JwtAuthGuard` globally with `APP_GUARD` — opt-out with `@Public()` rather than opt-in
- Register `RolesGuard` globally with `APP_GUARD` — define roles with `@Roles()` decorator
- Use `@nestjs/config` `ConfigService` for all secrets — never hardcode `JWT_SECRET`
- Validate `aud` and `iss` in JWKS strategy — never rely on signature alone
- Extend Express `Request` interface to avoid `(req.user as any)` casts in controllers

## Don'ts

- Don't use `HS256` with a shared secret for public-facing APIs — use JWKS/RS256 with an IdP
- Don't store the raw JWT payload in the database session — store only `userId` / `sub`
- Don't place `@UseGuards(JwtAuthGuard)` on every controller — use global registration instead
- Don't skip `rateLimit: true` on the JWKS client — unthrottled fetches can trigger IdP rate limits
