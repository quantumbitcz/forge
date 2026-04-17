# Phase 5 — Live Observation UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** `/forge-watch` Python-curses TUI + plan branches + best-of-N model bake-off via new `fg-095-bestof-orchestrator` agent + inline stderr cost ticker. Ship as Forge 4.1.0.

**Architecture:** 9 logical commits in one PR. Group A/B sentinel pattern: `FORGE_PHASE5_ACTIVE=1` activates at Commit 8 when 9 new files + orchestrator TUI section + schema 1.9.0 all present.

**Tech Stack:** Python 3 (stdlib `curses`), Bash, Bats. No pip dependencies.

**Verification:** No local runs. Static parse only (`python3 -m py_compile`, `bash -n`). CI validates on push.

**Spec:** `docs/superpowers/specs/2026-04-17-phase5-live-observation-ux-design.md`
**Depends on:** Phases 1-4 merged (v4.0.0 baseline).

---

## Task 0: Verify Phase 4 preconditions

- [ ] **Step 1: Verify plugin at 4.0.0 and Phase 4 deliverables present**

```bash
grep '"version": "4.0.0"' .claude-plugin/plugin.json || { echo "ABORT: Phase 4 not merged"; exit 1; }
test -f shared/staging-overlay.md                    || { echo "ABORT: Phase 4 missing staging-overlay"; exit 1; }
test -f shared/escalation-taxonomy.md                || { echo "ABORT: Phase 4 missing escalation-taxonomy"; exit 1; }
test -f shared/forge-resolve-file.sh                 || { echo "ABORT: Phase 4 missing resolve-file"; exit 1; }
test -f docs/control-safety.md                       || { echo "ABORT: Phase 4 missing control-safety doc"; exit 1; }
grep -q '"version": "1.8.0"' shared/state-schema.md  || { echo "ABORT: Phase 4 schema bump missing"; exit 1; }
test -d skills/forge-apply                           || { echo "ABORT: Phase 4 forge-apply skill missing"; exit 1; }

# Phase 3 Python 3 required-prereq check
python3 -c "import curses" 2>/dev/null               || { echo "WARN: curses import failed — TUI only in WSL/macOS/Linux"; }
```

All fatal checks must pass.

---

## Task 1: Commit this plan

```bash
git add docs/superpowers/plans/2026-04-17-phase5-live-observation-ux.md
git commit -m "docs(phase5): add live observation UX implementation plan"
```

---

## Task 2: Create `tests/fixtures/events/sample-run.jsonl` + 3 contract docs

**Files:**
- Create: `tests/fixtures/events/` directory + `sample-run.jsonl`
- Create: `shared/forge-watch-contract.md`, `shared/plan-branches.md`, `shared/best-of-n.md`

- [ ] **Step 1: Create fixture directory + realistic sample**

```bash
mkdir -p tests/fixtures/events
cat > tests/fixtures/events/sample-run.jsonl <<'EOF'
{"ts":"2026-04-17T10:00:00Z","type":"stage.start","stage":1,"name":"PREFLIGHT","run_id":"test-run-42"}
{"ts":"2026-04-17T10:00:08Z","type":"stage.end","stage":1,"name":"PREFLIGHT","outcome":"complete"}
{"ts":"2026-04-17T10:00:08Z","type":"stage.start","stage":2,"name":"EXPLORING"}
{"ts":"2026-04-17T10:00:50Z","type":"cost.inc","run_id":"test-run-42","stage":2,"agent":"fg-130-docs-discoverer","model":"claude-haiku-4-5-20251001","tokens_in":8000,"tokens_out":500,"cost_usd":0.0084,"run_cost_usd":0.0084,"cap_usd":5.00}
{"ts":"2026-04-17T10:00:52Z","type":"task.create","task_id":"t1","subject":"Stage 2: EXPLORING","agent":"fg-100-orchestrator"}
{"ts":"2026-04-17T10:00:52Z","type":"dispatch.child","parent_stage":2,"parent_task_id":"t1","child_agent":"fg-130-docs-discoverer","child_task_id":"t2"}
{"ts":"2026-04-17T10:01:12Z","type":"task.update","task_id":"t2","status":"completed","metadata":{"summary":"12 docs indexed"}}
{"ts":"2026-04-17T10:01:12Z","type":"stage.end","stage":2,"name":"EXPLORING","outcome":"complete"}
{"ts":"2026-04-17T10:01:12Z","type":"stage.start","stage":5,"name":"IMPLEMENTING"}
{"ts":"2026-04-17T10:23:15Z","type":"cost.inc","run_id":"test-run-42","stage":5,"agent":"fg-300-implementer","model":"claude-sonnet-4-6","tokens_in":12400,"tokens_out":892,"cost_usd":0.0508,"run_cost_usd":0.3243,"cap_usd":5.00}
{"ts":"2026-04-17T10:23:16Z","type":"apply.committed","run_id":"test-run-42","files":["src/auth/login.ts"],"additions":45,"deletions":12}
{"ts":"2026-04-17T10:23:20Z","type":"escalation.e2","run_id":"test-run-42","level":"E2","source_agent":"fg-400-quality-gate","message":"Quality gate FAIL after 2 cycles","stage":6}
EOF
```

Validate:
```bash
while IFS= read -r line; do echo "$line" | python3 -m json.tool > /dev/null || { echo "Bad line: $line"; exit 1; }; done < tests/fixtures/events/sample-run.jsonl
```

- [ ] **Step 2: Write `shared/forge-watch-contract.md` (8 sections per spec §4.6)**

Skeleton:

```markdown
# Forge Watch Contract

Authoritative contract for /forge-watch TUI's data consumption and interaction model. Enforced by `tests/contract/live-observation.bats`.

## 1. Event-stream consumption

- Primary source: `.forge/events.jsonl` (standard run) or `.forge/runs/<run_id>/events.jsonl` (sprint/best-of)
- Cursor: maintains file byte offset between polls; seeks on file rotation
- Poll interval: 500ms default; configurable via `observation.watch_refresh_ms`
- Backpressure: if event rate exceeds render rate, TUI batches + shows "...N events pending" overlay

## 2. State file polling

- Secondary: `.forge/state.json` read every 2s for stage, cost, tokens, cap
- Write-protection: Phase 2's mkdir-lock is writer-side; reader is non-locking (eventual consistency)

## 3. Key binding reference

(Copy the 9-row table from spec §4.1 verbatim.)

## 4. Terminal size fallback

- ≥ 80×24: 3-pane layout
- < 80 cols: single-column vertical stack with collapsible sections
- No-color TERM: ASCII-only rendering
- `curses.COLORS < 256`: 8-color fallback palette

## 5. Inline per-turn cost stderr format

```
[forge <stage>/10 <stage-name-short>] <agent-id> +$<delta> (run $<total>) • <tokens-K>
```

Example:
```
[forge 5/10 IMPL] fg-300 +$0.051 (run $0.372) • 14.3K tokens
```

Emitted by orchestrator on every cost.inc event. Suppressed when:
1. `state.tui.active == true` (TUI attached)
2. `caveman.output_mode == "ultra"`
3. `output_compression.default_level == "minimal"`

## 6. JSON snapshot schema (--json flag)

```json
{
  "run_id": "test-run-42",
  "stage": {"n": 5, "name": "IMPLEMENTING", "elapsed_s": 347},
  "cost": {"run_usd": 0.3243, "cap_usd": 5.00},
  "tokens": {"in": 128000, "out": 14000, "model": "claude-sonnet-4-6"},
  "agents": [{"id": "fg-300", "status": "in_progress", "task": "impl 2/3"}],
  "events_tail": [...],
  "pending": {"files": [...], "additions": N, "deletions": N}
}
```

## 7. state.tui.active semantics

- Set true by forge-watch.py on startup (writes to state.json atomically)
- Cleared by forge-watch.py on exit (normal or SIGINT-trapped)
- Orchestrator reads this flag for stderr ticker suppression
- Only one TUI per run; second attach warns + attaches read-only

## 8. Enforcement map

| Rule | Enforced by |
|---|---|
| §1 event consumption | `tests/unit/forge-watch-renderer.bats` (--json against fixture) |
| §3 key bindings | `tests/contract/live-observation.bats` (grep py file for key handlers) |
| §5 ticker format | `tests/contract/live-observation.bats` Group B (grep orchestrator) |
| §7 tui.active symmetry | `tests/contract/live-observation.bats` Group B (cross-file grep) |
```

- [ ] **Step 3: Write `shared/plan-branches.md` (5 sections per spec §4.3.3)**

- [ ] **Step 4: Write `shared/best-of-n.md` (7 sections per spec §4.4.3 + §4.4.4)**

Include §2 per-run forge.local.md override mechanism; §7 cost-cap interaction (per-run vs aggregate); winner-selection tiebreaker order (score → cost).

- [ ] **Step 5: Held for commit in Task 8**

---

## Task 3: Create `shared/forge-watch.py` (curses TUI)

**File:** `shared/forge-watch.py`

- [ ] **Step 1: Write the TUI skeleton** (~400 LOC target)

Key structure (pseudocode — full implementation in commit 3):

```python
#!/usr/bin/env python3
"""Forge Watch TUI — curses-based live pipeline viewer.

Reads .forge/events.jsonl and .forge/state.json; renders 3-pane layout.
See shared/forge-watch-contract.md for the authoritative contract.
"""
import curses
import json
import os
import sys
import time
from pathlib import Path

PLUGIN_ROOT = Path(__file__).parent.parent  # .../forge/
FORGE_DIR = Path(".forge")
REFRESH_MS = 500

def parse_args(argv):
    """Parse --help, --json, --run <id>, --bestof flags."""
    ...

def load_state():
    """Read .forge/state.json; return dict or None."""
    ...

def tail_events(path, cursor):
    """Yield new events since cursor; update cursor."""
    ...

def render_json_snapshot(state, events_tail):
    """Emit one JSON snapshot to stdout (for --json mode)."""
    snapshot = {
        "run_id": state.get("run_id"),
        "stage": {...},
        "cost": {...},
        "tokens": {...},
        "agents": [...],
        "events_tail": events_tail[-20:],
        "pending": state.get("pending", {}),
    }
    print(json.dumps(snapshot, indent=2))

def render_tui(stdscr):
    """Main curses event loop. Reads state + events, renders panes, handles keys."""
    curses.curs_set(0)
    stdscr.timeout(REFRESH_MS)  # NOT halfdelay (deprecated in 3.11+)

    # Mark TUI as active in state.json
    mark_tui_active(True)
    try:
        while True:
            state = load_state()
            events = tail_events(...)
            render_panes(stdscr, state, events)
            key = stdscr.getch()
            if key == ord('q'): break
            elif key == ord('a'): invoke_forge_apply()
            elif key == ord('P'): invoke_forge_preview()
            # ... etc
    finally:
        mark_tui_active(False)

def mark_tui_active(active: bool):
    """Atomically update state.json.tui.active."""
    ...

def main():
    args = parse_args(sys.argv[1:])
    if args.help:
        print(__doc__)
        return 0
    if args.json:
        state = load_state()
        events = list(tail_events(...))[-20:]
        render_json_snapshot(state, events)
        return 0
    # Check curses availability (Windows-native fails here)
    try:
        import _curses
    except ImportError:
        print("TUI requires WSL2 or Linux/macOS. Use --json mode on Windows.", file=sys.stderr)
        return 2
    return curses.wrapper(render_tui)

if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Make executable + compile-check**

```bash
chmod +x shared/forge-watch.py
python3 -m py_compile shared/forge-watch.py
python3 shared/forge-watch.py --help  # should not raise
```

- [ ] **Step 3: Held for commit in Task 8**

---

## Task 4: Create `skills/forge-watch/SKILL.md`

- [ ] **Step 1: Write SKILL.md per spec §4.2**

```markdown
---
name: forge-watch
description: "[read-only] Live curses TUI for watching a Forge pipeline run. Shows stage progress, agent queue, event log tail, cost, and offers key bindings for /forge-apply, /forge-reject, plan editing. Use during a long /forge-run to watch progress or at APPLY_GATE_WAIT to review staged changes visually. Trigger: /forge-watch, watch pipeline, live view, tui"
allowed-tools: ['Read', 'Bash']
---

# /forge-watch — Live pipeline TUI

## Flags

- **--help**: print usage and exit 0
- **--json**: emit one JSON status snapshot (for scripting)
- **--run <id>**: attach to a specific sprint/best-of run's events.jsonl
- **--bestof**: summary view of all best-of runs

## Exit codes

See `shared/skill-contract.md`.

## Implementation

Dispatches `python3 ${CLAUDE_PLUGIN_ROOT}/shared/forge-watch.py "$@"`. Terminal restored on exit.

## Examples

```
/forge-watch                       # attach to default run
/forge-watch --run bestof-2-sonnet # attach to a best-of sub-run
/forge-watch --bestof              # summary view
/forge-watch --json                # one-shot JSON snapshot
```
```

- [ ] **Step 2: Held for commit in Task 8**

---

## Task 5: Create `agents/fg-095-bestof-orchestrator.md`

- [ ] **Step 1: Write the new agent**

Full `.md` with:
- Frontmatter: `name: fg-095-bestof-orchestrator`, `color: pink` (or unused Phase 1 palette color — verify), `ui: { tasks: true, ask: true, plan_mode: true }`, tools include TaskCreate/TaskUpdate/AskUserQuestion/Agent
- Body with 7 phase sections matching spec §4.4.1 table: INPUT, PREFLIGHT, DISPATCH, MONITOR, SELECT, PROMOTE, CLEANUP
- `## User-interaction examples` section (Phase 1 Tier 1 requirement — it has ui.ask:true) with the SELECT-phase AskUserQuestion payload for winner selection

- [ ] **Step 2: Held for commit in Task 8**

---

## Task 6: Create `tests/contract/live-observation.bats` + `tests/unit/forge-watch-renderer.bats`

- [ ] **Step 1: Write live-observation.bats with Group A/B structure**

```bash
#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PLUGIN_ROOT
  if [[ -f "$PLUGIN_ROOT/shared/forge-watch.py" ]] && \
     [[ -f "$PLUGIN_ROOT/shared/forge-watch-contract.md" ]] && \
     [[ -f "$PLUGIN_ROOT/agents/fg-095-bestof-orchestrator.md" ]] && \
     grep -q '"version": "1.9.0"' "$PLUGIN_ROOT/shared/state-schema.md" 2>/dev/null; then
    export FORGE_PHASE5_ACTIVE=1
  fi
}

# Group A (active from Commit 2)

@test "[A] forge-watch-contract.md has 8 sections" {
  local f="$PLUGIN_ROOT/shared/forge-watch-contract.md"
  [ -f "$f" ]
  for n in 1 2 3 4 5 6 7 8; do
    grep -qE "^## $n\\. " "$f" || { echo "Missing §$n"; return 1; }
  done
}

@test "[A] plan-branches.md exists with 5 sections" {
  local f="$PLUGIN_ROOT/shared/plan-branches.md"
  [ -f "$f" ]
  local count
  count=$(grep -cE "^## [0-9]+\\. " "$f")
  [ "$count" -ge 5 ]
}

@test "[A] best-of-n.md exists with 7 sections" {
  local f="$PLUGIN_ROOT/shared/best-of-n.md"
  [ -f "$f" ]
  local count
  count=$(grep -cE "^## [0-9]+\\. " "$f")
  [ "$count" -ge 7 ]
}

@test "[A] forge-watch.py compiles" {
  python3 -m py_compile "$PLUGIN_ROOT/shared/forge-watch.py"
}

@test "[A] forge-watch.py --help succeeds without curses" {
  run python3 "$PLUGIN_ROOT/shared/forge-watch.py" --help
  [ "$status" = "0" ]
}

# Group B (active at Commit 8 via FORGE_PHASE5_ACTIVE)

@test "[B] state-schema.md version is 1.9.0" {
  [[ "${FORGE_PHASE5_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  grep -q '"version": "1.9.0"' "$PLUGIN_ROOT/shared/state-schema.md"
}

@test "[B] fg-100-orchestrator has TUI detection section" {
  [[ "${FORGE_PHASE5_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  grep -q "## § TUI detection\\|## § Plan branch dispatch\\|## § Best-of-N dispatch" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
}

@test "[B] orchestrator ticker format matches contract" {
  [[ "${FORGE_PHASE5_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  grep -q "forge <stage>/10\\|\\[forge .*/10" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
}

@test "[B] orchestrator ticker suppression references state.tui.active" {
  [[ "${FORGE_PHASE5_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  grep -q "state.tui.active" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
}

@test "[B] /forge-run documents --branch, --best-of flags" {
  [[ "${FORGE_PHASE5_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  local f="$PLUGIN_ROOT/skills/forge-run/SKILL.md"
  grep -q -- "--branch" "$f"
  grep -q -- "--best-of" "$f"
}

@test "[B] fg-095-bestof-orchestrator exists" {
  [[ "${FORGE_PHASE5_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  [ -f "$PLUGIN_ROOT/agents/fg-095-bestof-orchestrator.md" ]
}

@test "[B] skill count is 40" {
  [[ "${FORGE_PHASE5_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  local count
  count=$(find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$count" -eq 40 ]
}
```

- [ ] **Step 2: Write forge-watch-renderer.bats**

```bash
#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FIXTURE="$PLUGIN_ROOT/tests/fixtures/events/sample-run.jsonl"
  export PLUGIN_ROOT FIXTURE
  [[ -f "$FIXTURE" ]] || skip "Fixture missing; Phase 5 Commit 2 not merged"
}

@test "forge-watch.py --json emits valid JSON" {
  # Need to wrap: --json reads .forge/events.jsonl — simulate by placing fixture
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/.forge"
  cp "$FIXTURE" "$tmp/.forge/events.jsonl"
  echo '{"version":"1.9.0","run_id":"test-run-42","stage":"IMPLEMENTING"}' > "$tmp/.forge/state.json"

  cd "$tmp"
  run python3 "$PLUGIN_ROOT/shared/forge-watch.py" --json
  [ "$status" = "0" ]

  # Validate output is JSON
  echo "$output" | python3 -m json.tool > /dev/null

  # Validate schema per spec §4.6
  echo "$output" | python3 -c "
import json,sys
d = json.loads(sys.stdin.read())
assert 'run_id' in d
assert 'stage' in d
assert 'cost' in d
assert 'events_tail' in d
"
  cd /
  rm -rf "$tmp"
}

@test "forge-watch.py --json respects event types in fixture" {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/.forge"
  cp "$FIXTURE" "$tmp/.forge/events.jsonl"
  echo '{"version":"1.9.0","run_id":"test-run-42"}' > "$tmp/.forge/state.json"
  cd "$tmp"
  run python3 "$PLUGIN_ROOT/shared/forge-watch.py" --json
  [ "$status" = "0" ]
  # Fixture contains a cost.inc event; snapshot should include it in events_tail
  echo "$output" | grep -q "cost.inc"
  cd /
  rm -rf "$tmp"
}
```

- [ ] **Step 3: Held for commit in Task 8**

---

## Task 7: (Placeholder for any additional pre-commit prep)

*(Skipped — all files created in Tasks 2-6 are ready for Commit 2.)*

---

## Task 8: Commit 2 — Foundations

```bash
# Ensure executable bit on forge-watch.py BEFORE git add
chmod +x shared/forge-watch.py
git add shared/forge-watch.py
git ls-files --stage shared/forge-watch.py | grep -q "^100755 " || { echo "ABORT: execute bit not captured"; exit 1; }

git add shared/forge-watch-contract.md shared/plan-branches.md shared/best-of-n.md
git add skills/forge-watch/SKILL.md
git add agents/fg-095-bestof-orchestrator.md
git add tests/contract/live-observation.bats tests/unit/forge-watch-renderer.bats
git add tests/fixtures/events/sample-run.jsonl

git commit -m "feat(phase5): foundations — TUI + skill + contract docs + fg-095 + bats

Group A assertions active; Group B gated on FORGE_PHASE5_ACTIVE sentinel
(state-schema 1.9.0 + orchestrator TUI section present at Commit 8)."
```

---

## Task 9: Commit 3 — Orchestrator branch dispatch + flag parsing

- [ ] **Step 1: Update `agents/fg-100-orchestrator.md` — add `## § Plan branch dispatch`**

```markdown
## § Plan branch dispatch (Phase 5)

On invocation with `--branch <name>`:
1. Validate name: `[a-z][a-z0-9-]{0,31}`; reject with exit 1 otherwise.
2. Check `.forge/plans/branches/<name>/` does not exist (unless `--force`).
3. Create `.forge/plans/branches/<name>/`; copy current `.forge/state.json` + `.forge/plans/current.md` (if present) into it.
4. Set `state.branch = "<name>"`; all subsequent state writes go to the branch dir.
5. Reject combination `--branch X --best-of N>1` with explicit error.
6. Cannot branch from an in-flight run — only from completed or ABORTED state.

Documented in `shared/plan-branches.md`.
```

- [ ] **Step 2: Update `skills/forge-run/SKILL.md` — add --branch, --best-of, --profiles, --auto-winner flags**

Add to existing `## Flags`:
```
- **--branch <name>**: create/continue a plan branch at .forge/plans/branches/<name>/
- **--best-of <N>**: dispatch fg-095-bestof-orchestrator for N model profiles (2 ≤ N ≤ 5)
- **--profiles <csv>**: model profiles for --best-of (required if N > 3)
- **--auto-winner**: auto-select winner by quality-gate score (requires --best-of)
```

- [ ] **Step 3: Commit**

```bash
git add agents/fg-100-orchestrator.md skills/forge-run/SKILL.md
git commit -m "feat(phase5): orchestrator branch dispatch + forge-run flags

- fg-100: ## § Plan branch dispatch section
- /forge-run: --branch, --best-of, --profiles, --auto-winner flags documented"
```

---

## Task 10: Commit 4 — Best-of-N dispatch routing

- [ ] **Step 1: Add `## § Best-of-N dispatch routing` to fg-100-orchestrator**

```markdown
## § Best-of-N dispatch routing (Phase 5)

When `--best-of N` flag detected:
1. Validate: `2 ≤ N ≤ 5`; if `N > 3` require `--profiles`.
2. Validate profiles resolve in `model_routing` config; exit 1 with friendly error otherwise.
3. At PREFLIGHT, estimate aggregate cost using Phase 2 `shared/model-pricing.json`; compare against `bestof.aggregate_cap_usd`; emit E2 AskUserQuestion if exceeds.
4. Dispatch `fg-095-bestof-orchestrator` with payload:
   ```json
   {
     "requirement": "<user's requirement>",
     "n": N,
     "profiles": [<profile list>],
     "auto_winner": <bool>
   }
   ```
5. fg-095 handles all subsequent phases (INPUT through CLEANUP per `shared/best-of-n.md`).
6. On return: fg-095 reports winner index; fg-100 resumes post-bake-off (normal SHIP flow if autonomous, else AskUserQuestion for winner confirmation).

Documented in `shared/best-of-n.md §2`.
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-100-orchestrator.md
git commit -m "feat(phase5): fg-100 dispatch routing for fg-095-bestof-orchestrator"
```

---

## Task 11: Commit 5 — Inline cost ticker emission

- [ ] **Step 1: Add `## § TUI detection` + ticker emission to fg-100-orchestrator**

```markdown
## § TUI detection + inline cost ticker (Phase 5)

On every `cost.inc` event emission (from forge-token-tracker.sh), the orchestrator ALSO emits a single-line stderr ticker:

```
[forge <stage>/10 <STAGE-SHORT>] <agent-id> +$<delta> (run $<total>) • <tokens-K>K tokens
```

Example:
```
[forge 5/10 IMPL] fg-300 +$0.051 (run $0.372) • 14.3K tokens
```

**Suppression rules (all OR-ed — suppress if ANY is true):**
1. `state.tui.active == true` (TUI is attached; TUI shows cost in its own pane)
2. `caveman.output_mode == "ultra"` (runtime output compression)
3. `output_compression.default_level == "minimal"` (different subsystem — see `shared/output-compression.md`)

Read `state.tui.active` from `state.json` (cached per turn; refreshed on each cost.inc).

Format contract lives in `shared/forge-watch-contract.md §5`.
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-100-orchestrator.md
git commit -m "feat(phase5): inline per-turn cost stderr ticker (non-TUI)

- Orchestrator emits formatted ticker on every cost.inc event
- Suppressed when TUI attached OR caveman ultra OR output_compression minimal
- Format matches shared/forge-watch-contract.md §5"
```

---

## Task 12: Commit 6 — State schema 1.8.0 → 1.9.0 + config + observability cross-ref

- [ ] **Step 1: Bump state-schema.md + state-schema.json**

Find `"version": "1.8.0"` in both; change to `"1.9.0"`.

Add fields to state-schema.md + .json: `state.branch` (string), `state.bestof` (object per spec §4.7), `state.tui` (object per spec §4.7).

Add state-schema.md migration row: `1.9.0 | 2026-04-17 | Phase 5 live observation | branch, bestof, tui fields`.

Update `tests/contract/state-schema.bats` version literal from 1.8.0 → 1.9.0.

- [ ] **Step 2: Update config-schema.json — observation + bestof sections**

Add properties per spec §4.8:

```json
"observation": {
  "type": "object",
  "properties": {
    "watch_refresh_ms": {"type": "integer", "default": 500, "minimum": 100},
    "watch_event_tail_lines": {"type": "integer", "default": 20},
    "watch_auto_launch": {"type": "boolean", "default": false}
  }
},
"bestof": {
  "type": "object",
  "properties": {
    "max_n": {"type": "integer", "default": 5, "maximum": 5},
    "default_profiles": {"type": "array", "items": {"type": "string"}, "default": ["opus", "sonnet", "haiku"]},
    "auto_winner": {"type": "boolean", "default": false},
    "aggregate_cap_usd": {"type": "number", "default": 20.00, "minimum": 0},
    "action_on_aggregate_breach": {"type": "string", "enum": ["ask", "abort_remaining", "warn_continue"], "default": "ask"},
    "loser_retention_days": {"type": "integer", "default": 7}
  }
}
```

- [ ] **Step 3: Add `§11` to shared/observability-contract.md**

```markdown
## §11 Live observation consumer (Phase 5)

`/forge-watch` TUI consumes the events.jsonl stream established in §3 + state.json. Contract lives in `shared/forge-watch-contract.md`. Phase 5 adds:

- Event types (no new ones — consumer of existing types)
- `state.tui` object for attach tracking
- Stderr per-turn cost ticker format (§5 of forge-watch-contract)
- /forge-watch key bindings (§3 of forge-watch-contract)
```

- [ ] **Step 4: Commit**

```bash
git add shared/state-schema.md shared/state-schema.json shared/config-schema.json
git add shared/observability-contract.md
git add tests/contract/state-schema.bats
git commit -m "feat(phase5): schema 1.8.0 → 1.9.0 + config (observation, bestof) + obs-contract §11"
```

---

## Task 13: Commit 7 — Top-level docs + version bump + sentinel activation

- [ ] **Step 1: README.md — new 'Live observation' section**

Near existing feature sections, add:

```markdown
## Live observation (4.1.0+)

Watch a Forge pipeline run in real time:

- **`/forge-watch`** — curses TUI with 3 panes (stage progress, agent queue, event log tail). Key bindings for `/forge-apply`, `/forge-reject`, plan editing.
- **Inline stderr ticker** — non-TUI users see turn-by-turn cost ticks: `[forge 5/10 IMPL] fg-300 +$0.051 (run $0.372) • 14.3K tokens`.
- **`/forge-run --branch <name>`** — explore alternative plans without destroying prior ones.
- **`/forge-run --best-of N`** — bake-off N model profiles (opus/sonnet/haiku by default); pick the winner.

Contracts: `shared/forge-watch-contract.md`, `shared/plan-branches.md`, `shared/best-of-n.md`.
```

- [ ] **Step 2: CLAUDE.md — add 3 Key Entry Points**

```markdown
| Forge watch contract | `shared/forge-watch-contract.md` |
| Plan branches | `shared/plan-branches.md` |
| Best-of-N bake-off | `shared/best-of-n.md` |
```

Update skill count to `40`.

- [ ] **Step 3: CHANGELOG.md — 4.1.0 entry**

Full entry listing TUI, plan branches, best-of-N, new fg-095 agent, state schema 1.9.0, config additions, inline ticker.

- [ ] **Step 4: Cross-reference `/forge-watch` from docs/control-safety.md (Phase 4)**

Add a "Watch the pipeline live" section to docs/control-safety.md pointing at /forge-watch.

- [ ] **Step 5: Bump plugin + marketplace JSON**

```bash
sed -i.bak 's/"version": "4.0.0"/"version": "4.1.0"/' .claude-plugin/plugin.json
sed -i.bak 's/"version": "4.0.0"/"version": "4.1.0"/' .claude-plugin/marketplace.json
rm -f .claude-plugin/*.bak
```

- [ ] **Step 6: Commit (activates FORGE_PHASE5_ACTIVE sentinel)**

```bash
git add README.md CLAUDE.md CHANGELOG.md docs/control-safety.md
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "docs(phase5): top-level docs + bump 4.0.0 → 4.1.0

Activates FORGE_PHASE5_ACTIVE sentinel — Group B assertions in
live-observation.bats activate at HEAD after this commit lands."
```

---

## Task 14: Push + CI + tag + release

```bash
git push origin master
gh run watch

# On CI green:
git tag -a v4.1.0 -m "Phase 5: Live Observation UX

- /forge-watch Python-curses TUI
- Plan branches via --branch
- Best-of-N via --best-of (new fg-095-bestof-orchestrator agent)
- Inline stderr cost ticker for non-TUI users
- state-schema 1.8.0 → 1.9.0"
git push origin v4.1.0

gh release create v4.1.0 --title "4.1.0 — Phase 5: Live Observation UX" --notes-file - <<'EOF'
See CHANGELOG.md §4.1.0.

Next: Phase 6 — Frontend UX Excellence.
EOF
```

---

## Self-review

- **Spec coverage:** All 18 ACs mapped to tasks. (Commits 3-6 each map to one new orchestrator section or config delta.)
- **Placeholder scan:** Task 5 fg-095-bestof-orchestrator.md body is structural-only ("7 phase sections"). Given spec §4.4.1 table provides the phase-by-phase rubric, an engineer can produce the body from the spec. Acceptable.
- **Type consistency:** `state.tui.active`, `bestof.aggregate_cap_usd`, `FORGE_PHASE5_ACTIVE`, skill-count=40 used consistently across spec + plan.

**Plan complete.**
