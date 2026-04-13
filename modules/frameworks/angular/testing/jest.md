# Angular + Jest Testing Conventions

## Test Structure

- Co-locate tests: `component.spec.ts` next to `component.ts`
- Shared test utilities: `testing/` directory at module level
- Use `describe` for class name, `it` for method/behavior

## Component Testing

- Use `TestBed.configureTestingModule()` for component setup
- Prefer component harnesses (`ComponentHarness`) over direct DOM queries
- `fixture.detectChanges()` after setup and before assertions
- Use `fakeAsync` + `tick()` for async operations
- Override providers with `TestBed.overrideProvider()` for mocking

## Service Testing

- Create service directly: `service = TestBed.inject(MyService)`
- Mock HttpClient with `HttpClientTestingModule`
- Use `HttpTestingController` to assert and flush requests
- Test error handling: `req.flush('error', { status: 500, statusText: 'Error' })`

## Pipe and Directive Testing

- Test pipes as pure functions: `expect(pipe.transform(input)).toBe(expected)`
- Test directives via host component with `@Component({ template: '...' })`

## Signal and Standalone Testing

- Standalone components: import directly in `TestBed.configureTestingModule({ imports: [MyComponent] })`
- Signals: read with `component.mySignal()`, set with `fixture.componentRef.setInput('name', value)`
- Use `TestBed.flushEffects()` for effect assertions

## Mocking

- Jasmine spies: `spyOn(service, 'method').and.returnValue(of(result))`
- Auto-mock with `jest.mock()` for external modules
- Provide mock services via `{ provide: RealService, useValue: mockService }`

## Dos

- Use component harnesses for reliable DOM interaction
- Test OnPush components with `fixture.detectChanges()` after input changes
- Test async pipes with `fakeAsync` + `tick`
- Verify unsubscription in `ngOnDestroy`
- Test standalone component imports explicitly

## Don'ts

- Don't query DOM with `nativeElement.querySelector` directly (use harnesses)
- Don't test Angular internals (change detection, lifecycle hooks)
- Don't import entire modules when testing standalone components
- Don't use real HTTP in unit tests
- Don't test template bindings separately from component logic
