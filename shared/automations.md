# Automations Contract

Event-driven pipeline triggers that fire forge skills in response to external events. All triggers use Claude Code primitives (CronCreate, RemoteTrigger, PostToolUse hooks) or MCP polling — there are no true push webhooks.

## Trigger Types

| Trigger | Primitive | Dependencies | Latency | Example |
|---------|-----------|--------------|---------|---------|
| `cron` | `CronCreate` | None | Scheduled | Nightly health check |
| `ci_failure` | `RemoteTrigger` / GitHub Actions | CI workflow | Event-driven | Auto-fix on red build |
| `pr_opened` | `RemoteTrigger` / GitHub Actions | CI workflow | Event-driven | Auto-review on new PR |
| `dependabot_pr` | `RemoteTrigger` / GitHub Actions | Dependabot + CI workflow | Event-driven | Auto-merge safe updates |
| `linear_status` | MCP polling | Linear MCP | Poll interval | Trigger pipeline on ticket transition |
| `file_changed` | `PostToolUse` hook | None | Immediate | Re-lint on file save |

**Important:** `ci_failure`, `pr_opened`, and `dependabot_pr` all rely on a GitHub Actions workflow that invokes Claude Code via `RemoteTrigger`. They are not native webhooks — the CI runner calls into the Claude Code session. `linear_status` uses MCP polling at the interval configured in `sprint.poll_interval_seconds` (default 30s). `cron` uses the Claude Code `CronCreate` primitive directly with no external dependencies.

## Automation Definition Schema

Each automation is a YAML object in the `automations:` array in `forge-config.md`:

```yaml
automations:
  - name: "ci-failure-fix"
    trigger: ci_failure
    action: forge-fix
    filter:
      branch: "main"
      workflow: "ci.yml"
    cooldown_minutes: 30

  - name: "pr-review"
    trigger: pr_opened
    action: forge-review
    filter:
      base_branch: "main"
      exclude_authors:
        - "dependabot[bot]"
    cooldown_minutes: 5

  - name: "scheduled-health"
    trigger: cron
    action: codebase-health
    filter:
      cron: "0 3 * * 1"
    cooldown_minutes: 1440
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Unique identifier for this automation. Used as cooldown key and in logs. |
| `trigger` | enum | Yes | One of: `cron`, `ci_failure`, `pr_opened`, `dependabot_pr`, `linear_status`, `file_changed` |
| `action` | string | Yes | Forge skill name to invoke (e.g. `forge-fix`, `forge-review`, `codebase-health`, `forge-run`, `security-audit`) |
| `filter` | object | No | Trigger-specific filter criteria. Unmatched events are ignored. |
| `cooldown_minutes` | integer | Yes | Minimum minutes between consecutive firings of this automation. See Cooldown Rules. |
| `enabled` | boolean | No | Default `true`. Set `false` to disable without removing the definition. |

### Filter Fields by Trigger

| Trigger | Filter Field | Type | Description |
|---------|-------------|------|-------------|
| `cron` | `cron` | string | Cron expression (5-field). Required for cron triggers. |
| `ci_failure` | `branch` | string | Branch name or glob pattern |
| `ci_failure` | `workflow` | string | Workflow filename |
| `pr_opened` | `base_branch` | string | Target branch name or glob |
| `pr_opened` | `exclude_authors` | array | Author logins to skip |
| `dependabot_pr` | `base_branch` | string | Target branch name or glob |
| `dependabot_pr` | `dependency_type` | string | `production` or `development` |
| `linear_status` | `from_status` | string | Previous status name |
| `linear_status` | `to_status` | string | New status name |
| `file_changed` | `glob` | string | File glob pattern (e.g. `src/**/*.ts`) |
| `file_changed` | `exclude_glob` | string | Exclusion glob |

## Safety Constraints

1. **Cooldown per automation** — Each automation has a per-name cooldown timer. A trigger arriving during an active cooldown is silently dropped and logged as `skipped_cooldown`.
2. **Max 3 concurrent automations** — At most 3 automation-triggered skill invocations may run simultaneously. Additional triggers queue and execute when a slot opens. Queue depth is unbounded but logged.
3. **Destructive actions require human approval** — Any automation whose `action` would modify code (`forge-run`, `forge-fix`, `deep-health`, `migration`) pauses for user confirmation via `AskUserQuestion` before proceeding. Read-only actions (`codebase-health`, `forge-review`, `forge-status`, `security-audit`, `forge-diagnose`) execute without confirmation.
4. **No automation chaining** — An automation-triggered skill cannot itself fire another automation. The `triggered_by` field in the log prevents re-entrant loops.
5. **Graceful degradation** — If the skill invocation fails, the error is logged and the cooldown timer still resets. Repeated failures (3 consecutive for the same automation) disable the automation for the remainder of the session and log a WARNING.

## Cooldown Rules

- Each automation maintains an independent cooldown timer keyed by `name`.
- The timer starts when the skill invocation **completes** (success or failure), not when it starts.
- During cooldown, matching triggers are dropped and logged with `result: "skipped_cooldown"`.
- The `cooldown_minutes` value must be >= 1. Values below 1 are clamped to 1 and a WARNING is logged at PREFLIGHT.
- Cooldown state is held in memory only — it does not survive session restarts.

## Logging

All automation events are appended to `.forge/automation-log.jsonl` (JSON Lines, one object per line). Created on first write. Gitignored with the rest of `.forge/`.

### Log Entry Schema

```json
{
  "ts": "2026-04-12T03:00:01.234Z",
  "automation": "scheduled-health",
  "trigger": "cron",
  "action": "codebase-health",
  "result": "success",
  "duration_ms": 45200,
  "triggered_by": "cron",
  "error": null
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ts` | string (ISO 8601) | Yes | Timestamp of the event |
| `automation` | string | Yes | Automation `name` |
| `trigger` | string | Yes | Trigger type that fired |
| `action` | string | Yes | Skill that was invoked |
| `result` | enum | Yes | One of: `success`, `failure`, `skipped_cooldown`, `skipped_concurrent`, `skipped_disabled`, `awaiting_approval` |
| `duration_ms` | integer | No | Wall-clock execution time (omitted for skipped events) |
| `triggered_by` | string | Yes | Origin context (e.g. `cron`, `github_actions`, `mcp_poll`, `hook`) |
| `error` | string | No | Error message on failure, `null` on success |

## CI Integration

GitHub Actions workflow that sends `RemoteTrigger` events to Claude Code on CI failure or PR open:

```yaml
# .github/workflows/forge-triggers.yml
name: Forge Triggers
on:
  workflow_run:
    workflows: ["CI"]
    types: [completed]
  pull_request:
    types: [opened]

jobs:
  notify-forge:
    runs-on: ubuntu-latest
    if: >
      (github.event_name == 'workflow_run' && github.event.workflow_run.conclusion == 'failure') ||
      github.event_name == 'pull_request'
    steps:
      - name: Trigger forge automation
        uses: anthropics/claude-code-action@v1
        with:
          trigger: >
            ${{ github.event_name == 'pull_request'
                && 'pr_opened'
                || 'ci_failure' }}
          context: |
            branch: ${{ github.head_ref || github.ref_name }}
            workflow: ${{ github.event.workflow_run.name || '' }}
            pr_number: ${{ github.event.pull_request.number || '' }}
```

This workflow uses `RemoteTrigger` under the hood. The forge automation engine matches the incoming trigger type and context against configured `filter` fields to decide which automation (if any) to fire.

## Configuration

Automations are configured in `forge-config.md` under the `automations:` key:

```yaml
automations: []
```

An empty array disables all automations (default). Each entry follows the Automation Definition Schema above. The orchestrator reads this array at PREFLIGHT and registers triggers accordingly. Invalid entries (missing required fields, unknown trigger types) are logged as WARNING and skipped — they do not block the pipeline.

Runtime state (cooldown timers, concurrent count, consecutive failure counts) is held in memory and not persisted to `.forge/state.json`. Session restart resets all automation state.
