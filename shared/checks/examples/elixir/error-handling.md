# Error Handling Patterns (Elixir)

## with-chain

**Instead of:**
```elixir
def create_order(params) do
  case validate(params) do
    {:ok, validated} ->
      case Repo.insert(Order.changeset(validated)) do
        {:ok, order} ->
          case Billing.charge(order) do
            {:ok, receipt} -> {:ok, {order, receipt}}
            {:error, reason} -> {:error, reason}
          end
        {:error, changeset} -> {:error, changeset}
      end
    {:error, reason} -> {:error, reason}
  end
end
```

**Do this:**
```elixir
def create_order(params) do
  with {:ok, validated} <- validate(params),
       {:ok, order} <- Repo.insert(Order.changeset(validated)),
       {:ok, receipt} <- Billing.charge(order) do
    {:ok, {order, receipt}}
  end
end
```

**Why:** `with` chains multiple pattern-matched steps and short-circuits on the first non-match, eliminating deeply nested `case` pyramids. The non-matching value propagates automatically.

## tagged-tuples

**Instead of:**
```elixir
def find_user(id) do
  user = Repo.get(User, id)
  if user, do: user, else: nil
end

# Caller can't distinguish "not found" from function returning nil for other reasons
```

**Do this:**
```elixir
def find_user(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end
```

**Why:** Tagged tuples (`{:ok, value}` / `{:error, reason}`) are the Elixir convention for fallible operations. They enable pattern matching at call sites and compose naturally with `with`.

## supervisor-strategy

**Instead of:**
```elixir
def start_link(_) do
  # Process crashes take down the whole application
  GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
end
```

**Do this:**
```elixir
defmodule MyApp.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      {MyApp.Worker, restart: :transient}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

**Why:** OTP supervisors isolate failures — a crashed worker is restarted without affecting siblings. The `:transient` restart strategy only restarts on abnormal exits, preventing restart loops for expected shutdowns.
