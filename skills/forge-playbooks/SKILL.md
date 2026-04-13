---
name: forge-playbooks
description: "List available playbooks with usage stats and parameter details. Use when you want to see what playbooks are available, check playbook analytics, or find the right playbook for a task."
allowed-tools: ['Read', 'Bash', 'Glob']
---

# /forge-playbooks -- List Available Playbooks

List all available playbooks (project-specific and built-in) with their descriptions, parameter details, and usage analytics.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Playbooks enabled:** Read `playbooks.enabled` from `forge-config.md`. If `false`: report "Playbooks are disabled. Set `playbooks.enabled: true` in forge-config.md." and STOP.

## Instructions

### 1. Discover Playbooks

Scan both playbook directories:

1. **Project playbooks:** Read `playbooks.directory` from `forge-config.md` (default: `.claude/forge-playbooks`). Glob for `*.md` files in that directory.
2. **Built-in playbooks:** Glob for `*.md` files in `${CLAUDE_PLUGIN_ROOT}/shared/playbooks/`.
3. Merge lists. If a project playbook has the same name as a built-in, the project version wins. Mark overridden built-ins with "(overridden by project)".

### 2. Parse Playbook Metadata

For each discovered playbook:

1. Read the YAML frontmatter to extract: `name`, `description`, `version`, `parameters`, `tags`, `acceptance_criteria`.
2. Validate that `name` matches the filename (sans `.md`). If mismatch, note it as a warning.
3. Count the number of acceptance criteria.
4. Count the number of parameters (required vs optional).

### 3. Load Analytics

1. Check if `.forge/playbook-analytics.json` exists.
2. If it exists, read it and match playbook entries by name.
3. Extract per-playbook: `run_count`, `success_count`, `avg_score`, `last_used`.
4. If analytics file does not exist or is corrupt, report "No analytics data yet" for all playbooks.

### 4. Format Output

Display playbooks grouped by source (project first, then built-in):

```markdown
## Available Playbooks

### Project Playbooks (.claude/forge-playbooks/)

| Playbook | Description | Params | Runs | Avg Score | Last Used |
|----------|-------------|--------|------|-----------|-----------|
| `{name}` | {description} | {required}/{total} | {run_count} | {avg_score} | {last_used or "never"} |

### Built-In Playbooks

| Playbook | Description | Params | Runs | Avg Score | Last Used |
|----------|-------------|--------|------|-----------|-----------|
| `{name}` | {description} | {required}/{total} | {run_count} | {avg_score} | {last_used or "never"} |

---

### Usage

To run a playbook:
  /forge-run --playbook={name} param1=value1 param2=value2

To see playbook details:
  /forge-playbooks {name}
```

### 5. Detail View (Optional)

If `$ARGUMENTS` contains a playbook name, show the detailed view for that specific playbook:

```markdown
## Playbook: {name}

**Description:** {description}
**Version:** {version}
**Mode:** {mode}
**Tags:** {tags | join:", "}
**Source:** {project or built-in}

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `{name}` | {type} | {yes/no} | {default or "-"} | {description} |

### Acceptance Criteria

1. {ac_1}
2. {ac_2}
...

### Review Focus

- Categories: {focus_categories | join:", "}
- Min score: {min_score}
- Review agents: {review_agents | join:", "}

### Analytics

| Metric | Value |
|--------|-------|
| Total runs | {run_count} |
| Success rate | {success_count}/{run_count} ({pct}%) |
| Average score | {avg_score} |
| Average iterations | {avg_iterations} |
| Average duration | {avg_duration_seconds}s |
| Average cost | ${avg_cost_usd} |
| Last used | {last_used} |

### Common Findings

| Category | Occurrences |
|----------|-------------|
| {category} | {count} |

### Example

  /forge-run --playbook={name} {example_params}
```

## Important

- This is READ-ONLY. Never modify playbook files or analytics.
- Always show clickable file paths for each playbook.
- If no playbooks exist (no project playbooks and built-ins disabled), report: "No playbooks available. Create playbooks in `.claude/forge-playbooks/` or enable built-in playbooks with `playbooks.builtin_playbooks: true`."
- Analytics data may be absent for new playbooks. Show "never" and "0" for playbooks without runs.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| No playbooks found | Report "No playbooks available" with instructions to create or enable built-ins |
| Playbook frontmatter invalid | Skip playbook, log WARNING with filename and parse error |
| Analytics file corrupt | Report "Analytics data unavailable (corrupt file)" and list playbooks without stats |
| Playbook name mismatch | Log WARNING: "Playbook {filename} has name={name} in frontmatter (should match filename)" |
| Requested detail view for nonexistent playbook | Report "Playbook '{name}' not found" and list available playbooks |

## See Also

- `/forge-run --playbook={name}` -- Run a specific playbook
- `/forge-shape` -- Shape a requirement that could become a playbook
- `/forge-insights` -- Cross-run analytics including playbook effectiveness
- `shared/playbooks.md` -- Playbook format specification and interpolation syntax
