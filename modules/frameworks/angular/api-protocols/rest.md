# Angular + HttpClient REST — API Protocol Binding

## Integration Setup

- Use `provideHttpClient(withInterceptors([authInterceptor, errorInterceptor]))` in `app.config.ts`
- Create typed API services via `inject(HttpClient)` — one service per resource domain
- Functional interceptors (Angular 15+): no class-based interceptors in new code

```typescript
// app.config.ts
import { provideHttpClient, withInterceptors } from '@angular/common/http';

export const appConfig: ApplicationConfig = {
  providers: [
    provideHttpClient(withInterceptors([authInterceptor, errorInterceptor])),
    provideRouter(routes, withComponentInputBinding()),
  ],
};
```

## Functional Interceptors

```typescript
// src/app/core/interceptors/auth.interceptor.ts
import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthStore } from '../auth/auth.store';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authStore = inject(AuthStore);
  const token = authStore.accessToken();

  if (!token) return next(req);

  return next(req.clone({
    setHeaders: { Authorization: `Bearer ${token}` },
  }));
};
```

## Typed API Services

```typescript
// src/app/features/users/users.api.ts
import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class UsersApiService {
  private http = inject(HttpClient);
  private baseUrl = '/api/users';

  list(filters?: UserFilters): Observable<User[]> {
    return this.http.get<User[]>(this.baseUrl, { params: filters as Record<string, string> });
  }

  getById(id: string): Observable<User> {
    return this.http.get<User>(`${this.baseUrl}/${id}`);
  }

  create(payload: CreateUserDto): Observable<User> {
    return this.http.post<User>(this.baseUrl, payload);
  }

  update(id: string, payload: UpdateUserDto): Observable<User> {
    return this.http.put<User>(`${this.baseUrl}/${id}`, payload);
  }

  delete(id: string): Observable<void> {
    return this.http.delete<void>(`${this.baseUrl}/${id}`);
  }
}
```

## Signal Integration with httpResource (Angular 19+)

```typescript
// Angular 19+: reactive HTTP fetching bound to signals
import { httpResource } from '@angular/core';

@Component({ ... })
export class UserListComponent {
  searchQuery = signal('');

  usersResource = httpResource<User[]>(() => ({
    url: '/api/users',
    params: { q: this.searchQuery() },
  }));

  // Derived signals
  users = this.usersResource.value;
  loading = this.usersResource.isLoading;
  error = this.usersResource.error;
}
```

## Signal Integration with toSignal (Angular 16-18)

```typescript
// Pre-Angular 19: bridge Observable to signal
import { toSignal } from '@angular/core/rxjs-interop';
import { switchMap } from 'rxjs/operators';

@Component({ ... })
export class UserListComponent {
  private usersApi = inject(UsersApiService);
  searchQuery = signal('');

  users = toSignal(
    toObservable(this.searchQuery).pipe(
      debounceTime(300),
      switchMap(q => this.usersApi.list({ q }))
    ),
    { initialValue: [] }
  );
}
```

## Error Handling Interceptor

```typescript
// src/app/core/interceptors/error.interceptor.ts
import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, throwError } from 'rxjs';
import { NotificationService } from '../services/notification.service';

export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  const notifications = inject(NotificationService);

  return next(req).pipe(
    catchError(err => {
      if (err.status === 401) {
        // Handled by auth guard / redirect
      } else if (err.status >= 500) {
        notifications.error('An unexpected server error occurred. Please try again.');
      }
      return throwError(() => err);
    })
  );
};
```

## Scaffolder Patterns

```
src/app/
  core/
    interceptors/
      auth.interceptor.ts         # token attachment
      error.interceptor.ts        # global error handling
    api/
      api.types.ts                # shared request/response types
  features/{feature}/
    {feature}.api.ts              # resource-specific HttpClient service
    {feature}.store.ts            # NgRx SignalStore consuming the API service
```

## Dos

- Type all `HttpClient` calls with a generic: `http.get<User[]>('/api/users')`
- Use functional interceptors — compose multiple as an array in `withInterceptors([])`
- Handle loading, error, and empty states for every resource in the store or component
- Use `takeUntilDestroyed(destroyRef)` for subscriptions not bridged with `toSignal()`
- Prefer `httpResource()` (Angular 19+) for component-level fetching — eliminates boilerplate

## Don'ts

- Don't call `HttpClient` directly from components — delegate to a typed API service
- Don't use class-based `HttpInterceptor` in new code — use functional interceptors
- Don't ignore error states — surface them as signals and handle in the template
- Don't use `HttpClientModule` — use `provideHttpClient()` in `app.config.ts`
