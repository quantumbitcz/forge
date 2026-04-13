# Vue + Vitest Testing Conventions

## Test Structure

- Co-locate tests: `Component.test.ts` next to `Component.vue`
- Use `describe` matching component name
- Name tests by user-visible behavior

## Component Testing

- Mount via `mount()` or `shallowMount()` from `@vue/test-utils`
- Prefer `mount` for integration, `shallowMount` for isolation
- Use `wrapper.find('[data-testid="..."]')` only when semantic queries unavailable
- `await wrapper.vm.$nextTick()` after state changes
- Use `flushPromises()` for async operations

## Composable Testing

- Test composables in isolation with test wrapper component
- Or use `withSetup()` helper pattern for simple composables
- Test reactive refs: change input, assert output updates

## Pinia Store Testing

- Use `createTestingPinia()` from `@pinia/testing`
- Override initial state: `createTestingPinia({ initialState: { counter: { count: 10 } } })`
- Spy on actions: `const store = useStore(); expect(store.increment).toHaveBeenCalled()`

## Mocking

- Mock modules: `vi.mock('@/services/api')`
- Mock router: `const router = createRouter({ history: createMemoryHistory(), routes })`
- Mock global plugins: `mount(Component, { global: { plugins: [router] } })`

## Dos

- Test emitted events: `expect(wrapper.emitted('update:modelValue')).toBeTruthy()`
- Test slots: `mount(Component, { slots: { default: 'content' } })`
- Test v-model with `.setValue()` helper
- Test computed properties through rendered output
- Use `wrapper.unmount()` for cleanup verification

## Don'ts

- Don't access internal component state directly (test through UI)
- Don't test Vue reactivity system itself
- Don't mock Pinia in integration tests (use testing pinia)
- Don't use deprecated `wrapper.vm.$emit()` for testing events
- Don't test scoped CSS classes
