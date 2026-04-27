# Playwright E2E Testing Conventions (Cross-Framework)
> Support tier: contract-verified
## Test Structure

Organize by user journey, not by page. One file per major flow. Use `test.describe` for grouping related scenarios within a flow. Keep E2E tests in a dedicated `e2e/` or `playwright/` directory, separate from unit tests.

```typescript
// e2e/checkout.spec.ts
test.describe('Checkout flow', () => {
  test('completes purchase with valid payment', async ({ page }) => { ... })
  test('shows error on declined card', async ({ page }) => { ... })
})
```

## Naming

- File: `{user-journey}.spec.ts`
- Test: plain English — describes what the user does and what they expect
- Avoid technical names like `test_POST_/api/orders` — write `places an order successfully`

## Page Object Pattern

Encapsulate selectors and actions in Page Objects. Tests call methods, not raw locators.

```typescript
// e2e/pages/LoginPage.ts
export class LoginPage {
  constructor(private page: Page) {}

  async login(email: string, password: string) {
    await this.page.getByLabel('Email').fill(email)
    await this.page.getByLabel('Password').fill(password)
    await this.page.getByRole('button', { name: 'Sign in' }).click()
  }
}

// In test:
const loginPage = new LoginPage(page)
await loginPage.login('alice@example.com', 'secret')
```

## Selector Strategy

Priority order (most to least preferred):

1. `getByRole('button', { name: 'Submit' })` — semantic, accessible
2. `getByLabel('Email')` — form inputs
3. `getByText('Welcome back')` — visible user-facing text
4. `getByTestId('submit-btn')` — `data-testid` attribute for elements with no good semantic selector
5. CSS selectors (`.btn-primary`) — last resort; fragile

Never select by auto-generated class names (CSS Modules hashes, Tailwind utilities).

## Network Mocking

Mock external APIs and flaky third-party services. Do NOT mock your own backend in E2E tests — that defeats the purpose.

```typescript
await page.route('**/api/payments/process', route =>
  route.fulfill({ status: 200, json: { status: 'approved' } })
)

// Intercept and verify request body
await page.route('**/api/orders', async route => {
  const body = route.request().postDataJSON()
  expect(body.items).toHaveLength(2)
  await route.continue()
})
```

## Visual Regression

Use `toHaveScreenshot()` sparingly — only for components whose visual output is the product (charts, PDF previews, design tokens).

```typescript
await expect(page.locator('[data-testid="chart"]')).toHaveScreenshot('revenue-chart.png')
```

Update snapshots intentionally: `npx playwright test --update-snapshots`. Never commit auto-updated snapshots without reviewing the diff.

## Authentication State Reuse

Avoid logging in on every test — save and reuse auth state:

```typescript
// auth.setup.ts (runs once)
test('authenticate', async ({ page }) => {
  await page.goto('/login')
  await page.getByLabel('Email').fill(process.env.TEST_EMAIL!)
  await page.getByLabel('Password').fill(process.env.TEST_PASSWORD!)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await page.context().storageState({ path: 'playwright/.auth/user.json' })
})

// playwright.config.ts
projects: [
  { name: 'setup', testMatch: /auth\.setup\.ts/ },
  { name: 'chromium', use: { storageState: 'playwright/.auth/user.json' },
    dependencies: ['setup'] }
]
```

## Parallel Execution and Sharding

```typescript
// playwright.config.ts
export default defineConfig({
  workers: process.env.CI ? 2 : '50%',
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? 'github' : 'list',
})
```

Shard across CI jobs for large suites:
```bash
npx playwright test --shard=1/4   # Job 1 of 4
npx playwright test --shard=2/4   # Job 2 of 4
```

## CI Configuration

```yaml
# GitHub Actions
- name: Run Playwright tests
  run: npx playwright test
  env:
    CI: true

- name: Upload traces on failure
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: playwright-traces
    path: playwright-report/
```

Collect traces on failure (`trace: 'on-first-retry'`). Always run in headless mode in CI (the default). Use `--reporter=github` for inline PR annotations.

## What NOT to Test with E2E

- Pure UI state with no server interaction — unit test the component
- API contracts — use API-level integration tests
- Permission enforcement logic — test at the API layer, not via browser clicks
- Every edge case — E2E tests are expensive; cover happy paths and critical error paths

## Anti-Patterns

- Hardcoded `waitForTimeout(2000)` — use `waitFor` with a condition
- Selecting elements by auto-generated class names
- Tests that depend on execution order (shared database state without cleanup)
- Running E2E tests in the same CI job as unit tests (they have different resource profiles)
- Storing credentials in the test file — use environment variables or `.env.test`
