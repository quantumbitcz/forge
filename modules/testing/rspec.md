# RSpec Best Practices

> Support tier: contract-verified

## Overview
RSpec is the dominant BDD-style testing framework for Ruby. Use it for unit, integration, and system tests in Ruby and Rails applications. RSpec excels at readable test descriptions, powerful matchers, and composable test doubles. Avoid it for non-Ruby projects — each language has its idiomatic testing framework.

## Conventions

### Test Structure
```ruby
# spec/models/user_spec.rb
RSpec.describe User do
  describe "#full_name" do
    it "returns first and last name combined" do
      user = User.new(first_name: "Alice", last_name: "Smith")
      expect(user.full_name).to eq("Alice Smith")
    end

    context "when last name is missing" do
      it "returns only first name" do
        user = User.new(first_name: "Alice", last_name: nil)
        expect(user.full_name).to eq("Alice")
      end
    end
  end

  describe ".active" do
    it "returns only active users" do
      active = create(:user, active: true)
      create(:user, active: false)
      expect(User.active).to contain_exactly(active)
    end
  end
end
```

### Shared Examples
```ruby
RSpec.shared_examples "an authenticatable resource" do
  it { is_expected.to respond_to(:authenticate) }
  it { is_expected.to respond_to(:password_digest) }
end

RSpec.describe User do
  it_behaves_like "an authenticatable resource"
end
```

### Test Doubles
```ruby
let(:payment_gateway) { instance_double(PaymentGateway) }

before do
  allow(payment_gateway).to receive(:charge).and_return(success_response)
end

it "charges the card" do
  service.process_payment(order)
  expect(payment_gateway).to have_received(:charge).with(amount: 99.99)
end
```

## Configuration

```ruby
# spec/spec_helper.rb
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.order = :random
end
```

## Dos
- Use `describe` for the class/method under test, `context` for conditions, `it` for behaviors.
- Use `let` (lazy) and `let!` (eager) for test data — avoid instance variables in `before` blocks.
- Use `instance_double` for type-checked mocks — they fail if the mocked method doesn't exist.
- Use `shared_examples` for behaviors shared across multiple specs.
- Use `FactoryBot` for test data creation — avoid fixtures for complex object graphs.
- Use `context "when ..."` to describe preconditions — it groups related assertions clearly.
- Run specs in random order (`--order random`) to catch order-dependent tests.

## Don'ts
- Don't use `subject` for non-trivial setups — named `let` variables are more readable.
- Don't use `allow_any_instance_of` — it's a code smell indicating tight coupling.
- Don't test private methods directly — test through the public interface.
- Don't use `before(:all)` for database operations — state leaks between examples.
- Don't use string descriptions that duplicate the code: `it "returns true"` vs `it "validates the email format"`.
- Don't use `expect { }.not_to raise_error` — it catches all exceptions including unrelated ones.
- Don't nest `describe`/`context` more than 3 levels deep — extract to shared examples or separate specs.
