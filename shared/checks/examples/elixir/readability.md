# Readability Patterns (Elixir)

## pipe-operator

**Instead of:**
```elixir
def process(raw_input) do
  result = String.trim(raw_input)
  result = String.downcase(result)
  result = String.split(result, ",")
  Enum.map(result, &String.to_atom/1)
end
```

**Do this:**
```elixir
def process(raw_input) do
  raw_input
  |> String.trim()
  |> String.downcase()
  |> String.split(",")
  |> Enum.map(&String.to_atom/1)
end
```

**Why:** The pipe operator (`|>`) reads top-to-bottom as a data transformation pipeline, eliminating intermediate variables and making the flow of data self-evident.

## multi-clause-functions

**Instead of:**
```elixir
def handle_response(response) do
  if response.status == 200 do
    {:ok, Jason.decode!(response.body)}
  else
    if response.status == 404 do
      {:error, :not_found}
    else
      {:error, {:server_error, response.status}}
    end
  end
end
```

**Do this:**
```elixir
def handle_response(%{status: 200, body: body}), do: {:ok, Jason.decode!(body)}
def handle_response(%{status: 404}), do: {:error, :not_found}
def handle_response(%{status: status}), do: {:error, {:server_error, status}}
```

**Why:** Multi-clause function definitions with pattern matching replace conditional branching with declarative dispatch. Each clause handles exactly one case, making the logic scannable.

## doc-attributes

**Instead of:**
```elixir
# Calculates the price after discount
# discount is a float between 0 and 1
def apply_discount(price, discount) do
  price * (1 - discount)
end
```

**Do this:**
```elixir
@doc """
Applies a percentage discount to a price.

## Examples

    iex> Pricing.apply_discount(100.0, 0.2)
    80.0

"""
@spec apply_discount(number(), float()) :: float()
def apply_discount(price, discount) when discount >= 0 and discount <= 1 do
  price * (1 - discount)
end
```

**Why:** `@doc` with doctests creates documentation that doubles as executable tests (`mix test`). `@spec` typespecs enable Dialyzer static analysis. Guards enforce preconditions at the function boundary.
