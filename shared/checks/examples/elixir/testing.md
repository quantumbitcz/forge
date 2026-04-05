# Testing Patterns (Elixir)

## async-sandbox

**Instead of:**
```elixir
test "creates a user" do
  # Shared database connection — tests can't run in parallel
  Repo.insert!(%User{name: "Alice"})
  assert Repo.aggregate(User, :count) == 1
end
```

**Do this:**
```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
end

test "creates a user" do
  assert {:ok, user} = Repo.insert(%User{name: "Alice"})
  assert user.id != nil
  assert Repo.get!(User, user.id).name == "Alice"
end
```

**Why:** The Ecto SQL Sandbox wraps each test in a transaction that is rolled back after the test completes. Tests run in parallel without data leakage, and the database resets automatically.

## describe-blocks

**Instead of:**
```elixir
test "discount for premium user" do
  user = %User{plan: :premium}
  assert Pricing.discount(user) == 0.2
end

test "no discount for free user" do
  user = %User{plan: :free}
  assert Pricing.discount(user) == 0.0
end
```

**Do this:**
```elixir
describe "discount/1" do
  test "returns 20% for premium users" do
    user = build(:user, plan: :premium)
    assert Pricing.discount(user) == 0.2
  end

  test "returns 0% for free users" do
    user = build(:user, plan: :free)
    assert Pricing.discount(user) == 0.0
  end
end
```

**Why:** `describe` blocks group tests by function, making `mix test --trace` output read like a specification. Factory functions (`build/2` via ExMachina) isolate test data from schema changes.
