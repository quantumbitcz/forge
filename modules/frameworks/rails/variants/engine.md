# Rails + Engine (Modular Monolith) Variant

> Rails Engines for modular monoliths. Extends `modules/frameworks/rails/conventions.md`.
> Use this variant when a single Rails app outgrows folder-only modularity but you don't yet need
> to split into separate services. Engines bound a domain inside the same deploy unit.

## Why Engines

A Rails Engine is a miniature Rails app packaged as a gem and mounted into a host. Benefits over folder-only modularity:

- **Hard module boundaries** — engines can't accidentally reference host code (`isolate_namespace` catches it)
- **Per-engine routes** — `mount Admin::Engine, at: '/admin'` keeps the host's `routes.rb` flat
- **Per-engine migrations** — schema changes ship with the engine
- **Per-engine tests** — test the engine in isolation against a dummy host app
- **Shared host services** — engines can depend on host gems and other engines

Use engines when:
- Domains are clearly bounded (admin panel, billing, marketing site)
- You expect to extract some engines to separate services later
- Multiple teams own different parts of the same monolith

Skip engines when the app is < 30k lines or when there's only one team.

## Generating an Engine

```bash
bin/rails plugin new admin --mountable
```

`--mountable` produces an isolated engine with its own namespace, routes, and migration directory. Without it, the engine is a "full" engine (no isolation — gems shared with the host, no separate namespacing).

```
admin/
├─ admin.gemspec               # gem metadata
├─ lib/admin.rb
├─ lib/admin/engine.rb         # isolate_namespace Admin
├─ config/routes.rb            # engine-internal routes
├─ app/controllers/admin/      # all classes namespaced under Admin::
├─ app/models/admin/
├─ app/views/admin/
├─ db/migrate/                 # engine migrations
├─ spec/dummy/                 # minimal Rails host for testing
└─ spec/                       # engine specs
```

## isolate_namespace

```ruby
# admin/lib/admin/engine.rb
module Admin
  class Engine < ::Rails::Engine
    isolate_namespace Admin

    config.generators do |g|
      g.test_framework :rspec
      g.factory_bot dir: 'spec/factories'
    end
  end
end
```

`isolate_namespace Admin` enforces:
- Models, controllers, helpers must live under `Admin::`
- Routes scoped under the engine's mount point
- Generators emit namespaced classes (`bin/rails g controller posts` → `Admin::PostsController`)
- Engine doesn't leak constants into the host

## Mounting in the Host

```ruby
# host_app/Gemfile
gem 'admin', path: 'engines/admin'

# host_app/config/routes.rb
Rails.application.routes.draw do
  mount Admin::Engine, at: '/admin', as: :admin   # routes prefix '/admin'

  root 'home#index'
end
```

Engine URL helpers are scoped under the engine's name: `admin.posts_path` from anywhere in the host. Host helpers are accessible from the engine via `main_app.root_path`.

## Migrations

Engine migrations live under `engine/db/migrate/`. Install them into the host:

```bash
cd host_app
bin/rails admin:install:migrations    # copies engine migrations to db/migrate/
bin/rails db:migrate
```

Each engine declares its install task automatically — `<engine_name>:install:migrations`. Schema changes ship with the engine; host installs them.

Caveat: once installed, the migrations live in the host's `db/migrate/` and are no longer tracked back to the engine. Bump the engine version when schema changes ship.

## Assets in Engines (Propshaft)

Each engine ships its own asset directory:

```
admin/app/assets/
├─ stylesheets/admin/application.css
└─ images/admin/logo.png
```

Reference from views via `image_tag('admin/logo.png')` — Propshaft serves them from `/assets/admin/logo-<digest>.png`. The host's `config.assets.paths` automatically includes engine asset directories.

For Importmap, the engine declares its pins in `config/importmap.rb` and the host loads them via `pin_all_from Admin::Engine.root.join('app/javascript')`.

## Dependency Injection

Engines should not call into host-specific code by name. Instead, accept dependencies via Rails config:

```ruby
# admin/lib/admin/engine.rb
module Admin
  class Engine < ::Rails::Engine
    isolate_namespace Admin
    config.admin = ActiveSupport::OrderedOptions.new
    config.admin.user_class = 'User'   # default; host overrides
  end
end

# admin/app/controllers/admin/application_controller.rb
def current_admin
  user_class = Admin::Engine.config.admin.user_class.constantize
  user_class.find_by(id: session[:admin_id])
end

# host_app/config/application.rb
config.admin.user_class = 'AdminUser'
```

This keeps the engine portable — drop it into another host with a different User model and override one config line.

## Testing Engines Independently

The engine's `spec/dummy/` is a minimal Rails app used as the host during the engine's own test runs:

```bash
cd engines/admin
bundle exec rspec    # runs against spec/dummy
```

Test categories:
- **Unit specs** — test models, services, policies in isolation
- **Request specs** — test the engine's routes via `spec/dummy`
- **Integration specs in the host** — test the engine + host integration in `host_app/spec/`

## Shared Models Across Engines (avoid)

Cross-engine model sharing is the hardest engine smell to fix:

```ruby
# admin/app/models/admin/post.rb
module Admin
  class Post < ::Post   # host model — couples Admin to host
  end
end
```

Once you do this, the engine can't be deployed without a host that has `::Post`. Better:

- Define the model in a **shared engine** (`engines/core/`) that other engines depend on
- Or duplicate the model in each engine and sync via events (`solid_queue` jobs)
- Or extract the boundary as a service (gRPC / REST)

The engine pattern fights you here — accept the duplication or rethink the boundary.

## Dos

- Use `--mountable` (not bare `plugin new`) — `isolate_namespace` is the whole point of engines
- Keep engines bounded by domain, not by technical layer (good: `billing`, `admin`. Bad: `controllers`, `services`)
- Pass dependencies via `Engine.config` — never hard-code host class names inside the engine
- Test the engine in isolation via `spec/dummy/` — and also test the host integration in the host's specs
- Bump the engine's gem version on every schema change so migration drift is visible

## Don'ts

- Don't reach into the host from the engine via constant names (`User.find(...)`) — use injected config
- Don't share AR models across engines via subclassing — duplicate the model or use events
- Don't put cross-engine business logic in the host — it becomes the lowest-common-denominator dumping ground
- Don't skip `isolate_namespace` — the engine becomes a folder pretending to be a module
- Don't deploy engines from separate gem repos until the boundary is stable — premature `path: 'engines/...'` → `git: '...'` migration causes weeks of dependency-resolution pain
