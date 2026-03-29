# Angular Documentation Conventions

> Extends `modules/documentation/conventions.md` with Angular-specific patterns.

## Code Documentation

- Use TSDoc (`/** */`) for all exported components, services, directives, pipes, and signals-based stores.
- Components: document `@Input()` and `@Output()` properties. Use TSDoc `@param`-style on `input()` and `output()` signal factories.
- Services: document public methods with preconditions, return values, and side effects (HTTP calls, state mutations).
- NgRx SignalStore features (`withMethods`, `withState`): document the exposed state shape and each method's mutation contract.
- Pipes: document the transform logic, accepted input types, and any arguments.

```typescript
/**
 * Displays an athlete's session history with pagination.
 *
 * @example
 * <app-session-list [athleteId]="selectedAthleteId" (sessionSelected)="onSelect($event)" />
 */
@Component({ ... })
export class SessionListComponent {
  /** ID of the athlete whose sessions are displayed. */
  athleteId = input.required<string>();

  /** Emitted when the user selects a session row. */
  sessionSelected = output<SessionId>();
}
```

## Architecture Documentation

- Document the module / standalone component structure for the feature area.
- Document lazy-loaded routes: which routes are lazy, which feature module they load, and their entry components.
- Document the NgRx SignalStore layout: which stores exist, what state they hold, and which components consume them.
- Dependency injection: document custom `InjectionToken` declarations and their providers.
- Document OnPush change detection strategy — it is the default, but document components that deviate and why.

## Diagram Guidance

- **Feature module map:** Mermaid flowchart showing lazy-loaded routes and their feature modules.
- **Signal data flow:** Sequence diagram for complex derived signal computations.

## Dos

- TSDoc on all `input()` and `output()` signal factories — they are the component's public API
- Document `InjectionToken` at the declaration site — injection tokens are invisible without explicit docs
- Document router guards: what condition they check and where they redirect on failure

## Don'ts

- Don't document Angular lifecycle hooks unless the implementation is non-standard
- Don't skip `@Output` documentation — event names like `clicked` are ambiguous without context
