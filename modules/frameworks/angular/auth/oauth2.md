# Angular + OAuth2 / OIDC (angular-auth-oidc-client)

> Angular-specific patterns for OIDC-based auth via `angular-auth-oidc-client`. Extends Angular conventions.

## Integration Setup

```bash
npm install angular-auth-oidc-client
```

```typescript
// src/app/auth/auth.config.ts
import { PassedInitialConfig } from 'angular-auth-oidc-client';

export const authConfig: PassedInitialConfig = {
  config: {
    authority: 'https://your-idp.example.com',
    redirectUrl: `${window.location.origin}/auth/callback`,
    postLogoutRedirectUri: window.location.origin,
    clientId: 'your-client-id',
    scope: 'openid profile email offline_access',
    responseType: 'code',
    silentRenew: true,
    useRefreshToken: true,
    secureRoutes: ['/api'],  // automatically attach tokens to these URL prefixes
  },
};
```

```typescript
// app.config.ts
import { provideAuth } from 'angular-auth-oidc-client';
import { authConfig } from './auth/auth.config';

export const appConfig: ApplicationConfig = {
  providers: [
    provideAuth(authConfig),
    provideHttpClient(withInterceptors([authInterceptor])),
    provideRouter(routes, withComponentInputBinding()),
  ],
};
```

## OidcSecurityService Usage

```typescript
// src/app/auth/auth.store.ts — NgRx SignalStore wrapping OidcSecurityService
import { signalStore, withState, withMethods, withComputed } from '@ngrx/signals';
import { inject } from '@angular/core';
import { OidcSecurityService } from 'angular-auth-oidc-client';
import { toSignal } from '@angular/core/rxjs-interop';

export const AuthStore = signalStore(
  { providedIn: 'root' },
  withState({ isAuthenticated: false, userData: null as UserProfile | null }),
  withMethods((store, oidc = inject(OidcSecurityService)) => ({
    login(): void {
      oidc.authorize();
    },
    logout(): void {
      oidc.logoff().subscribe();
    },
    checkAuth(): void {
      oidc.checkAuth().subscribe(({ isAuthenticated, userData }) => {
        patchState(store, { isAuthenticated, userData });
      });
    },
    getAccessToken(): string | null {
      return oidc.getAccessToken() ?? null;
    },
  })),
  withComputed(({ isAuthenticated, userData }) => ({
    displayName: computed(() => userData()?.name ?? 'Guest'),
    isLoggedIn: computed(() => isAuthenticated()),
  }))
);
```

## Auth Guard (Functional)

```typescript
// src/app/auth/auth.guard.ts
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthStore } from './auth.store';

export const authGuard: CanActivateFn = () => {
  const authStore = inject(AuthStore);
  const router = inject(Router);

  if (authStore.isLoggedIn()) return true;
  return router.createUrlTree(['/login']);
};
```

```typescript
// app.routes.ts
export const routes: Routes = [
  {
    path: 'dashboard',
    loadComponent: () => import('./features/dashboard/dashboard.page').then(m => m.DashboardPage),
    canActivate: [authGuard],
  },
  {
    path: 'auth/callback',
    loadComponent: () => import('./auth/callback.page').then(m => m.CallbackPage),
  },
];
```

## OIDC Callback Page

```typescript
// src/app/auth/callback.page.ts
import { Component, OnInit, inject } from '@angular/core';
import { Router } from '@angular/router';
import { OidcSecurityService } from 'angular-auth-oidc-client';

@Component({
  standalone: true,
  template: `<p>Completing sign in...</p>`,
})
export class CallbackPage implements OnInit {
  private oidc = inject(OidcSecurityService);
  private router = inject(Router);

  ngOnInit(): void {
    this.oidc.checkAuth().subscribe(({ isAuthenticated }) => {
      this.router.navigate([isAuthenticated ? '/dashboard' : '/login']);
    });
  }
}
```

## Token Interceptor

```typescript
// src/app/core/interceptors/auth.interceptor.ts
import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthStore } from '../../auth/auth.store';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authStore = inject(AuthStore);
  const token = authStore.getAccessToken();

  if (!token || !req.url.startsWith('/api')) return next(req);

  return next(req.clone({
    setHeaders: { Authorization: `Bearer ${token}` },
  }));
};
```

## App Initialization

```typescript
// src/app/app.component.ts — check auth on app startup
import { Component, OnInit, inject } from '@angular/core';
import { AuthStore } from './auth/auth.store';

@Component({
  selector: 'app-root',
  standalone: true,
  template: `<router-outlet />`,
  imports: [RouterOutlet],
})
export class AppComponent implements OnInit {
  private authStore = inject(AuthStore);

  ngOnInit(): void {
    this.authStore.checkAuth();
  }
}
```

## Scaffolder Patterns

```
src/app/
  auth/
    auth.config.ts            # OidcSecurityService configuration
    auth.store.ts             # NgRx SignalStore wrapping OIDC service
    auth.guard.ts             # functional route guard
    callback.page.ts          # OIDC redirect callback component
  core/
    interceptors/
      auth.interceptor.ts     # token-attaching functional interceptor
```

## Dos

- Use `secureRoutes` in `authConfig` to automatically attach tokens by URL prefix
- Wrap `OidcSecurityService` in an `AuthStore` — expose typed signals, not raw observables
- Use `useRefreshToken: true` + `silentRenew: true` for seamless token refresh
- Clean up URL after OIDC redirect: `oidc.checkAuth()` handles code/state removal automatically
- Use functional `canActivate` guards — no class-based guards in new code

## Don'ts

- Don't call `oidc.getAccessToken()` in templates — access via `AuthStore` signals only
- Don't store tokens in `localStorage` — `angular-auth-oidc-client` uses `sessionStorage` by default; leave it
- Don't expose `client_secret` — Angular SPAs use PKCE flow without a secret
- Don't bypass `authGuard` by checking `isAuthenticated` in the component constructor — guards run first
- Don't use class-based `CanActivate` guards — use functional guard syntax
