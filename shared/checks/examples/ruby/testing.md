# Testing Patterns (Ruby)

## let-lazy-evaluation

**Instead of:**
```ruby
describe User do
  it "validates email" do
    user = User.new(name: "Alice", email: "bad", role: :member)
    expect(user).not_to be_valid
  end

  it "saves with valid attributes" do
    user = User.new(name: "Alice", email: "alice@test.com", role: :member)
    expect(user.save).to be true
  end
end
```

**Do this:**
```ruby
describe User do
  subject(:user) { build(:user, **attributes) }
  let(:attributes) { {} }

  context "with invalid email" do
    let(:attributes) { { email: "bad" } }

    it { is_expected.not_to be_valid }
  end

  context "with valid attributes" do
    it { is_expected.to be_valid }
    it { expect(user.save).to be true }
  end
end
```

**Why:** `let` is lazily evaluated and memoized per example. Overriding specific attributes in nested contexts highlights exactly what varies per test case, with FactoryBot providing sensible defaults.

## shared-examples

**Instead of:**
```ruby
describe AdminController do
  it "returns 401 for unauthenticated requests" do
    get :index
    expect(response).to have_http_status(:unauthorized)
  end
end

describe ReportsController do
  it "returns 401 for unauthenticated requests" do
    get :index
    expect(response).to have_http_status(:unauthorized)
  end
end
```

**Do this:**
```ruby
RSpec.shared_examples "requires authentication" do |action|
  it "returns 401 for unauthenticated requests" do
    get action
    expect(response).to have_http_status(:unauthorized)
  end
end

describe AdminController do
  it_behaves_like "requires authentication", :index
end

describe ReportsController do
  it_behaves_like "requires authentication", :index
end
```

**Why:** Shared examples DRY up cross-cutting test behavior (auth, pagination, error handling). Changes to the shared expectation update all consumers automatically.
