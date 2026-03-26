# ExUnit Best Practices

## Overview
ExUnit is Elixir's built-in testing framework. Use it for unit and integration tests in Elixir/Phoenix applications. ExUnit excels at concurrent test execution, doctests, and first-class support for async testing with the BEAM VM. Avoid it for non-Elixir projects.

## Conventions

### Test Structure
```elixir
defmodule MyApp.UserServiceTest do
  use ExUnit.Case, async: true

  alias MyApp.UserService

  describe "create_user/2" do
    test "creates a user with valid attributes" do
      assert {:ok, user} = UserService.create_user("alice@example.com", "Alice")
      assert user.email == "alice@example.com"
      assert user.name == "Alice"
    end

    test "returns error for invalid email" do
      assert {:error, :invalid_email} = UserService.create_user("not-an-email", "Alice")
    end
  end

  describe "find_user/1" do
    setup do
      {:ok, user} = UserService.create_user("bob@example.com", "Bob")
      %{user: user}
    end

    test "finds user by id", %{user: user} do
      assert {:ok, found} = UserService.find_user(user.id)
      assert found.email == user.email
    end

    test "returns error for missing user" do
      assert {:error, :not_found} = UserService.find_user("nonexistent")
    end
  end
end
```

### Doctests
```elixir
defmodule MyApp.Utils do
  @doc """
  Slugifies a string.

      iex> MyApp.Utils.slugify("Hello World")
      "hello-world"

      iex> MyApp.Utils.slugify("  Spaces  ")
      "spaces"
  """
  def slugify(str) do
    str |> String.trim() |> String.downcase() |> String.replace(~r/\s+/, "-")
  end
end
```

### Mox for Behaviour-Based Mocks
```elixir
# test/support/mocks.ex
Mox.defmock(MyApp.MockPaymentGateway, for: MyApp.PaymentGateway)

# test/services/order_service_test.exs
test "charges the payment gateway" do
  expect(MyApp.MockPaymentGateway, :charge, fn amount ->
    assert amount == Decimal.new("99.99")
    {:ok, %{transaction_id: "tx_123"}}
  end)

  assert {:ok, order} = OrderService.process(order_params)
end
```

## Configuration

```elixir
# test/test_helper.exs
ExUnit.start(exclude: [:slow])
Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)
```

## Dos
- Use `async: true` on test modules that don't share state — ExUnit runs them concurrently.
- Use `describe` blocks to group related tests and share `setup` context.
- Use `Mox` for behaviour-based mocking — it enforces the contract at compile time.
- Use doctests for pure functions — they serve as documentation and tests simultaneously.
- Use `setup` callbacks for test data — they run before each test in the `describe` block.
- Use pattern matching in assertions: `assert {:ok, %User{email: "alice@example.com"}} = result`.
- Use `Ecto.Adapters.SQL.Sandbox` for database test isolation in Phoenix apps.

## Don'ts
- Don't use `async: true` with tests that share database state without the Ecto sandbox.
- Don't use `Process.sleep` for async waiting — use `assert_receive` with timeout.
- Don't mock modules you own — use dependency injection via Behaviours and Mox.
- Don't test OTP GenServer internals — test through the public API.
- Don't use `setup_all` for database operations — it runs once and state leaks.
- Don't skip doctests for public API functions — they catch documentation drift.
- Don't use string assertions (`assert result == "expected"`) when pattern matching works.
