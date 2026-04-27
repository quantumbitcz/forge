# Cucumber / BDD Best Practices
> Support tier: contract-verified
## Overview
Cucumber is a BDD (Behavior-Driven Development) testing framework that lets you write tests in Gherkin (human-readable Given-When-Then syntax). Available for JVM (cucumber-jvm), JavaScript (cucumber-js), Python (behave/pytest-bdd), Ruby, and .NET (SpecFlow). Use it for acceptance testing where non-technical stakeholders participate in defining behavior. Avoid it for unit tests, performance tests, or when the Gherkin layer adds ceremony without stakeholder involvement.

## Conventions

### Feature File Structure
```gherkin
# features/checkout.feature
Feature: Checkout Process
  As a customer
  I want to complete a purchase
  So that I receive my ordered products

  Background:
    Given the following products exist:
      | name       | price | stock |
      | Widget     | 9.99  | 100   |
      | Gadget     | 49.99 | 50    |

  Scenario: Successful checkout with single item
    Given I am logged in as "alice@example.com"
    And I have "Widget" in my cart with quantity 2
    When I proceed to checkout
    And I enter valid payment details
    Then the order should be created with total "$19.98"
    And I should receive an order confirmation email

  Scenario Outline: Checkout validation
    Given I am logged in as "<email>"
    And I have "<product>" in my cart
    When I proceed to checkout
    And I enter payment with card "<card>"
    Then I should see error "<error>"

    Examples:
      | email              | product | card             | error            |
      | alice@example.com  | Widget  | 4000000000000002 | Card declined    |
      | alice@example.com  | Widget  |                  | Card is required |
```

### Step Definitions (TypeScript — cucumber-js)
```typescript
import { Given, When, Then } from "@cucumber/cucumber";
import { expect } from "chai";

Given("I am logged in as {string}", async function(email: string) {
  this.user = await loginAs(email);
});

Given("I have {string} in my cart with quantity {int}", async function(product: string, qty: number) {
  await this.user.addToCart(product, qty);
});

When("I proceed to checkout", async function() {
  this.checkoutResult = await this.user.checkout();
});

Then("the order should be created with total {string}", async function(expectedTotal: string) {
  expect(this.checkoutResult.order.total).to.equal(expectedTotal);
});
```

### Step Definitions (Kotlin — cucumber-jvm)
```kotlin
class CheckoutSteps {
    private lateinit var user: TestUser
    private lateinit var result: CheckoutResult

    @Given("I am logged in as {string}")
    fun loginAs(email: String) {
        user = TestUser.login(email)
    }

    @When("I proceed to checkout")
    fun proceedToCheckout() {
        result = user.checkout()
    }

    @Then("the order should be created with total {string}")
    fun verifyTotal(expectedTotal: String) {
        assertThat(result.order.total).isEqualTo(expectedTotal)
    }
}
```

## Configuration

```javascript
// cucumber.js
module.exports = {
  default: {
    require: ["features/step_definitions/**/*.ts"],
    requireModule: ["ts-node/register"],
    format: ["progress", "html:reports/cucumber.html"],
    parallel: 4,
    tags: "not @wip"
  }
};
```

## Dos
- Write scenarios in business language — avoid technical implementation details in Gherkin.
- Use `Background` for shared preconditions across scenarios in a feature file.
- Use `Scenario Outline` with `Examples` tables for data-driven tests.
- Keep step definitions reusable — write generic steps like `Given I am logged in as {string}`.
- Use tags (`@smoke`, `@wip`, `@slow`) to organize and filter test runs.
- Store test data in `Examples` tables or data tables — not hardcoded in step definitions.
- Run BDD tests as part of CI — they serve as living documentation of accepted behavior.

## Don'ts
- Don't write Gherkin for unit tests — the Given-When-Then overhead adds no value for isolated code tests.
- Don't put implementation details in feature files — `When I click the button with class .btn-primary` defeats the purpose.
- Don't create one step per test — reuse steps across scenarios for consistency and maintainability.
- Don't skip stakeholder involvement — Cucumber without business collaboration is just a verbose test framework.
- Don't use too many steps per scenario — keep scenarios focused (5-8 steps max) for readability.
- Don't couple step definitions to UI selectors — use a page object or service layer underneath.
- Don't test edge cases through BDD — use unit tests for boundary conditions and error paths.
