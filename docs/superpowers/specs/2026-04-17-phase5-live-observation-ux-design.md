# Phase 5 — Live Observation UX (Design)

**Status:** Draft for review
**Date:** 2026-04-17
**Target version:** Forge 4.1.0 (SemVer minor — additive; no breaking changes)
**Author:** Denis Šajnar (authored with Claude Opus 4.7)
**Phase sequence:** 5 of 7
**Depends on:** Phase 4 merged (4.0.0). Phase 2's `.forge/events.jsonl` + sprint-mode per-run paths are load-bearing.

---

## 1. Goal

Ship the visible face of the pipeline: a curses TUI (`/forge-watch`) that consumes the Phase 2 event stream and renders stage progress, agent queue, cost, hook failures, and escalation prompts. Add plan branches so users can explore alternative approaches without destroying prior plans. Add `--best-of N` so users can run the same requirement across N model profiles and pick the winner. Add inline per-turn cost emission to stderr for users who don't open the TUI.

## 2. Context and motivation

April 2026 UX audit graded live observation **C−**. Specific gaps:

1. **No live consumer of `.forge/events.jsonl`.** Phase 2 established the stream; Phase 5 is the consumer.
2. **No pane UI.** Users see a flat text log; can't see "stage 5 / 10, $0.41 spent, fg-300 running, 2 agents queued" at a glance.
3. **No plan-branch primitive.** Phase 4 made plans editable but linear — one plan at a time.
4. **No model bake-off.** Users who want to compare opus/sonnet/haiku on the same requirement run manually with different configs — laborious and fragile.
5. **Cost is invisible unless TUI open.** Phase 2 streams to events.jsonl + session-start badge, but sessions don't refresh mid-run; a user staring at their terminal sees no turn-by-turn cost tick.

No backwards compatibility required.

## 3. Non-goals

- **No web UI / no browser dashboard.** TUI only. Web dashboard deferred to Phase 7+.
- **No new event types beyond what Phase 2 established.** Phase 5 is pure consumer.
- **No auto-selection of best-of-N winner by default.** User picks; `--auto-winner` flag opts in with quality-gate score as tiebreaker.
- **No branch merge between plans.** Branches are read-only explorations. To merge, user picks one as canonical and re-invokes with it as `current.md`.
- **No background TUI.** `/forge-watch` runs in the foreground until user exits with `q`.
- **No changes to orchestrator logic beyond flag parsing.** Plan-branch and best-of-N dispatch paths are additive orchestrator code.
- **Deferred:** FE UX (Phase 6), Go binary (Phase 7).

## 4. Design

### 4.1 `/forge-watch` TUI — `shared/forge-watch.py`

**Tech:** Python 3 stdlib `curses` only. Required-dep per Phase 3 prereq check.

**Panes (3-pane layout, terminal size ≥80×24):**

```
┌─ Run: 2026-04-17-feat-mfa ─── Stage 5/10 IMPLEMENTING ─── $0.41 / $5.00 cap ─┐
│ Progress ──────────────────────────┬─ Agent queue ─────────────────────────── │
│ ██████████░░░░░░░░░░ 50%           │ 🟢 fg-300 impl task 2/3 (in progress)    │
│ PREFLIGHT   ✓ 0:08                 │ ⬜ fg-500 test-gate (queued)              │
│ EXPLORING   ✓ 0:42                 │ ⬜ fg-400 quality-gate (queued)           │
│ PLANNING    ✓ 1:12                 │                                           │
│ VALIDATING  ✓ 0:23                 │ Elapsed: 5:47 • ETA: ~12 min             │
│ IMPLEMENTING ◐ 1:24 (running)      │ Tokens: 128K in, 14K out                 │
│ VERIFYING   · pending              │ Model: claude-sonnet-4-6                 │
│ ...                                │                                           │
├─ Event log (tail) ────────────────────────────────────────────────────────────┤
│ 10:23:15 [cost.inc]    fg-300  sonnet  12.4K+0.9K  $0.0508  run $0.3243     │
│ 10:23:18 [task.update] fg-300  impl task 1/3  → completed  PASS              │
│ 10:23:19 [dispatch]    parent=Stage 5  child=fg-300  task=2/3                │
│ 10:23:45 [cost.inc]    fg-300  sonnet  10.2K+1.1K  $0.0471  run $0.3714     │
│                                                                                │
├─ Keys: [q]uit [p]ause [r]esume [a]pply [P]review [R]eject [e]dit plan ───────┤
└────────────────────────────────────────────────────────────────────────────────┘
```

**Key bindings:**

| Key | Action |
|---|---|
| `q` | Quit TUI (pipeline continues) |
| `p` | Pause pipeline (sends SIGUSR1 to orchestrator; orchestrator pauses at next stage boundary) |
| `r` | Resume paused pipeline |
| `P` (shift-p) | Invoke `/forge-preview` in a sub-pane; show diff |
| `a` | Invoke `/forge-apply` (only enabled in APPLY_GATE_WAIT) |
| `R` (shift-r) | Invoke `/forge-reject` (only enabled in APPLY_GATE_WAIT) |
| `e` | Edit plan file (launches `$EDITOR` on `.forge/plans/current.md`; only enabled in PLAN_EDIT_WAIT) |
| `↑/↓` | Scroll event log |
| `tab` | Cycle pane focus |
| `?` | Show full key help overlay |

**Data source:**
- Primary: `.forge/events.jsonl` (tailed via `tail -f` equivalent — Python: read + seek + poll every 500ms)
- Fallback for sprint/bestof: `.forge/runs/<run_id>/events.jsonl`
- Supplementary: `.forge/state.json` (stage, cost, tokens, cap status) — re-read every 2s
- Secondary: `.forge/pending/` listing for APPLY_GATE rendering

**Render cadence:** 2Hz (every 500ms). Single-threaded event loop; curses `halfdelay(5)` for input polling.

**Exit behavior:** `q` exits cleanly; pipeline continues. SIGINT (Ctrl+C) also exits (trap to restore terminal).

**Graceful degradation:**
- If terminal <80×24: fall back to vertical single-pane layout with collapsible sections.
- If terminal doesn't support colors: use plain ASCII without ANSI sequences.
- If `.forge/events.jsonl` missing: render empty event pane with "waiting for events…" message.
- If `python3` not available: skill body prints clear error with install hint.

### 4.2 `skills/forge-watch/SKILL.md` (new)

Minimal dispatcher:

```markdown
---
name: forge-watch
description: "[read-only] Live curses TUI for watching a Forge pipeline run. Shows stage progress, agent queue, event log tail, cost, and offers key bindings for /forge-apply, /forge-reject, plan editing. Use during a long /forge-run to watch progress or at APPLY_GATE_WAIT to review staged changes visually. Trigger: /forge-watch, watch pipeline, live view, tui"
allowed-tools: ['Read', 'Bash']
---

# /forge-watch — Live pipeline TUI

Consumes `.forge/events.jsonl` + `.forge/state.json` with a 3-pane curses view.

## Flags

- **--help**: print usage and exit 0
- **--json**: emit one JSON status snapshot to stdout and exit (scripting)
- **--run <id>**: attach to a specific sprint/best-of run's events.jsonl
- **--bestof**: summary view of all best-of runs (stage + cost + score per run)

## Exit codes

See `shared/skill-contract.md`.

## Implementation

Dispatches `python3 shared/forge-watch.py [flags]`. Terminal restored on exit.

## Examples

```
/forge-watch                      # attach to default run
/forge-watch --run bestof-2-sonnet # attach to specific sprint/best-of run
/forge-watch --bestof             # summary of all best-of runs
/forge-watch --json               # one-shot JSON snapshot
```
```

### 4.3 Plan branches

#### 4.3.1 Directory layout

```
.forge/plans/
├─ current.md                       # canonical plan
├─ archive/                         # time snapshots
└─ branches/
    ├─ approach-A/
    │   ├─ current.md               # branch plan
    │   ├─ state.json               # branch-independent state
    │   ├─ pending/                 # branch-independent staging
    │   └─ events.jsonl             # branch-independent event log
    └─ approach-B/
        └─ ...
```

All gitignored (`.forge/` already excluded).

#### 4.3.2 `/forge-run --branch <name>` flow

- Orchestrator detects `--branch <name>` flag.
- Validates name: `[a-z][a-z0-9-]{0,31}` (no collisions with existing branch dirs unless `--force`).
- Creates `.forge/plans/branches/<name>/` directory.
- Copies current `.forge/state.json`, `.forge/plans/current.md` (if present) into the branch dir.
- Sets branch context: all subsequent state writes go into the branch dir instead of `.forge/`.
- Pipeline proceeds normally within the branch context.
- User compares branches via `/forge-watch --run branch-<name>` or filesystem diff.

#### 4.3.3 `shared/plan-branches.md` (contract doc)

Sections: (1) directory layout, (2) orchestrator branch-context switching, (3) `--branch` flag parsing + validation, (4) state key `state.branch` (string, optional), (5) how branches interact with sprint / best-of (orthogonal — branches can host best-of runs).

#### 4.3.4 `/forge-run --branch` restrictions

- Cannot be combined with `--best-of N > 1` in the same invocation (use-case: branching AND bake-off). Both produce multiple sub-runs; combining explodes the state tree. Explicit error with suggestion.
- Cannot branch from an in-flight run — only from a completed or ABORTED run's state.

### 4.4 Best-of-N model bake-off

#### 4.4.1 `/forge-run --best-of N [--profiles opus,sonnet,haiku] 'requirement'`

- N ∈ [2, 5] hard cap (N=1 errors with "use /forge-run without --best-of").
- `--profiles <csv>` optional:
  - N ≤ 3 and absent → first-N of `[opus, sonnet, haiku]`.
  - N > 3 → `--profiles` REQUIRED (no meaningful default).
  - At PREFLIGHT, orchestrator validates every profile resolves to a model in `model_routing`; unresolvable profile → exit 1 with "profile X not in model_routing".

- Orchestrator spawns N sub-pipelines under `.forge/runs/bestof-<i>-<profile>/`, each with:
  - Independent `state.json`, `events.jsonl`, `pending/`, `plans/current.md`
  - Independent worktree via existing Phase 1 worktree-manager (`.forge/worktrees/bestof-<i>/`)
  - Per-run `forge.local.md` override under `.forge/runs/bestof-<i>-<profile>/forge.local.md` with `model_routing.default: <profile>` (fg-100-orchestrator reads this file first, then falls back to project-level config). No env-var injection; pure filesystem override.

**New dedicated agent — `agents/fg-095-bestof-orchestrator.md` (v1 review I1):**

The sprint orchestrator's invariants don't cleanly invert ("N requirements × 1 model" ≠ "1 requirement × N models" — ANALYZE/GROUP/conflict-resolver are meaningless for best-of). Rather than contorting fg-090 with conditional skips, Phase 5 introduces a **new** dedicated orchestrator that reuses only the primitives (worktree-manager, per-run directories, cross-repo coordinator) but has its own phase flow:

| Phase (fg-095) | Purpose |
|---|---|
| INPUT | Parse `--best-of N`, `--profiles`, requirement; validate per §4.4.1 |
| PREFLIGHT | Validate profiles against `model_routing`; estimate aggregate cost |
| DISPATCH | Create N per-run directories + worktrees; write per-run `forge.local.md`; invoke fg-100 for each in parallel |
| MONITOR | Aggregate events across N runs; expose to TUI via `/forge-watch --bestof` |
| SELECT | After all N complete: render summary (score, cost, time, diff size); user picks (or `--auto-winner`) |
| PROMOTE | Winner's worktree → user's project worktree via Phase 1 worktree-manager merge; losers stashed to `.forge/bestof/<timestamp>/` |
| CLEANUP | Optional prune of loser worktrees after N days (config: `bestof.loser_retention_days`, default 7) |

Compare fg-090 (sprint): `ANALYZE`/`GROUP`/`APPROVE` phases present, `conflict-resolver` dispatched; these are skipped in fg-095 since parallelism is trivially independent.

Aggregate cost estimation (PREFLIGHT): orchestrator computes `sum(profile_cost_estimate)` from Phase 2's per-model pricing + historical run length. Compares against `bestof.aggregate_cap_usd` (see §4.4.4).

#### 4.4.2 Winner selection

- **Default (manual):** After all N complete, orchestrator prints a summary table (score, cost, time, pending-diff size per run) and waits via `AskUserQuestion` — user picks winner number. Winner's worktree is promoted to the user's project worktree.
- **`--auto-winner`:** highest quality-gate score wins; ties broken by cost (lower wins). Winner recorded in `state.bestof.winner`.
- Non-winners: stashed under `.forge/bestof/<timestamp>/` for review. User can promote later manually.

#### 4.4.4 Aggregate cost cap (`bestof.aggregate_cap_usd`)

Per-run `cost_cap.usd` (Phase 2) applies to each of the N runs independently. Best-of-N adds an **aggregate** cap that sums across all N runs — a single budget for the bake-off.

Config:

```yaml
bestof:
  aggregate_cap_usd: 20.00      # 0 disables; any positive sets aggregate cap
  action_on_aggregate_breach: ask   # ask | abort_remaining | warn_continue
```

Enforcement: fg-095 monitors `sum(cost.inc events)` across all N runs. On breach, action mirrors Phase 2's `cost_cap.action_on_breach` semantics but applied to the bake-off as a whole. `abort_remaining` cancels un-finished runs (ABORTED) while preserving completed-run state for winner selection.

At PREFLIGHT, fg-095 estimates aggregate cost; if estimate exceeds `aggregate_cap_usd`, emit E2 `AskUserQuestion` with options: increase cap / proceed anyway / abort bake-off.

#### 4.4.3 `shared/best-of-n.md` (contract doc)

Sections: (1) invocation + flag parsing, (2) sprint-orchestrator reuse, (3) model-profile list + defaults, (4) winner selection (manual vs auto), (5) non-winner archival, (6) state key `state.bestof` schema, (7) cost cap interaction (cap applies per-run, not aggregate).

### 4.5 Inline per-turn cost emission (non-TUI)

**Complements the TUI** for users who don't open it.

- Phase 2's `forge-token-tracker.sh` already writes `cost.inc` events.
- Phase 5 addition: orchestrator, on each `Agent` return that triggers a `cost.inc` event, ALSO emits a single-line stderr progress ticker:

```
[forge 5/10 IMPL] fg-300 +$0.051 (run $0.372) • 14.3K tokens
```

- Emission format in `shared/forge-watch-contract.md §5`:
  ```
  [forge <stage>/10 <stage-name-short>] <agent-id> +$<delta> (run $<total>) • <tokens-K>
  ```
- Suppressed when `caveman.output_mode: ultra` (per `shared/caveman.md` — independent from output_compression) OR `output_compression.default_level: minimal` (per `shared/output-compression.md`).
- Suppressed when TUI is active. Single source of truth: orchestrator reads `state.json.tui.active` (set by `/forge-watch` on attach, cleared on exit). No separate `state.tui.active` env var (v1 review I3: two-mechanism suppression guarantees drift).

### 4.6 `shared/forge-watch-contract.md` (new)

Authoritative contract for the TUI's data consumption:

- §1 Event-stream consumption (pending cursor, seek-on-restart, backpressure behavior)
- §2 State-file polling (2s cadence, graceful handling of mid-write via file lock from Phase 2)
- §3 Key binding reference (see §4.1 above)
- §4 Terminal size fallback rules
- §5 Inline per-turn cost stderr format (§4.5)
- §6 JSON snapshot schema for `--json` flag
- §7 `state.tui.active` env var semantics
- §8 Enforcement map (which bats file checks what)

### 4.7 State schema additions (`shared/state-schema.md` + `.json`)

Bump `1.8.0 → 1.9.0`.

New fields:

- `state.branch` (string, optional) — branch name if this state is under `.forge/plans/branches/<name>/`
- `state.bestof` (object, optional):
  ```json
  {
    "index": 1,
    "total": 3,
    "profile": "sonnet",
    "requirement": "Add MFA",
    "winner": null
  }
  ```
- `state.tui` (object, optional):
  ```json
  {
    "active": false,
    "pid": null,
    "attached_at": null
  }
  ```

Schema history row: `1.9.0 | 2026-04-17 | Phase 5 live observation | branch, bestof, tui fields`.

### 4.8 Configuration additions

`forge.local.md` / `forge-config.md`:

```yaml
observation:
  watch_refresh_ms: 500           # TUI redraw cadence
  watch_event_tail_lines: 20      # event log pane height
  watch_auto_launch: false        # auto-launch TUI on /forge-run (opt-in)

bestof:
  max_n: 5                              # hard cap on --best-of N
  default_profiles: [opus, sonnet, haiku]
  auto_winner: false                    # default: manual pick
  aggregate_cap_usd: 20.00              # total spend ceiling across all N runs
  action_on_aggregate_breach: ask       # ask | abort_remaining | warn_continue
  loser_retention_days: 7               # auto-prune loser worktrees after N days
```

### 4.9 Documentation updates

- `README.md` — new "Live observation" section + screenshots; version bump
- `CLAUDE.md` — add 3 Key Entry Points (`forge-watch-contract.md`, `plan-branches.md`, `best-of-n.md`); skill count `39 → 40`
- `CHANGELOG.md` — 4.1.0 entry
- `docs/control-safety.md` (Phase 4) — cross-reference `/forge-watch` for the APPLY_GATE_WAIT user flow
- `.claude-plugin/plugin.json`, `marketplace.json` — `4.0.0 → 4.1.0`

## 5. File manifest

### 5.1 Delete

None.

### 5.2 Create (9 files)

```
shared/forge-watch.py                          # ~400 LOC curses TUI
shared/forge-watch-contract.md                 # contract doc
shared/plan-branches.md                        # contract doc
shared/best-of-n.md                            # contract doc
skills/forge-watch/SKILL.md                    # dispatcher
agents/fg-095-bestof-orchestrator.md           # NEW agent — dedicated best-of dispatcher
tests/contract/live-observation.bats           # contract-level asserts
tests/unit/forge-watch-renderer.bats           # non-TUI render unit test
tests/fixtures/events/sample-run.jsonl         # renderer fixture
```

`tests/fixtures/events/` directory does not exist yet — plan must `mkdir -p`.

### 5.3 Update in place

**Agents (1, not 2 — fg-090 unchanged per v1 review I1):**
- `agents/fg-100-orchestrator.md` — add `## § Plan branch dispatch`, `## § Best-of-N dispatch routing` (dispatches to fg-095), `## § TUI detection` sections; stderr ticker emission on cost.inc
- ~~`agents/fg-090-sprint-orchestrator.md`~~ — **not modified**. Best-of has its own agent (fg-095) per v1 review I1.

**Shared docs (3):**
- `shared/state-schema.md` — bump 1.8.0 → 1.9.0; add `branch`, `bestof`, `tui` fields
- `shared/state-schema.json` — mirror the .md changes
- `shared/observability-contract.md` — add §11 TUI consumption contract cross-reference

**Skills (2):**
- `skills/forge-run/SKILL.md` — add `--branch <name>`, `--best-of N`, `--profiles <csv>`, `--auto-winner` flags
- `skills/forge-sprint/SKILL.md` — note best-of-N reuses this infrastructure

**Config (1):**
- `shared/config-schema.json` — `observation` + `bestof` fields

**Top-level (6):**
- `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/control-safety.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

### 5.4 File-count arithmetic

| Category | Count |
|---|---|
| Creations | 9 (+fg-095-bestof-orchestrator) |
| Agent updates | 1 (fg-100 only; fg-090 unchanged) |
| Shared doc updates | 3 |
| Skill updates | 2 |
| Config | 1 |
| Top-level | 6 |
| **Unique file operations** | **22** (9+1+3+2+1+6) |

## 6. Acceptance criteria

All verified by CI on push.

1. `shared/forge-watch.py` exists, valid Python (`python3 -m py_compile` passes), shebang `#!/usr/bin/env python3`.
2. `skills/forge-watch/SKILL.md` exists with Phase 1 skill-contract compliance (`[read-only]` badge, `## Flags`, `## Exit codes`).
3. `shared/forge-watch-contract.md` exists with 8 sections per §4.6.
4. `shared/plan-branches.md` exists with 5 sections per §4.3.3.
5. `shared/best-of-n.md` exists with 7 sections per §4.4.3.
6. `/forge-run` SKILL.md documents `--branch`, `--best-of`, `--profiles`, `--auto-winner` flags.
7. `agents/fg-100-orchestrator.md` contains 3 new sections: Plan branch dispatch, Best-of-N dispatch, TUI detection.
8. `agents/fg-090-sprint-orchestrator.md` has `best_of` mode section.
9. `shared/state-schema.md` version `1.9.0`; `branch`, `bestof`, `tui` fields documented.
10. `shared/state-schema.json` version `1.9.0`; new fields present; schema validates sample fixture.
11. `shared/config-schema.json` includes `observation.*` and `bestof.*` fields.
12. `tests/contract/live-observation.bats` passes: Python file compiles, TUI file has defined key bindings table matching spec §4.1, contract doc sections resolve.
13. `tests/unit/forge-watch-renderer.bats` passes: `forge-watch.py --json` against `tests/fixtures/events/sample-run.jsonl` emits expected JSON snapshot schema.
14. `skills/forge-watch` counts into total as skill #40 (Phase 4's 39 + 1); `CLAUDE.md` skill count line says `40`.
15. `README.md`, `CLAUDE.md`, `CHANGELOG.md` updated per §4.9.
16. `docs/control-safety.md` (existing from Phase 4) cross-references `/forge-watch`.
17. `.claude-plugin/plugin.json` + `marketplace.json` set to `4.1.0`.
18. CI green on push; no local test runs permitted.

## 7. Test strategy

**Static (bats + Python compile):**
- `live-observation.bats` Group A: file existence, contract doc section counts, Python compile, SKILL.md contract compliance.
- `live-observation.bats` Group B (gated on `FORGE_PHASE5_ACTIVE=1` sentinel):
  - Cross-file: `shared/forge-watch.py` writes `state.tui.active = true` on startup + clears on exit; orchestrator's `## § TUI detection` reads `state.tui.active`. Grep both files for symmetrical pattern.
  - `skill-count = 40` check.
  - **Stderr ticker (C4 fix):** grep `agents/fg-100-orchestrator.md` for the exact ticker format string from `shared/forge-watch-contract.md §5` (`[forge <stage>/10 <stage-name-short>] <agent-id> +$<delta> (run $<total>) • <tokens-K>`).
  - Grep orchestrator for suppression logic: must reference `state.tui.active` AND one of `caveman.output_mode` / `output_compression.default_level`.
  - `/forge-watch` key-binding table (§4.1) → assert all 9 keys documented in `shared/forge-watch-contract.md §3`.
  - `/forge-run --best-of N` dispatches `fg-095-bestof-orchestrator` (grep fg-100-orchestrator routing).

**Runtime (bats — non-interactive):**
- `tests/unit/forge-watch-renderer.bats`: invoke `forge-watch.py --json --fixture tests/fixtures/events/sample-run.jsonl` and assert JSON snapshot schema (stage, cost_usd, agents[], events_tail[]).
- No interactive curses testing in CI — curses needs a real tty. `--json` mode is the CI surrogate.

**Manual sanity (documented, not CI):**
- `docs/control-safety.md` gains a "Phase 5 TUI quick test" section with commands to verify pane layout locally.

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Python curses behaves differently on macOS (ncurses 5.x) vs Linux (6.x) | Medium | Medium | Targeted smoke: test fixture CI step on both OSes via `python3 -c "import curses"` + dry-run render |
| TUI redraw racing with orchestrator writes to events.jsonl | Low | Low | Phase 2 mkdir-lock already serializes writes; reader is non-locking (tail -f pattern with seek) — eventual consistency is fine |
| Best-of-N cost cap confusion (per-run vs aggregate) | Medium | Medium | `shared/best-of-n.md §7` documents that `cost_cap` applies per-run; aggregate-cap is a future opt-in. User can set `bestof.aggregate_cap_usd` (new, optional) |
| Plan branches + best-of-N combination explodes state tree | Low | High | Orchestrator rejects `--branch` + `--best-of N>1` with explicit error (spec §4.3.4) |
| TUI key `a` during active APPLY_GATE races the orchestrator's AskUserQuestion | Low | Low | Key `a` is enabled **only in APPLY_GATE_WAIT** (not APPLY_GATE) per §4.1 key-binding table. In APPLY_GATE the orchestrator's AskUserQuestion is modal — TUI doesn't offer `a`. No bypass token needed. |
| Terminal resize mid-run corrupts pane layout | Medium | Low | `curses.KEY_RESIZE` handler recomputes layout; fallback to single-column on <80 cols |
| `$EDITOR` launch from `e` key doesn't restore curses state cleanly | Medium | Medium | Wrap in `curses.endwin()` / restore pattern; test on vim, nano, VS Code `code --wait` |
| Python 3 unavailable at runtime | Low | Medium | Phase 3 prereq check covers bash+python3 as required deps; failure at `/forge-init` catches it |
| `.forge/events.jsonl` grows unbounded for long runs; TUI slow to scroll | Low | Low | TUI caps event tail buffer at `observation.watch_event_tail_lines` (default 20 visible, 500 buffered); older events paged via `↑` |
| Sprint/best-of events.jsonl path detection ambiguity | Low | Low | TUI's `--run <id>` flag explicit; `auto-detect` by reading `state.run_id` |
| `auto-winner` selection penalizes models that take longer | Medium | Low | Default ranks by quality-gate score; cost is tiebreaker, not primary. Documented in best-of-n.md |
| Non-TUI stderr cost ticker spams users | Medium | Low | Suppressed under ultra-caveman; also suppressed if `observation.inline_cost_ticker: false` (default true) |

## 9. Rollout (one PR, multi-commit; CI gates on HEAD)

1. **Commit 1 — Specs land.** This spec + plan.
2. **Commit 2 — Foundations.** 3 contract docs + `shared/forge-watch.py` skeleton (just --help + --json stub) + sample events fixture. CI green.
3. **Commit 3 — TUI + skill.** Full curses TUI in `forge-watch.py`; `skills/forge-watch/SKILL.md` dispatcher; `tests/contract/live-observation.bats` + `tests/unit/forge-watch-renderer.bats`. Group A active; Group B gated. CI green.
4. **Commit 4 — Orchestrator branch-dispatch + flag parsing.** `fg-100-orchestrator` gets `--branch` handling; `/forge-run` SKILL.md gains flags. CI green.
5. **Commit 5 — Orchestrator best-of + sprint reuse.** `fg-100-orchestrator` + `fg-090-sprint-orchestrator` get `best_of` mode + winner selection. CI green.
6. **Commit 6 — Inline cost ticker.** Orchestrator stderr emission on `cost.inc`; respects `state.tui.active` env. CI green.
7. **Commit 7 — Schema bump + config + observability-contract cross-ref.** `state-schema.md/json` → 1.9.0; `config-schema.json` new fields; `observability-contract.md §11`. CI green.
8. **Commit 8 — Top-level docs + version bump + sentinel.** README, CLAUDE, CHANGELOG, docs/control-safety.md, plugin.json, marketplace.json → 4.1.0. `FORGE_PHASE5_ACTIVE=1` sentinel activates Group B. CI green.
9. **Push → CI → tag `v4.1.0` → release.**

## 10. Versioning rationale

Purely additive: new skill, new flags, new state fields, new docs. No behavior change to existing pipelines. `4.0.0 → 4.1.0`.

## 11. Open questions

None. Brainstorming locked all 4 features in scope.

## 12. References

- Phase 2 spec (events.jsonl, sprint-mode paths, cost streaming)
- Phase 4 spec (APPLY_GATE, editable plan, scopes)
- `shared/forge-token-tracker.sh` (Phase 2) — stderr ticker piggybacks
- `shared/observability-contract.md` (Phase 2+4) — extended with §11
- `agents/fg-090-sprint-orchestrator.md` — sprint parallelization reused
- April 2026 UX audit — §3 "Live observation gap"
- User instruction: "I want it all except the backwards compatibility"
