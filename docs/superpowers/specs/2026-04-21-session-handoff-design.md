# Session Handoff — Design Spec

**Date:** 2026-04-21
**Author:** Denis Šajnar (with brainstorming assistance)
**Status:** Draft — pending user review
**Supersedes:** none
**Related docs:** `shared/context-condensation.md`, `shared/context_guard.py`, `shared/error-taxonomy.md`, `hooks/_py/check_engine/compact_check.py`

## Problem

Long Claude Code sessions accumulate context from forge pipeline activity, multi-stage task reports, AskUserQuestion dialogs, and accumulated tool output. The existing `compact_check.py` hook emits a stderr hint at 180K tokens suggesting `/compact`, and `context_guard.py` tracks tokens and triggers inner-loop condensation during convergence. Neither offers the user a way to preserve their session's state for continuation elsewhere.

Two concrete user problems today:

1. **Pipeline handoff** — `/forge-run` on a multi-stage feature, session context is getting heavy, user wants to carry the run state into a fresh Claude Code session without losing progress.
2. **Conversation handoff** — user's Claude Code session in this repo is getting heavy (could be a forge run, could be general editing/exploration), wants a portable paste-able prompt for a fresh session.

Industry convention (softaworks, JD Hodges, Blake Link, LangGraph, Claude official docs) converges on a structured markdown handoff file with a machine-readable header and a human narrative body. Forge already has the machine half solved via `run_id`, checkpoint DAG, and `/forge-recover resume`. The missing piece is the human-facing artefact + an interactive/autonomous trigger path.

## Non-goals

- Replacing F08 context condensation. F08 summarises *within* the orchestrator's agent context; handoffs address the *user's outer Claude Code session*.
- Live cross-tool session transfer (Cursor ↔ Claude Code etc.). The file is paste-able, which is good enough.
- Multi-machine sync. Handoffs live in `.forge/runs/<run_id>/handoffs/` — co-located with the repo, follow normal git worktree rules.
- New LLM calls for summarisation. Handoff generation is deterministic Python; body sections project from existing F08 retention tags and state.json.

## Approach

A thin projection layer over existing forge state, exposed as a file that's both machine-readable (YAML frontmatter) and human-pasteable (markdown body + explicit RESUME PROMPT block). Two trigger levels (soft / hard), both write-and-continue in autonomous mode; interactive mode pauses at hard via a new `CONTEXT_CRITICAL` safety escalation.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  USER'S CLAUDE CODE SESSION                                   │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  /forge-run (or general usage)                         │  │
│  │                                                         │  │
│  │  PostToolUse(Agent) → hooks/post_tool_use_agent.py     │  │
│  │    └→ hooks/_py/check_engine/compact_check.py          │  │
│  │         └→ shared/context_guard.py check <tokens>      │  │
│  │             ├─ OK        (< 50%)                        │  │
│  │             ├─ SOFT      (≥ 50%) → handoff/writer.py   │  │
│  │             └─ CRITICAL  (≥ 70%) → handoff/writer.py   │  │
│  │                                   + escalation         │  │
│  └────────────────────────────────────────────────────────┘  │
│                          │                                    │
│                          ↓                                    │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  hooks/_py/handoff/writer.py                           │  │
│  │    ├─ read state.json, F08 tags, PREEMPT, decisions   │  │
│  │    ├─ redact via data-classification                  │  │
│  │    ├─ render frontmatter + body + resume block       │  │
│  │    ├─ write .forge/runs/<id>/handoffs/<name>.md      │  │
│  │    ├─ append to state.json.handoff.chain             │  │
│  │    ├─ write .forge/alerts.json (HANDOFF_WRITTEN)     │  │
│  │    └─ index into run-history.db (FTS5)               │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                           │
                           ↓  (later, fresh session)
┌──────────────────────────────────────────────────────────────┐
│  FRESH CLAUDE CODE SESSION                                    │
│                                                               │
│  Path A: /forge-handoff resume <path>                         │
│    ├─ parse frontmatter, validate schema                      │
│    ├─ staleness check (git_head, checkpoint_sha)             │
│    ├─ seed state.json                                         │
│    └─ delegate to /forge-recover resume <run_id>             │
│                                                               │
│  Path B: user pastes RESUME PROMPT block                      │
│    └─ fresh session reads narrative + Critical Files         │
│       and proceeds — works without forge installed            │
│                                                               │
│  Path C: /forge-handoff resume (no args)                      │
│    └─ picks latest un-SHIPPED handoff automatically          │
└──────────────────────────────────────────────────────────────┘
```

## Components

### 1. `hooks/_py/handoff/writer.py` (new)

Deterministic Python module. Inputs: `run_id`, `level`, `reason`. Reads from:

- `.forge/runs/<run_id>/state.json` (canonical pipeline state)
- F08 retention tags (`active_findings`, `acceptance_criteria`, `user_decisions`, `convergence_trajectory`, `test_status`, `active_errors`)
- `.forge/runs/<run_id>/decisions.jsonl`
- `.forge/learnings/` (PREEMPT items)
- `.forge/runs/<run_id>/checkpoints/<head_checkpoint>`
- `git rev-parse HEAD` + `git diff --stat <base>...HEAD`

Outputs: a markdown file at `.forge/runs/<run_id>/handoffs/<timestamp>-<level>-<slug>.md`.

**Never calls an LLM.** All prose is rendered from structured inputs. If prose looks terse or mechanical, that's the correct tradeoff — it's reproducible and cheap.

**Size enforcement:**

- Light variant (milestone, soft): cap at 3K tokens (~12KB).
- Full variant (hard, terminal, manual): cap at 15K tokens (~60KB).
- Truncation order when over cap: Convergence Trajectory → Key Decisions → oldest Active Findings → oldest Critical Files. Goal / Next Action / Do Not Touch / User Directive are **never** truncated.

**Redaction:** pipe every string that will be written through `shared/data-classification.md` redactor before emitting. Replace detected secrets with `[REDACTED:<type>]`.

### 2. `hooks/_py/handoff/resumer.py` (new)

Parses a handoff file, performs staleness checks, seeds state.json, hands off to `/forge-recover resume`.

**Staleness matrix:**

| `git_head` match | `checkpoint_sha` match | Interactive behaviour | Autonomous behaviour |
|---|---|---|---|
| ✓ | ✓ | Resume directly | Resume directly |
| ✗ (commits added) | ✓ | AskUserQuestion: Rebase / Force / Abort | Refuse. Write `HANDOFF_STALE` alert, exit non-zero. |
| ✓ | ✗ (checkpoint gone) | Warn, fall through to Path B (narrative-only) | Warn, fall through to Path B |
| ✗ | ✗ | AskUserQuestion: Narrative-only / Abort | Refuse. Write `HANDOFF_STALE` alert, exit non-zero. |

Rationale for autonomous refusal: auto-resuming across commits can reference files that have moved or been deleted. Safer to surface as an alert and let the user decide.

### 3. `hooks/_py/check_engine/compact_check.py` (extended)

Current behaviour (keep): emit stderr hint at 180K tokens.

Add:

- Read `handoff.*` config from `forge-config.md`.
- Compute utilisation against current model's context window (via `shared/context-condensation.md` model window table).
- At `soft_threshold_pct` (default 50): dispatch `handoff/writer.py` with `level=soft`, `reason=context_soft_50pct`, if last handoff was > `min_interval_minutes` ago. In interactive mode also fire an AskUserQuestion offering handoff-then-stop. In autonomous/background: write and continue silently.
- At `hard_threshold_pct` (default 70): dispatch writer with `level=hard`. Interactive: raise `CONTEXT_CRITICAL` safety escalation, pipeline pauses at next stage boundary. Autonomous/background: write and continue, no pause.

### 4. `hooks/_py/handoff/milestones.py` (new)

Hooks into orchestrator stage transitions. At each of: EXPLORING→PLANNING, PLANNING→VALIDATING, VALIDATING→IMPLEMENTING, IMPLEMENTING→VERIFYING, VERIFYING→REVIEWING, REVIEWING→DOCUMENTING, DOCUMENTING→SHIPPING, SHIPPING→LEARNING, plus `feedback_loop_count >= 2` escalation and terminal states (SHIP / ABORT / FAIL) — dispatch writer with `level=milestone` or `level=terminal`.

Rate-limited by `min_interval_minutes` except terminal which always fires.

### 5. `skills/forge-handoff.md` (new)

Subcommands:

| Subcommand | Behaviour |
|---|---|
| `/forge-handoff` | Manual full handoff now. Interactive: AskUserQuestion picks slug from current stage context. Autonomous: silently writes with auto-generated slug. |
| `/forge-handoff list [--run <id>]` | Shows handoff chain for current or specified run. |
| `/forge-handoff show <path\|latest>` | Prints handoff contents. |
| `/forge-handoff resume [<path>]` | Path A structured resume; no arg → Path C (auto-pick latest un-SHIPPED). |
| `/forge-handoff search <query>` | FTS5 search over `run-history.db` handoff index. |

### 6. `shared/mcp-server/` (extended, F30)

Two new read-only tools:

- `forge_list_handoffs(run_id: str | None)` → list of handoff metadata (path, level, created_at, reason, score).
- `forge_get_handoff(path: str)` → full handoff content.

Enables any MCP client to introspect forge handoff chains — not just Claude Code.

### 7. `shared/error-taxonomy.md` (extended)

New entry `CONTEXT_CRITICAL`:

- Type: safety escalation (joins REGRESSING, E1-E4).
- Severity: WARNING (not unrecoverable).
- Trigger: interactive mode only, `hard_threshold_pct` reached.
- Recovery: pause at next stage boundary, write alert, await user resume.
- **Autonomous exception:** `CONTEXT_CRITICAL` is explicitly excluded from autonomous-bypass list. In autonomous it is logged but does not pause.

### 8. Auto-memory flow (extended — reuses existing system)

On terminal handoff (SHIP / ABORT / FAIL), the writer extracts:

- Top 3 PREEMPT items with HIGH confidence.
- `tag:user_decisions` content from this run.

And writes them as memory entries under `~/.claude/projects/<project-hash>/memory/` using the existing auto-memory format (project type, not feedback — they're run-derived facts). Prefix filenames with `forge_handoff_`.

Rationale: handoff knowledge persists across forge runs even without explicit resume — auto-memory surfaces it in any future conversation in this repo.

## Data model

### File naming

```
.forge/runs/<run_id>/handoffs/<YYYY-MM-DD-HHMMSS>-<level>-<slug>.md
```

- `<level>` ∈ `{soft, hard, milestone, terminal, manual}`
- `<slug>` derived from requirement or stage name, sanitised to `[a-z0-9-]`, truncated to 40 chars
- Same-second collision: append `-2`, `-3`, etc.
- Rotation: when chain length exceeds `chain_limit` (default 50), move oldest to `handoffs/archive/` (still FTS5-indexed)

### Frontmatter schema

```yaml
schema_version: 1.0              # increment on breaking changes
handoff_version: 1.0
run_id: 20260421-a3f2
parent_run_id: null              # non-null if this run is itself resumed from another
stage: REVIEWING
substage: quality_gate_batch_2
mode: standard                   # standard|migration|bugfix|bootstrap|refactor|performance|testing
autonomous: false
background: false
score: 82
score_history: [45, 61, 74, 82]
convergence_phase: perfection
convergence_counters:
  total_iterations: 7
  phase_iterations: 3
  verify_fix_count: 1
checkpoint_sha: 7af9c3d0...
checkpoint_path: .forge/runs/20260421-a3f2/checkpoints/7af9c3d0
branch_name: feat/FG-142-add-health
worktree_path: .forge/worktree
git_head: abd3d25a
commits_since_base: 3
open_askuserquestion: null
previous_handoff: .forge/runs/20260421-a3f2/handoffs/2026-04-21-120000-milestone-explore.md
trigger:
  level: soft                    # soft|hard|milestone|terminal|manual
  reason: context_soft_50pct
  threshold_pct: 52
  tokens: 104000
created_at: 2026-04-21T14:30:22Z
```

### Body section inventory

| Section | Source | Light variant | Full variant | Truncatable |
|---|---|---|---|---|
| Goal | `state.json.requirement` + shaped spec | 1 para | 1 para | no |
| Progress | Completed ACs + files + test status | 1 para | bullets | last-first |
| Active Findings | `tag:active_findings`, dedup `(file, line, category)` | top 5 | all, severity-ordered | oldest-first |
| Acceptance Criteria Status | `tag:acceptance_criteria` + living specs registry | — | per-AC table | yes |
| Key Decisions | `decisions.jsonl` filtered outcome-affecting | — | last 20 | oldest-first |
| Do Not Touch | PREEMPT items + user_decisions "don't" | ✓ | ✓ | no |
| Next Action | State machine peek | ✓ | ✓ | no |
| Convergence Trajectory | `tag:convergence_trajectory` | — | one line per iter | oldest-first |
| Critical Files | Files touched this run + watched files | top 10 | all | oldest-first |
| Open Questions / Blockers | Silenced autonomous AUQ + escalations | ✓ | ✓ | no |
| User Directive | Empty placeholder | ✓ | ✓ | no |

### Alert schema (`.forge/alerts.json`)

```json
{
  "type": "HANDOFF_WRITTEN",
  "level": "soft|hard|milestone|terminal|manual",
  "run_id": "20260421-a3f2",
  "path": ".forge/runs/20260421-a3f2/handoffs/2026-04-21-143022-soft-add-health.md",
  "reason": "context_soft_50pct | context_hard_70pct | stage_transition | feedback_escalation | ship | abort | fail | manual",
  "created_at": "2026-04-21T14:30:22Z",
  "resume_prompt_preview": "I'm resuming a forge run from a handoff..."
}
```

Additional alert type: `HANDOFF_STALE` written when autonomous resume refuses due to drift.

### State.json additions

```json
{
  "handoff": {
    "last_written_at": "2026-04-21T14:30:22Z",
    "last_path": ".forge/runs/.../handoffs/....md",
    "chain": [
      ".forge/runs/.../handoffs/2026-04-21-120000-milestone-explore.md",
      ".forge/runs/.../handoffs/2026-04-21-143022-soft-add-health.md"
    ],
    "soft_triggers_this_run": 2,
    "hard_triggers_this_run": 0,
    "milestone_triggers_this_run": 5,
    "suppressed_by_rate_limit": 1
  }
}
```

Bump `state-schema.md` version 1.9.0 → 1.10.0.

## Configuration

```yaml
handoff:
  enabled: true
  soft_threshold_pct: 50            # default 50 (was 70 in earlier draft)
  hard_threshold_pct: 70            # default 70 (was 90 in earlier draft)
  min_interval_minutes: 15
  autonomous_mode: auto             # auto | milestone_only | disabled
  auto_on_ship: true
  auto_on_escalation: true          # feedback_loop_count >= 2
  chain_limit: 50
  auto_memory_promotion: true       # terminal handoffs push top PREEMPTs to user auto-memory
  mcp_expose: true                  # expose handoffs via MCP server
```

### PREFLIGHT constraints (add to `shared/preflight-constraints.md`)

| Parameter | Range | Rationale |
|---|---|---|
| `soft_threshold_pct` | 30-80 | Below 30 → noise storm; above 80 → overlaps with hard |
| `hard_threshold_pct` | `soft + 10` to 95 | Must be strictly greater than soft by margin; max 95 to leave recovery room |
| `min_interval_minutes` | 1-60 | Prevents storm in fast pipelines |
| `chain_limit` | 5-500 | Practical bounds for rotation |
| `autonomous_mode` | `auto` \| `milestone_only` \| `disabled` | Enumerated |

## Triggers — unified table

| Trigger | Interactive behaviour | Autonomous behaviour | Level |
|---|---|---|---|
| Tokens ≥ `soft_threshold_pct` (50%) | AskUserQuestion: Continue / Compact / Handoff+new session / Handoff+stop | Auto-write, continue pipeline, log `[AUTO handoff-soft]` | soft |
| Tokens ≥ `hard_threshold_pct` (70%) | AskUserQuestion: Handoff+stop / Try /compact / Abort; raise `CONTEXT_CRITICAL`, pause at stage boundary | Auto-write, continue pipeline, log `[AUTO handoff-hard]`, NO pause | hard |
| Stage transition | Opportunistic (only if last handoff > 2h old) | Always, rate-limited | milestone |
| `feedback_loop_count >= 2` | AskUserQuestion: Handoff+escalate / Retry / Abort | Auto-write, raise escalation per existing rules | milestone |
| SHIP / ABORT / FAIL | Always (ignore rate limit) | Always | terminal |
| `/forge-handoff` (user-invoked) | AskUserQuestion picks slug | Silently writes | manual |

## Error handling

| Scenario | Behaviour |
|---|---|
| Writer fails mid-write | Atomic rename from `.tmp` suffix; on failure, leave `.tmp` and log ERROR |
| Redactor fails | Log ERROR, do NOT write handoff (fail-closed — never write unredacted secrets) |
| FTS5 index full | Log WARNING, skip indexing, file still written |
| State.json missing | No-op — we're not in a forge run; user can still `/forge-handoff` manually in general sessions |
| Same-second collision | Append `-2`, `-3` suffix up to 10; beyond → log ERROR |
| Size cap exceeded after all truncations | Truncate to cap with `<!-- TRUNCATED at cap -->` marker |
| Resume staleness in autonomous | Refuse, write `HANDOFF_STALE` alert, exit non-zero |
| Resume staleness in interactive | AskUserQuestion per staleness matrix |

## Testing

### Unit tests

- `tests/unit/handoff-writer.bats` — frontmatter correctness, body section rendering, size cap enforcement, truncation order, redaction invocation
- `tests/unit/handoff-resumer.bats` — staleness matrix, state.json seeding, delegation to forge-recover
- `tests/unit/handoff-config.bats` — PREFLIGHT constraint validation

### Contract tests

- `tests/contract/handoff-schema.bats` — frontmatter schema v1.0 validation
- `tests/contract/handoff-alerts.bats` — alert schema `HANDOFF_WRITTEN` and `HANDOFF_STALE`
- `tests/contract/handoff-state.bats` — `state.json.handoff.*` shape

### Scenario tests

- `tests/scenario/handoff-soft-interactive.bats` — 50% threshold → AskUserQuestion mock → user picks handoff → file exists, chain updated
- `tests/scenario/handoff-hard-autonomous.bats` — 70% threshold → no pause, file written, alert present, pipeline continued
- `tests/scenario/handoff-terminal.bats` — SHIP → terminal handoff written → auto-memory populated
- `tests/scenario/handoff-resume-clean.bats` — resume with matching git_head + checkpoint_sha → state seeded, delegates to recover
- `tests/scenario/handoff-resume-stale-autonomous.bats` — drifted HEAD in autonomous → refuse, alert written
- `tests/scenario/handoff-chain.bats` — multiple handoffs per run, chain pointers intact, rotation past `chain_limit`
- `tests/scenario/handoff-mcp.bats` — MCP tools return expected shape

## Open questions for review

None. All key decisions resolved:

- Scope: both modes (pipeline + general conversation)
- Thresholds: 50% soft / 70% hard
- Autonomous: always write-and-continue, never pause
- Auto-memory promotion: enabled
- MCP exposure: enabled
- Staleness in autonomous: refuse + `HANDOFF_STALE` alert
- No new LLM calls (deterministic Python)
- Single file per handoff (frontmatter + body + resume block)

## Rollout

1. Ship behind `handoff.enabled: false` default for first release (opt-in).
2. One forge release cycle as opt-in; collect feedback via auto-memory + `.forge/alerts.json` inspection.
3. Flip default to `true` in next minor release.
4. MCP tools gated by `handoff.mcp_expose: true` from day one.

## References

- softaworks session-handoff skill: <https://github.com/softaworks/agent-toolkit/blob/main/skills/session-handoff/README.md>
- JD Hodges handoff prompt template: <https://www.jdhodges.com/blog/ai-session-handoffs-keep-context-across-conversations/>
- Blake Link Session Handoff Protocol: <https://blakelink.us/posts/session-handoff-protocol-solving-ai-agent-continuity-in-complex-projects/>
- Claude Code 1M context session management: <https://claude.com/blog/using-claude-code-session-management-and-1m-context>
- LangGraph persistence + checkpointing: <https://docs.langchain.com/oss/python/langgraph/persistence>

## Self-review checklist (completed inline)

- [x] **Placeholders:** none — all sections populated
- [x] **Internal consistency:** thresholds 50/70 consistent across Triggers, PREFLIGHT, Config, unified table
- [x] **Scope:** focused single implementation plan; estimate 600-800 LOC + tests
- [x] **Ambiguity:** autonomous-hard behaviour explicitly "write and continue, no pause"; staleness matrix explicit per mode; truncation order explicit; fail-closed on redactor failure
