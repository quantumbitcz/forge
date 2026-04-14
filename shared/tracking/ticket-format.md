# Ticket Format Reference

Defines the kanban ticket ID format used in `.forge/tracking/`.

## Ticket ID Format

```
{PREFIX}-{NNN}
```

- **PREFIX**: Configurable, default `FG`. Set via `tracking.prefix` in `forge-config.md`.
- **NNN**: Zero-padded 3-digit counter (e.g., `001`, `042`, `123`). Auto-incremented.

Examples: `FG-001`, `FG-042`, `FG-123`.

## Filename Format

```
{PREFIX}-{NNN}-{slug}.md
```

- **slug**: Lowercase, hyphen-separated summary derived from the ticket title.
- Example: `FG-042-add-user-authentication.md`

## Counter File

```
.forge/tracking/.counter
```

Plain text file containing the next available ticket number. Atomically incremented when a new ticket is created. Never decremented.

## Status Directories

```
.forge/tracking/
  ├── backlog/        # Tickets not yet started
  ├── in-progress/    # Tickets currently being worked on
  ├── review/         # Tickets awaiting review
  └── done/           # Completed tickets
```

Tickets move between directories as their status changes. A ticket file exists in exactly one directory at a time.

## Ticket File Structure

```markdown
---
id: FG-042
title: Add user authentication
status: in-progress
created: 2026-04-14T10:30:00Z
branch: feat/FG-042-add-user-authentication
---

Description of the work item.
```

Frontmatter fields:
- `id` (required): Ticket ID matching filename prefix
- `title` (required): Human-readable title
- `status` (required): Current status (backlog, in-progress, review, done)
- `created` (required): ISO 8601 timestamp
- `branch` (optional): Associated git branch name

## Archival

Completed tickets are archived after `tracking.archive_after_days` (default 90, range 30-365, 0 = disabled). Archived tickets move to `.forge/tracking/archive/` and are excluded from active board queries.

## Rules

1. IDs are **never reused** -- even after archival.
2. Operations **silently skip** if tracking is not initialized (no `.forge/tracking/` directory).
3. The prefix is set once at `/forge-init` and should not change mid-project.
4. Counter file must be updated atomically to prevent duplicate IDs in sprint mode.

## Related

- `shared/tracking/tracking-schema.md` -- Full tracking state schema
- `shared/tracking/tracking-ops.sh` -- Tracking operations script
- `shared/git-conventions.md` -- Branch naming uses ticket IDs
