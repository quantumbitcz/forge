# Cypress Best Practices

> Support tier: contract-verified

## Overview
Cypress is a JavaScript-based E2E testing framework providing real-time browser reloading, automatic waiting, time-travel debugging, and network stubbing. Use it for testing web applications (React, Vue, Angular, Next.js) where visual feedback and developer experience matter. Avoid Cypress for cross-browser testing at scale (use Playwright for Webkit/Firefox), mobile app testing, or non-web applications.

## Conventions

### Test Structure
```typescript
describe("Checkout Flow", () => {
  beforeEach(() => {
    cy.intercept("GET", "/api/cart", { fixture: "cart.json" }).as("getCart");
    cy.visit("/checkout");
    cy.wait("@getCart");
  });

  it("should complete purchase with valid card", () => {
    cy.getByTestId("card-number").type("4242424242424242");
    cy.getByTestId("expiry").type("12/28");
    cy.getByTestId("cvc").type("123");

    cy.intercept("POST", "/api/orders", { statusCode: 201, body: { id: "order_123" } }).as("createOrder");
    cy.getByTestId("submit-button").click();
    cy.wait("@createOrder");

    cy.url().should("include", "/order/confirmation");
    cy.getByTestId("order-id").should("contain", "order_123");
  });

  it("should show validation error for expired card", () => {
    cy.getByTestId("card-number").type("4242424242424242");
    cy.getByTestId("expiry").type("01/20");
    cy.getByTestId("submit-button").click();

    cy.getByTestId("error-message").should("be.visible").and("contain", "expired");
  });
});
```

### Custom Commands
```typescript
// cypress/support/commands.ts
Cypress.Commands.add("getByTestId", (testId: string) => {
  return cy.get(`[data-testid="${testId}"]`);
});

Cypress.Commands.add("login", (email: string, password: string) => {
  cy.session([email, password], () => {
    cy.visit("/login");
    cy.getByTestId("email").type(email);
    cy.getByTestId("password").type(password);
    cy.getByTestId("submit").click();
    cy.url().should("not.include", "/login");
  });
});
```

### API Interception
```typescript
cy.intercept("GET", "/api/products*", { fixture: "products.json" }).as("getProducts");
cy.intercept("POST", "/api/orders", (req) => {
  expect(req.body).to.have.property("items");
  req.reply({ statusCode: 201, body: { id: "order_123" } });
}).as("createOrder");
```

## Configuration

```typescript
// cypress.config.ts
import { defineConfig } from "cypress";

export default defineConfig({
  e2e: {
    baseUrl: "http://localhost:3000",
    viewportWidth: 1280,
    viewportHeight: 720,
    defaultCommandTimeout: 10000,
    requestTimeout: 10000,
    retries: { runMode: 2, openMode: 0 },
    video: false,
    screenshotOnRunFailure: true,
    experimentalRunAllSpecs: true
  }
});
```

## Dos
- Use `data-testid` attributes for selecting elements — they're resilient to CSS and text changes.
- Use `cy.intercept()` to stub API calls — tests should not depend on backend availability.
- Use `cy.session()` for login — it caches session state across tests, dramatically speeding up the suite.
- Use `cy.wait("@alias")` after triggering API calls — it ensures the response is received before assertions.
- Use fixtures (`cypress/fixtures/`) for API response data — keeps tests readable and maintainable.
- Use `beforeEach` for test setup — every test should start from a known state.
- Run Cypress in CI with `cypress run` (headless) — `cypress open` is for local development only.

## Don'ts
- Don't use `cy.wait(ms)` for arbitrary delays — use `cy.wait("@alias")` or assertion-based waiting.
- Don't select elements by CSS class or tag name — they change frequently and break tests.
- Don't test third-party sites (OAuth providers, payment gateways) — stub their APIs instead.
- Don't share state between tests — each test should be independent and runnable in isolation.
- Don't use `cy.get().then()` chains when Cypress commands already chain — it adds unnecessary complexity.
- Don't run all E2E tests on every PR — run smoke tests on PR, full suite nightly or on release branches.
- Don't ignore flaky tests — investigate and fix the root cause (usually timing issues or missing waits).
