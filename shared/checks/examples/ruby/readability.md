# Readability Patterns (Ruby)

## enumerable-chaining

**Instead of:**
```ruby
def active_admin_emails(users)
  result = []
  users.each do |user|
    if user.active? && user.admin?
      result << user.email.downcase
    end
  end
  result.sort
end
```

**Do this:**
```ruby
def active_admin_emails(users)
  users
    .select(&:active?)
    .select(&:admin?)
    .map { |u| u.email.downcase }
    .sort
end
```

**Why:** Enumerable chains express transformations declaratively. Each step has a single responsibility, and the pipeline reads top-to-bottom as a data flow.

## frozen-string-literal

**Instead of:**
```ruby
class Config
  DEFAULT_HOST = "localhost"
  DEFAULT_PORT = "3000"

  def base_url
    "http://#{DEFAULT_HOST}:#{DEFAULT_PORT}"
  end
end
```

**Do this:**
```ruby
# frozen_string_literal: true

class Config
  DEFAULT_HOST = "localhost"
  DEFAULT_PORT = "3000"

  def base_url
    "http://#{DEFAULT_HOST}:#{DEFAULT_PORT}"
  end
end
```

**Why:** The `frozen_string_literal` magic comment freezes all string literals in the file, preventing accidental mutation and reducing object allocations. It is the default in Ruby 3+ style guides.

## pattern-matching

**Instead of:**
```ruby
def handle_response(response)
  if response.is_a?(Hash) && response[:status] == 200
    process(response[:body])
  elsif response.is_a?(Hash) && response[:status] == 404
    nil
  else
    raise "Unexpected response: #{response}"
  end
end
```

**Do this:**
```ruby
def handle_response(response)
  case response
  in { status: 200, body: }
    process(body)
  in { status: 404 }
    nil
  else
    raise "Unexpected response: #{response}"
  end
end
```

**Why:** Pattern matching (`case...in`, Ruby 3+) destructures and binds variables in one step, replacing manual type checks and hash key access with declarative matching.
