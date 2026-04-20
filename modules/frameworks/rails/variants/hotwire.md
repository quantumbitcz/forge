# Rails + Hotwire Variant

> Hotwire (Turbo + Stimulus) for Rails 7.2 / 8.x. Extends `modules/frameworks/rails/conventions.md`.
> Default variant for new Rails apps in this plugin — assume Hotwire unless `api-only` or `engine` is specified.

## Why Hotwire

Hotwire ships with Rails 7+ as the default front-end story. It lets you build SPA-feeling interactions with server-rendered HTML and very little JavaScript:

- **Turbo Drive** — accelerates link/form navigation (XHR + body swap, preserves JS state)
- **Turbo Frames** — scoped page regions that update independently
- **Turbo Streams** — fragment updates pushed over HTTP form responses or WebSocket
- **Stimulus** — small JS controllers attached via `data-` attributes

Use Hotwire when the team prefers ERB + sprinkled JS over a Node/SPA stack.

## Turbo Drive

```erb
<%# Default behaviour: Turbo intercepts every link and form %>
<%= link_to 'Posts', posts_path %>      <%# XHR + body swap %>
<%= link_to 'Logout', logout_path,
      data: { turbo_method: :delete, turbo_confirm: 'Sure?' } %>

<%# Opt out per-link (rare) %>
<%= link_to 'Download PDF', pdf_path, data: { turbo: false } %>
```

Lifecycle events fire on `document`:

```js
// app/javascript/application.js
document.addEventListener('turbo:before-fetch-request', (e) => { /* spinner on */ })
document.addEventListener('turbo:before-render', (e) => { /* swap warnings */ })
document.addEventListener('turbo:load', (e) => { /* analytics ping */ })
```

`turbo:load` replaces `DOMContentLoaded` for cross-page initialization — DOMContentLoaded fires once per full reload, `turbo:load` fires on every Turbo navigation.

## Turbo Frames

A Turbo Frame is a portion of the page that updates independently. Wrap the region in `<turbo-frame id="...">`:

```erb
<%# app/views/posts/show.html.erb %>
<turbo-frame id="post_<%= @post.id %>">
  <%= render @post %>
  <%= link_to 'Edit', edit_post_path(@post) %>
</turbo-frame>
```

When the user clicks Edit, Rails renders the edit page; Turbo finds the matching `<turbo-frame id="post_42">` in the response and swaps only that region. The rest of the page is untouched.

**Lazy-loaded frames** (server-side render only when scrolled into view):

```erb
<turbo-frame id="recommendations" src="<%= recommendations_path %>" loading="lazy">
  <p>Loading recommendations…</p>
</turbo-frame>
```

## Turbo Streams

Turbo Streams update parts of the page in response to user actions (form submit) or server events (WebSocket broadcast). Seven actions:

| Action  | Effect |
|---------|--------|
| `append`  | Append children to the target |
| `prepend` | Prepend children to the target |
| `replace` | Replace the entire target element |
| `update`  | Replace target's innerHTML, keep the wrapper |
| `remove`  | Remove the target |
| `before`  | Insert siblings before the target |
| `after`   | Insert siblings after the target |

```erb
<%# app/views/comments/create.turbo_stream.erb %>
<%= turbo_stream.append 'comments', partial: 'comment', locals: { comment: @comment } %>
<%= turbo_stream.update 'comment-count', @post.comments.count %>
<%= turbo_stream.replace 'new-comment-form', partial: 'form', locals: { comment: Comment.new } %>
```

```ruby
# app/controllers/comments_controller.rb
def create
  @comment = @post.comments.create!(comment_params)
  respond_to do |format|
    format.turbo_stream     # renders create.turbo_stream.erb
    format.html { redirect_to @post }
  end
end
```

## Broadcasting Streams via ActionCable

Push updates from anywhere in the server (controllers, jobs, models) over WebSocket:

```ruby
# app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :post
  after_create_commit -> { broadcast_append_to post, target: 'comments' }
  after_update_commit -> { broadcast_replace_to post }
  after_destroy_commit -> { broadcast_remove_to post }
end
```

```erb
<%# app/views/posts/show.html.erb %>
<%= turbo_stream_from @post %>      <%# subscribe to broadcasts on this post's stream %>
<div id="comments">
  <%= render @post.comments %>
</div>
```

Rails 8 default cable adapter is `solid_cable` (DB-backed) — no Redis required for low-throughput apps.

## Morphing (Rails 8)

Rails 8 ships morphing Turbo by default — DOM diffing instead of full element replacement, preserving form state and focus:

```erb
<%= turbo_stream.morph @post %>
<%# or per-frame: %>
<turbo-frame id="post_42" refresh="morph"></turbo-frame>
```

Pages also support page refreshes via `<meta name="turbo-refresh-method" content="morph">` so a back-button navigation morphs the body instead of replacing it.

## Stimulus Controllers

Stimulus controllers attach behaviour to data attributes. Filename and identifier are kebab-case:

```js
// app/javascript/controllers/dropdown_controller.js
import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  static targets = ['menu']
  static values = { open: { type: Boolean, default: false } }
  static classes = ['hidden']

  connect() {
    // runs when controller attaches to the DOM
  }

  toggle() {
    this.openValue = !this.openValue
    this.menuTarget.classList.toggle(this.hiddenClass, !this.openValue)
  }

  disconnect() {
    // runs when controller detaches (Turbo navigation, element removal)
  }
}
```

```erb
<div data-controller="dropdown" data-dropdown-hidden-class="hidden">
  <button data-action="click->dropdown#toggle">Menu</button>
  <ul data-dropdown-target="menu" class="hidden">
    <li>Profile</li>
  </ul>
</div>
```

**Naming:** controller files end with `_controller.js`; identifiers omit the suffix (`dropdown_controller.js` → `data-controller="dropdown"`).

## Dos

- Pin Stimulus controllers via `bin/importmap pin @hotwired/stimulus` (or include via jsbundling) — never copy-paste the source
- One Stimulus controller per responsibility (`dropdown`, `clipboard`, `autocomplete`) — never a `helpers` god controller
- Use `data-action="click->dropdown#toggle"` syntax for explicit event binding — never inline `onclick`
- Wrap interactive regions in Turbo Frames so updates don't re-render the whole page
- Broadcast streams from `after_*_commit` (not `after_save`) — fires after the transaction commits, ensuring downstream consumers see persisted data
- Use `bin/rails dev:cache` to toggle the development cache when testing fragment caching with Turbo

## Don'ts

- Don't put business logic in Stimulus controllers — keep them presentational; logic belongs server-side
- Don't broadcast from `after_save` — fires inside the transaction; subscribers may query stale data
- Don't use Turbo Streams for full-page navigation — use Turbo Drive (a regular link) instead
- Don't disable Turbo globally just to fix one edge case — opt out per-link with `data-turbo="false"`
- Don't share Stimulus controller state across instances via module-scope variables — each `<div data-controller="...">` gets its own instance
- Don't broadcast PII in stream payloads — anyone subscribed to the stream can intercept; scope streams per-user (`turbo_stream_from current_user`)
