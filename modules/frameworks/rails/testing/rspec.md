# Rails + RSpec Testing Patterns

> Rails-specific RSpec patterns. Extends `modules/testing/rspec.md`.
> Generic RSpec conventions (matchers, shared examples, `let`/`subject`, `before`/`after`) are in the parent file.

Rails 8 ships with **Minitest** by default, but RSpec (rspec-rails 7+) is the dominant community choice for the gem ecosystem (Capybara, factory_bot, shoulda-matchers, vcr, rswag). Install via `bin/rails generate rspec:install` after adding `gem 'rspec-rails'` to the `:development, :test` group.

## Spec Layout

```
spec/
├─ rails_helper.rb        # Rails-aware (loads app, fixtures, factories)
├─ spec_helper.rb         # Plain RSpec (no Rails) — for fast pure-Ruby specs
├─ requests/              # Preferred — HTTP-level integration specs
├─ models/                # Validations, scopes, callbacks, instance methods
├─ services/              # Business logic units
├─ system/                # Browser-driven feature tests (Capybara)
├─ jobs/                  # ActiveJob units
├─ mailers/               # ActionMailer rendering and delivery
├─ policies/              # Pundit policies
├─ components/            # ViewComponent specs
├─ factories/             # factory_bot definitions
└─ support/               # shared_examples, helpers, configuration
```

## rails_helper.rb

```ruby
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'
require 'shoulda/matchers'

Rails.root.glob('spec/support/**/*.rb').each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
  config.include ActiveJob::TestHelper, type: :job
  config.include ActionMailer::TestHelper, type: :mailer
  config.include Devise::Test::IntegrationHelpers, type: :request
end

Shoulda::Matchers.configure do |c|
  c.integrate { |with| with.test_framework :rspec; with.library :rails }
end
```

## Request Specs (preferred over controller specs)

Rails 5+ deprecated controller specs in favour of request specs — request specs exercise the full middleware + routing + controller stack:

```ruby
# spec/requests/posts_spec.rb
require 'rails_helper'

RSpec.describe 'Posts', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }   # Devise integration helper

  describe 'GET /posts' do
    it 'lists published posts' do
      published = create_list(:post, 3, :published, author: user)
      _draft    = create(:post, author: user)

      get posts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(*published.map(&:title))
    end
  end

  describe 'POST /posts' do
    it 'creates a post with valid params' do
      expect {
        post posts_path, params: { post: attributes_for(:post) }
      }.to change(Post, :count).by(1)

      expect(response).to redirect_to(post_path(Post.last))
    end

    it 'rejects invalid params with 422' do
      post posts_path, params: { post: { title: '' } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Title can&#39;t be blank')
    end
  end
end
```

Why request specs > controller specs:
- Exercises the full stack (middleware, routing, controller, response)
- Refactor-safe — if you split a controller, the spec still passes
- Tests the public HTTP contract — what consumers actually depend on

## System Specs (Capybara)

System specs drive a real browser via Capybara. Choose a driver:

| Driver | Pros | Cons | Use when |
|--------|------|------|----------|
| **Cuprite** (Chrome DevTools) | Fast, no Selenium, parallel-safe | Chrome only | **Recommended default** |
| **Selenium + Chrome headless** | Cross-browser via swap | Slower, more flaky | Multi-browser matrix |
| **Playwright** (capybara-playwright-driver) | Modern API, Chrome/Firefox/WebKit | Less mature in Ruby | Cross-browser, Hotwire-heavy apps |

```ruby
# spec/rails_helper.rb (or support/system.rb)
require 'capybara/cuprite'

Capybara.javascript_driver = :cuprite
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1280, 800], browser_options: { 'no-sandbox': nil })
end

# spec/system/post_creation_spec.rb
RSpec.describe 'Post creation', type: :system, js: true do
  let(:user) { create(:user) }
  before { sign_in user }

  it 'creates a post via the form' do
    visit new_post_path
    fill_in 'Title', with: 'Hello world'
    fill_in 'Body',  with: 'This is a body'
    click_button 'Create'

    expect(page).to have_content('Post was successfully created')
    expect(page).to have_content('Hello world')
  end
end
```

For Hotwire-heavy specs (Turbo Streams, broadcasting), Cuprite handles WebSocket frames cleanly. Wait for streams via `expect(page).to have_css('#comment_42')` (Capybara's auto-wait).

## factory_bot

```ruby
# spec/factories/posts.rb
FactoryBot.define do
  factory :post do
    sequence(:title) { |n| "Post #{n}" }
    body { 'A body of text' }
    association :author, factory: :user

    trait :published do
      published_at { 1.day.ago }
    end

    trait :with_comments do
      transient { comment_count { 3 } }
      after(:create) do |post, ev|
        create_list(:comment, ev.comment_count, post: post)
      end
    end
  end
end
```

Usage patterns:

| Method | Speed | Persistence | Use when |
|--------|-------|-------------|----------|
| `build(:post)` | Fast | In-memory only | Testing validations, no DB needed |
| `build_stubbed(:post)` | Fastest | Stubbed `id`, `created_at`; no DB hit | Testing presenters, view specs |
| `create(:post)` | Slow | Inserts via SQL | Integration, request, system specs |
| `attributes_for(:post)` | Fast | Returns Hash | Controller param hashes |

Default to `build_stubbed` when you can — `create` is the slowest and the most likely to leak state.

## Shared Examples vs Shared Contexts

```ruby
# spec/support/shared_examples/auditable.rb
RSpec.shared_examples 'auditable' do
  it { is_expected.to have_db_column(:created_by_id) }
  it { is_expected.to have_db_column(:updated_by_id) }

  it 'records created_by on insert' do
    User.current = create(:user)
    record = create(described_class.name.underscore.to_sym)
    expect(record.created_by).to eq(User.current)
  end
end

# spec/models/post_spec.rb
RSpec.describe Post do
  it_behaves_like 'auditable'
end
```

Shared **examples** test behaviour; shared **contexts** set up state (`include_context 'with logged-in admin'`). Don't mix the two.

## Database isolation

Prefer Rails' built-in transactional fixtures (`config.use_transactional_fixtures = true`) — fast, no setup. Each test runs inside a transaction that rolls back at teardown.

Switch to `database_cleaner-active_record` only when:
- Using Capybara with a JS driver that runs in a separate process (the test thread's transaction isn't visible to the browser thread). Modern Cuprite + Selenium-managed in-process Chrome share the connection — usually not needed
- Using multiple databases that don't share a connection

```ruby
# spec/rails_helper.rb (only if needed)
config.use_transactional_fixtures = false
config.before(:each) { DatabaseCleaner.strategy = :transaction }
config.before(:each, type: :system) { DatabaseCleaner.strategy = :truncation }
config.before(:each) { DatabaseCleaner.start }
config.after(:each)  { DatabaseCleaner.clean }
```

## ActiveJob testing

```ruby
# spec/jobs/welcome_email_job_spec.rb
RSpec.describe WelcomeEmailJob, type: :job do
  it 'queues the job' do
    expect { WelcomeEmailJob.perform_later(user_id: 1) }
      .to have_enqueued_job(WelcomeEmailJob).with(user_id: 1).on_queue('mailers')
  end

  it 'sends the welcome email' do
    user = create(:user)
    perform_enqueued_jobs do
      WelcomeEmailJob.perform_later(user_id: user.id)
    end
    expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
  end
end
```

In request specs that enqueue jobs, use `perform_enqueued_jobs do ... end` to drain the queue inline.

## VCR for external HTTP

```ruby
# spec/support/vcr.rb
VCR.configure do |c|
  c.cassette_library_dir = 'spec/vcr_cassettes'
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.filter_sensitive_data('<STRIPE_KEY>') { ENV.fetch('STRIPE_API_KEY', 'test_key') }
end

# Usage:
RSpec.describe StripeChargeService, vcr: { cassette_name: 'stripe/charge_succeeds' } do
  it 'charges the card' do
    expect(StripeChargeService.new(amount: 100).call).to be_success
  end
end
```

Cassettes capture the first run; subsequent runs replay deterministically. Filter all secrets via `filter_sensitive_data`.

## Useful matchers (rspec-rails)

- `have_http_status(:ok)` / `have_http_status(200)` — response code
- `redirect_to(path)` — redirect target
- `render_template(:show)` — controller specs only
- `have_enqueued_job(MyJob).with(...)` — ActiveJob assertions
- `have_been_enqueued` / `have_enqueued_mail(MyMailer, :welcome)` — mailer specs
- `have_broadcasted_to(stream)` — ActionCable assertions
- `match_response_schema('schema_name')` — JSON schema (json_matchers gem)

## `rspec --profile`

Identifies the slowest specs:

```bash
bundle exec rspec --profile 10
# => prints the 10 slowest examples + groups
```

Anything over 1 second usually means an N+1, an avoidable `create` (use `build_stubbed`), or a missing `--no-test-framework` on a generator that scaffolded a redundant spec.

## Dos

- Prefer **request specs** over controller specs — controller specs are deprecated in Rails 5+
- Use `build_stubbed` over `create` when DB persistence isn't needed — 10-100× faster
- Use factory_bot **traits** to compose state (`create(:post, :published, :with_comments, comment_count: 5)`)
- Use Capybara's auto-wait (`have_css`, `have_content`) — never `sleep` to wait for JS
- Drive auth via Devise's `sign_in user` integration helper — don't POST to `/users/sign_in` in every test
- Use `perform_enqueued_jobs` to drain the queue inline; `have_enqueued_job` to assert without performing
- Run `bundle exec rspec --profile 10` weekly — slowest specs accumulate

## Don'ts

- Don't write controller specs in new code — use request specs
- Don't `sleep` in system specs to wait for Turbo Streams — use `have_css('#comment_42')` (Capybara auto-waits up to `Capybara.default_max_wait_time`)
- Don't `let!` everywhere — eager evaluation defeats the lazy-spec speedup; use `let` and call it where needed
- Don't share state via instance variables across `before` blocks and examples — use `let` / `let!`
- Don't `create(:user)` in every test if a `build_stubbed(:user)` would do — every `create` is 10-100ms of DB IO
- Don't run system specs with `js: true` everywhere — only specs that exercise client-side JS need a browser
- Don't ship VCR cassettes containing real secrets — `filter_sensitive_data` is mandatory before commit

For generic RSpec patterns (lazy `let`, `subject`, `shared_examples`, `--bisect`), see `modules/testing/rspec.md`.
