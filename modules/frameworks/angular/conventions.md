# Angular Framework Conventions
> Support tier: contract-verified
> Framework-specific conventions for Angular 17+ projects. Language idioms are in `modules/languages/typescript.md`. Generic testing patterns are in `modules/testing/vitest.md`.

## Architecture (Feature-Based)

| Layer | Responsibility | Location |
|-------|---------------|----------|
| Page / Route component | Route-level UI, data loading via resolvers | `src/app/features/{feature}/pages/` |
| Feature component | Feature-specific UI + state | `src/app/features/{feature}/components/` |
| Shared component | Reusable UI atoms/molecules | `src/app/shared/components/` |
| Service | Business logic, HTTP, state coordination | `src/app/features/{feature}/{feature}.service.ts` |
| Store | NgRx SignalStore for complex reactive state | `src/app/features/{feature}/{feature}.store.ts` |
| API module | HttpClient wrappers, typed responses | `src/app/core/api/` |
| Type definitions | Shared types/interfaces | `src/app/shared/models/` or co-located |

**Dependency rule:** Shared components never import from feature components. Features import from shared via barrel exports (`index.ts`). Core (services, interceptors, guards) is imported by features only.

## Component Patterns

- **Standalone components** for all new code — no NgModules declarations
- **OnPush change detection** by default — only update when inputs change or signals notify
- Use `inject()` function over constructor injection in all new components and services
- Keep component files under 200 lines — extract sub-components when they have independent state or logic (hard limit 400 lines enforced by check engine)
- Functions max ~30 lines, max 3 nesting levels, max 4 params
- Use `@defer` blocks for lazily rendered UI sections (heavy charts, below-fold content)

```typescript
@Component({
  selector: 'app-user-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule],
  template: `...`
})
export class UserCardComponent {
  user = input.required<User>();
  selected = output<string>();
}
```

## Signals and Reactive State

### When to Use What
- **Component signals** (`signal()`, `computed()`): local UI state, form derived state, ephemeral values
- **NgRx SignalStore**: feature-level state shared across components, complex derived state with side effects
- **`toSignal()`**: bridge Observable streams (HTTP, router events) into signals — preferred over `async` pipe
- **`httpResource()`** (Angular 19+): reactive HTTP fetching bound to signals; replaces manual HttpClient + toSignal patterns
- **Input signals** (`input()`, `input.required()`): typed inputs with automatic change tracking
- **Model signals** (`model()`): two-way bindable inputs for form-like components
- **Output signals** (`output()`): type-safe event emitters

### Anti-Patterns
- Don't use `async` pipe — use `toSignal()` instead; avoids subscription management and works with OnPush
- Don't use `@Input()` / `@Output()` decorators in new code — use `input()` / `output()` signal APIs
- Don't use `ngOnChanges` to react to input changes — use `effect()` watching input signals
- Don't subscribe manually without a destroy mechanism — use `takeUntilDestroyed()` from `@angular/core/rxjs-interop`
- Don't use `Subject` for component-level state — use `signal()` and `computed()`

## Routing (Standalone)

```typescript
// app.routes.ts
export const routes: Routes = [
  {
    path: 'users',
    loadComponent: () => import('./features/users/pages/user-list.page').then(m => m.UserListPage),
  },
  {
    path: 'users/:id',
    loadChildren: () => import('./features/users/users.routes').then(m => m.USER_ROUTES),
    canActivate: [authGuard],
  },
];
```

- Always use `loadComponent` / `loadChildren` for lazy loading — never eager-import feature routes
- Route guards as functions (`canActivate: [authGuard]`), not class-based guards
- Route resolvers for pre-loading data: return signals or observables; accessed via `input()` or `ActivatedRoute`
- Typed router parameters: use `withComponentInputBinding()` in `provideRouter()` to bind route params as inputs

## Naming Conventions

| Artifact | Convention | Example |
|----------|-----------|---------|
| Component | `{feature-name}.component.ts` | `user-card.component.ts` |
| Page component | `{feature-name}.page.ts` | `user-list.page.ts` |
| Service | `{feature-name}.service.ts` | `user.service.ts` |
| Store | `{feature-name}.store.ts` | `user.store.ts` |
| Guard | `{feature-name}.guard.ts` | `auth.guard.ts` |
| Resolver | `{feature-name}.resolver.ts` | `user.resolver.ts` |
| Interceptor | `{feature-name}.interceptor.ts` | `auth.interceptor.ts` |
| Pipe | `{feature-name}.pipe.ts` | `format-date.pipe.ts` |
| Model/Interface | `{feature-name}.model.ts` | `user.model.ts` |

## NgRx SignalStore

```typescript
// user.store.ts
import { signalStore, withState, withComputed, withMethods } from '@ngrx/signals';
import { inject } from '@angular/core';

export const UserStore = signalStore(
  { providedIn: 'root' },
  withState({ users: [] as User[], loading: false, error: null as string | null }),
  withComputed(({ users }) => ({
    activeUsers: computed(() => users().filter(u => u.active)),
  })),
  withMethods((store, userService = inject(UserService)) => ({
    loadUsers: rxMethod<void>(
      switchMap(() => {
        patchState(store, { loading: true });
        return userService.getAll().pipe(
          tap(users => patchState(store, { users, loading: false })),
          catchError(err => { patchState(store, { error: err.message, loading: false }); return EMPTY; })
        );
      })
    ),
  }))
);
```

- Use `patchState` for all state mutations — never mutate state directly
- `withComputed` for derived state — replaces selectors
- `withMethods` for actions/effects — use `rxMethod` for observable-based side effects
- `withHooks` for lifecycle (init, destroy)

## HttpClient Patterns

- Use `HttpClient` via `inject(HttpClient)` in services, never in components
- Typed responses: `this.http.get<User[]>('/api/users')`
- Functional interceptors (Angular 15+): `export function authInterceptor(req: HttpRequest<unknown>, next: HttpHandlerFn)`
- Error handling: `catchError` in service layer; expose error state via signals or store
- Cancel requests on destroy: `takeUntilDestroyed(this.destroyRef)` in services

## Forms

- **Reactive forms** for all forms with validation logic — no template-driven forms in feature code
- Use `FormGroup<{ field: FormControl<Type> }>` for strict typing (Angular 14+)
- Validators as pure functions — no class-based validators
- Signal integration: `toSignal(this.form.valueChanges)` for reactive form value consumption

## Animation & Motion

Reference `shared/frontend-design-theory.md` for design theory guardrails.

### Library Preference
- **Route transitions and enter/leave**: Angular Animations (`@angular/animations`) — `trigger`, `transition`, `animate`, `state`
- **Component micro-interactions**: CSS transitions with Angular class bindings
- **Complex sequences** (scroll-driven, orchestrated): GSAP with DestroyRef cleanup

### Timing Standards
- Instant feedback (button press, toggle): < 100ms
- Micro-interaction (hover, tooltip): 150-200ms
- UI transition (panel open, element reveal): 200-350ms
- Route transition: 300-500ms total

### Performance Rules
- Only animate `transform` and `opacity` — GPU-composited, no layout recalc
- Use `will-change` sparingly — remove after animation
- Target 60fps — simplify or remove if jank occurs

### Accessibility
- REQUIRED: All animations must respect `prefers-reduced-motion`
- Use `@media (prefers-reduced-motion: reduce)` for CSS animations
- Never use animation as the only indicator of state change

## Multi-Viewport Design

### Breakpoints
- Mobile: 375px (iPhone SE baseline)
- Tablet: 768px
- Desktop: 1280px
- Wide: 1536px+ (optional)

### Responsive Strategy
- Use Angular CDK `BreakpointObserver` via `inject(BreakpointObserver)` for programmatic breakpoint detection
- CSS container queries preferred over media queries for component-level responsiveness
- `@angular/cdk/layout` `Breakpoints.Handset` / `Breakpoints.Tablet` / `Breakpoints.Web` constants

### Mobile Requirements (375px)
- Touch targets: minimum 44x44px
- Single-column reflow — no horizontal scrolling
- Font size: minimum 16px body text (prevents iOS zoom on focus)

## Security

- Sanitize content via Angular's `DomSanitizer` — never bypass with `bypassSecurityTrustHtml` unless necessary
- Validate all user input before submission
- Never store tokens in `localStorage` — use memory or `sessionStorage`
- HttpClient adds XSRF token automatically via `withXsrfConfiguration()`

## Performance

### Rendering
- OnPush is default — avoid calling impure functions in templates
- Use `trackBy` on all `*ngFor` / `@for` loops
- Virtualize long lists with CDK Virtual Scroll (`@angular/cdk/scrolling`)
- `@defer` for below-fold and heavy components: `@defer (on viewport) { <HeavyChart /> }`

### Bundle
- Target <200KB initial JS
- `loadComponent` / `loadChildren` for all feature routes (code splitting)
- Tree-shake: named imports only, avoid barrel re-exports in shared when not needed

## Testing

### Test Framework
- **Vitest** (via Analog / analog-vitest) or **Karma + Jasmine** (Angular CLI default) for unit tests
- **Angular Testing Library** (`@testing-library/angular`) for component tests — prefer over TestBed raw
- **`TestBed.configureTestingModule`** for service/store tests; `provideHttpClientTesting` for HTTP isolation
- **Angular CDK Harnesses** (`HarnessLoader`) for Material component interaction in tests
- **Playwright** for end-to-end tests

### Integration Test Patterns
- Render components with `render()` from `@testing-library/angular`
- Provide services via `TestBed` providers or `render({ providers: [...] })`
- Mock HTTP with `provideHttpClientTesting` + `HttpTestingController`
- Test stores in isolation: provide real `SignalStore`, mock only the service dependency
- Test user flows end-to-end within a page: fill form, submit, verify success/error UI

### What to Test
- User-visible behavior: what the user sees and can interact with
- Conditional rendering based on signal state (loading, error, empty, populated)
- Form validation and submission flows
- Route guard logic: authenticated vs unauthenticated state

### What NOT to Test
- Angular change detection internals (that OnPush updates)
- Signal graph internals — test the output, not that `computed()` runs
- Third-party library behavior (that `HttpClient` makes requests)
- CSS classes or styling details — test visible outcomes instead

### Example Test Structure
```
src/app/features/{feature}/
  components/
    user-card.component.ts
    user-card.component.spec.ts   # co-located unit test
  pages/
    user-list.page.ts
    user-list.page.spec.ts        # integration test
src/testing/
  setup.ts                        # global test setup
  test-providers.ts               # shared provider factories
```

For general Vitest patterns, see `modules/testing/vitest.md`.

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Smart Test Rules

- No duplicate tests — grep existing tests before generating
- Test behavior, not implementation
- Skip framework guarantees (don't test Angular renders, signal graph)
- One assertion focus per it() — multiple asserts OK if same behavior

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated modules, changing service injection contracts, restructuring NgRx store.

## Dos and Don'ts

### Do
- Use standalone components with `ChangeDetectionStrategy.OnPush` for all new components
- Use `inject()` function instead of constructor injection for cleaner, tree-shakeable code
- Use signal APIs: `input()`, `output()`, `model()`, `signal()`, `computed()`, `effect()`
- Use `toSignal()` to convert Observables to signals — eliminates manual subscription management
- Use `takeUntilDestroyed()` for any remaining Observable subscriptions in services
- Use `@defer` for lazily rendering heavy or below-fold UI sections
- Use `loadComponent` / `loadChildren` for all route-level code splitting
- Use functional guards and interceptors — no class-based guards in new code
- Use `trackBy` (or `track` in `@for`) for all list rendering

### Don't
- Don't create NgModules for new features — use standalone component imports
- Don't use `@Input()` / `@Output()` decorators — prefer `input()` / `output()` signal APIs
- Don't use `async` pipe — use `toSignal()` instead
- Don't subscribe to Observables without a destroy mechanism (`takeUntilDestroyed`, `toSignal`)
- Don't call `.subscribe()` directly in components — delegate to stores or services
- Don't use `ngOnChanges` — react to input signal changes with `effect()`
- Don't bypass Angular's DomSanitizer without understanding XSS implications
- Don't use class-based route guards or interceptors in new code
