# Ecto Best Practices

## Overview
Ecto is Elixir's database library providing schemas, changesets, queries, and migrations. Use it for Phoenix/Elixir backends needing type-safe database access with explicit data validation. Ecto excels at composable queries, changeset-based validation, and multi-repo support. Avoid it for non-Elixir projects.

## Architecture Patterns

**Schema and changeset:**
```elixir
defmodule MyApp.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :password_hash, :string
    has_many :orders, MyApp.Order
    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_required([:email, :name])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end
end
```

**Composable queries:**
```elixir
import Ecto.Query

def list_active_users(opts \\ []) do
  User
  |> where([u], u.active == true)
  |> maybe_filter_by_role(opts[:role])
  |> order_by([u], desc: u.inserted_at)
  |> limit(^(opts[:limit] || 20))
  |> Repo.all()
end

defp maybe_filter_by_role(query, nil), do: query
defp maybe_filter_by_role(query, role), do: where(query, [u], u.role == ^role)
```

**Transactions:**
```elixir
Ecto.Multi.new()
|> Ecto.Multi.insert(:order, Order.changeset(%Order{}, order_attrs))
|> Ecto.Multi.update(:user, fn %{order: order} ->
  User.changeset(user, %{last_order_at: DateTime.utc_now()})
end)
|> Repo.transaction()
```

**Anti-pattern — skipping changesets for inserts/updates:** Changesets validate data before it reaches the database. Inserting raw maps bypasses validation and constraint checking.

## Configuration

```elixir
# config/config.exs
config :my_app, MyApp.Repo,
  database: "myapp_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool_size: 10
```

## Performance

**Preloading associations (avoid N+1):**
```elixir
users = Repo.all(from u in User, preload: [:orders])
```

**Select only needed fields:**
```elixir
Repo.all(from u in User, select: %{id: u.id, email: u.email})
```

**Use `Repo.stream` for large result sets** to avoid loading everything into memory.

## Security

Ecto uses parameterized queries by default — all `^variable` interpolations are bind parameters. Never use `fragment()` with user input unless parameterized.

## Testing

```elixir
# Use Ecto.Adapters.SQL.Sandbox for test isolation
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
end

test "creates a user" do
  assert {:ok, user} = Repo.insert(User.changeset(%User{}, %{email: "test@example.com", name: "Test"}))
  assert user.email == "test@example.com"
end
```

## Dos
- Use changesets for all data mutations — they provide validation, casting, and constraint checking.
- Use `Ecto.Multi` for transactions involving multiple operations — it composes cleanly.
- Use `preload` to avoid N+1 queries — never access associations without preloading.
- Use composable query functions — build queries from small, reusable functions.
- Use `Ecto.Adapters.SQL.Sandbox` for concurrent test isolation in Phoenix.
- Use migrations for all schema changes — never modify the database directly.
- Use `Repo.stream` for processing large datasets without memory pressure.

## Don'ts
- Don't skip changesets — inserting raw maps bypasses all validation.
- Don't use `fragment()` with unsanitized user input — it can bypass parameterization.
- Don't preload associations you don't need — each preload adds a query.
- Don't use `Repo.get!` in user-facing code — it raises on missing records; use `Repo.get` and handle `nil`.
- Don't put business logic in changesets — keep them focused on data validation and casting.
- Don't use dynamic table names from user input — it's a SQL injection vector.
- Don't ignore changeset errors — always check `{:ok, _}` / `{:error, changeset}` tuples.
