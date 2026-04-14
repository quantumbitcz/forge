# Angular + TypeScript Variant

> TypeScript-specific patterns for Angular projects. Extends `modules/languages/typescript.md` and `modules/frameworks/angular/conventions.md`.

## TypeScript Configuration

Angular requires `strict: true` — this enables all strict checks:

```json
// tsconfig.json (required settings)
{
  "compilerOptions": {
    "strict": true,
    "strictNullChecks": true,
    "noImplicitAny": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "exactOptionalPropertyTypes": true,
    "useDefineForClassFields": false
  }
}
```

Recommended additions:
- `"paths"` for `@app/*`, `@core/*`, `@shared/*` path aliases
- `"moduleResolution": "bundler"` for Vite-based builds (Analog)

## Component Typing

- Type component class fields explicitly when inference isn't obvious
- Use `InputSignal<T>` and `InputRequiredSignal<T>` return types from `input()` when needed for documentation
- `OutputEmitterRef<T>` for `output()` return type

```typescript
import { Component, input, output, model, computed, ChangeDetectionStrategy } from '@angular/core';

interface UserCardProps {
  user: User;
  selected?: boolean;
}

@Component({
  selector: 'app-user-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `...`,
})
export class UserCardComponent {
  user = input.required<User>();
  selected = input(false);       // optional with default
  selectUser = output<string>(); // typed event
  expanded = model(false);       // two-way bindable

  displayName = computed(() => `${this.user().firstName} ${this.user().lastName}`);
}
```

## Service Typing

- Return `Observable<T>` from API services — explicit type annotation required
- Return `Signal<T>` from store computed properties
- Type `inject()` result via generic: `inject<UserService>(UserService)` when type can't be inferred

```typescript
@Injectable({ providedIn: 'root' })
export class UserService {
  private http = inject(HttpClient);

  getById(id: string): Observable<User> {
    return this.http.get<User>(`/api/users/${id}`);
  }
}
```

## Store Typing (NgRx SignalStore)

```typescript
import { signalStore, withState, withComputed } from '@ngrx/signals';

type UserState = {
  users: User[];
  selectedId: string | null;
  loading: boolean;
  error: string | null;
};

const initialState: UserState = {
  users: [],
  selectedId: null,
  loading: false,
  error: null,
};

export const UserStore = signalStore(
  withState<UserState>(initialState),
  withComputed(({ users, selectedId }) => ({
    selectedUser: computed(() => users().find(u => u.id === selectedId()) ?? null),
    count: computed(() => users().length),
  }))
);
```

## Discriminated Unions for Async State

```typescript
type AsyncState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: string };

// Usage in component signal
resourceState = signal<AsyncState<User[]>>({ status: 'idle' });
```

## Route and Resolver Typing

```typescript
// Typed resolver
export const userResolver: ResolveFn<User> = (route) => {
  const service = inject(UserService);
  return service.getById(route.paramMap.get('id')!);
};

// Accessing resolved data as input (withComponentInputBinding)
@Component({ ... })
export class UserDetailPage {
  user = input.required<User>(); // bound from resolver via route input binding
}
```

## Guard Typing

```typescript
import { CanActivateFn, CanMatchFn } from '@angular/router';

export const authGuard: CanActivateFn = (route, state): boolean | UrlTree => {
  const authStore = inject(AuthStore);
  const router = inject(Router);

  if (authStore.isLoggedIn()) return true;
  return router.createUrlTree(['/login'], { queryParams: { returnUrl: state.url } });
};
```

## Path Aliases

Configure in `tsconfig.json` and `vite.config.ts` (for Analog) or `angular.json`:

```json
{
  "paths": {
    "@app/*": ["src/app/*"],
    "@core/*": ["src/app/core/*"],
    "@shared/*": ["src/app/shared/*"],
    "@features/*": ["src/app/features/*"]
  }
}
```

Import order with aliases:
1. `@angular/*` framework imports
2. Third-party (`@ngrx/*`, `rxjs`, etc.)
3. `@core/*` (services, interceptors, guards)
4. `@shared/*` (components, pipes, directives)
5. `@features/*` or relative `./` imports

## Strict Mode Rules

- `strict: true` in tsconfig — no exceptions
- No `any` type — use `unknown` and narrow with type guards or `zod` validation
- No `as` type assertions unless narrowing from `unknown` or DOM types
- No non-null assertion (`!`) on values that could legitimately be null/undefined — handle the null case
- TSDoc on all exported services, stores, and public component APIs (what + why, not how)

## Standalone Components (Angular 17+)

All components are `standalone: true` (default in Angular 17+). No NgModule declarations -- components import their own dependencies.

```typescript
@Component({
  selector: 'app-user-profile',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, UserAvatarComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `...`,
})
export class UserProfileComponent {
  // ...
}
```

Use `importProvidersFrom()` for module-based libraries in `app.config.ts`.

## Built-in Control Flow (Angular 17+)

Use `@if`, `@for`, `@switch` instead of `*ngIf`, `*ngFor`, `*ngSwitch`:

```html
@if (user()) {
  <app-user-card [user]="user()" />
} @else {
  <app-login-prompt />
}

@for (item of items(); track item.id) {
  <app-list-item [item]="item" />
} @empty {
  <p>No items found.</p>
}
```

`@for` requires a `track` expression.

## Deferred Loading

Use `@defer` for heavy components to reduce initial bundle size:

```html
@defer (on viewport) {
  <app-heavy-chart [data]="chartData()" />
} @placeholder {
  <app-chart-skeleton />
}
```

## Provider Configuration

Use functional providers instead of NgModules:

```typescript
// app.config.ts
export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor, loggingInterceptor])),
    provideAnimationsAsync(),
  ],
};
```

## Dos

- Use `inject()` function instead of constructor injection
- Use `OnPush` change detection strategy on all components
- Use `provideHttpClient(withInterceptors([...]))` not `HttpClientModule`
- Defer heavy components with `@defer`

## Don'ts

- Don't create NgModules for new code
- Don't use `*ngIf` / `*ngFor` / `*ngSwitch` -- use built-in control flow
- Don't use `@Input()` / `@Output()` decorators -- use signal-based `input()` / `output()`
- Don't use `BehaviorSubject` for component-level state -- use signals
- Don't use class-based route guards
