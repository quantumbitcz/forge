# Error Handling Patterns (Ruby)

## custom-exceptions

**Instead of:**
```ruby
def find_user(id)
  user = User.find_by(id: id)
  raise "User not found" unless user
  user
end
```

**Do this:**
```ruby
class UserNotFoundError < StandardError
  attr_reader :user_id

  def initialize(user_id)
    @user_id = user_id
    super("User #{user_id} not found")
  end
end

def find_user(id)
  User.find_by(id: id) || raise(UserNotFoundError, id)
end
```

**Why:** Custom exception classes carry structured context (the user ID) and let callers rescue precisely the failure they can handle. Raising bare strings loses the exception hierarchy.

## ensure-cleanup

**Instead of:**
```ruby
def process_file(path)
  file = File.open(path, 'r')
  data = file.read
  transform(data)
  file.close  # Skipped if transform raises
end
```

**Do this:**
```ruby
def process_file(path)
  File.open(path, 'r') do |file|
    transform(file.read)
  end
end
```

**Why:** Block form of `File.open` guarantees the file handle is closed when the block exits, even if an exception is raised. This is Ruby's idiomatic RAII pattern.

## retry-with-limit

**Instead of:**
```ruby
def fetch_data(url)
  response = Net::HTTP.get(URI(url))
rescue => e
  retry  # Infinite retry loop
end
```

**Do this:**
```ruby
def fetch_data(url, max_retries: 3)
  retries = 0
  begin
    Net::HTTP.get(URI(url))
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    retries += 1
    raise if retries > max_retries
    sleep(2 ** retries)
    retry
  end
end
```

**Why:** Unbounded `retry` creates infinite loops on persistent failures. Capping retries with exponential backoff and rescuing specific exceptions prevents both loops and masking unrelated errors.
