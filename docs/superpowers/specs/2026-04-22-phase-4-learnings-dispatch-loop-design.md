# Phase 4: Learnings Dispatch Loop — Design

**Status:** Draft (2026-04-22).
**Author:** Denis Šajnar (solo).
**Supersedes:** none — this is the first design round for the read path.

## Goal

Make the learnings corpus actually influence agent behavior at dispatch time. Today `shared/learnings/*.md` and `.claude/forge-log.md` are written by `fg-700-retrospective` and loaded *once* at PREFLIGHT into the shaper's context. Every other subagent — planner, implementer, reviewers, quality gate — runs blind of what prior runs already discovered. The system is **write-only**. This phase closes the loop by adding a decay-aware, domain-filtered, per-agent-relevant injection layer that runs on *every* dispatch in stages where learnings can realistically help.

## Problem Statement

Gaps in the current code path, with citations:

- **Injection happens once, at PREFLIGHT.** `agents/fg-100-orchestrator.md:553–575` describes §0.6 "PREEMPT System + Version Detection" as a PREFLIGHT-only activity — items are collected, domain-filtered, decay-adjusted, and then passed downstream as part of the *explore* dispatch. The planner dispatch at `agents/fg-100-orchestrator.md:1040–1051` includes `PREEMPT learnings: [matched items]` as a *one-shot* field; there is no re-selection per stage.
- **Implementer receives a bag, not a filter.** `agents/fg-100-orchestrator.md:1214` passes "PREEMPT" into the implementer brief but the content is whatever PREFLIGHT produced — no re-ranking against the specific task, no recency bias.
- **Reviewers never read learnings at all.** Grep across `agents/fg-410*.md` through `agents/fg-419*.md` returns zero hits for `learnings` or `PREEMPT`. The security reviewer has no access to `SEC-*` priors; the architecture reviewer has no access to architectural-smell priors. Same anti-patterns get re-flagged (or re-missed) run after run.
- **Decay contract exists, but there is no selector.** `shared/learnings/decay.md:8` gives `confidence(t) = base_confidence × 2^(-Δt_days / half_life_days)` and `hooks/_py/memory_decay.py:39` implements `effective_confidence()` — but no caller ever uses the result to *rank* candidate learnings for a specific agent. The decay layer is only read by PREFLIGHT's bulk loader.
- **Reinforcement signal is thin.** `shared/agent-communication.md:261–270` defines `PREEMPT_APPLIED` / `PREEMPT_SKIPPED` markers scoped to the implementer. No analogous signal from reviewers or planner, so learnings that helped design never reinforce.
- **Cross-project file is a separate namespace.** `shared/cross-project-learnings.md:25–31` loads `~/.claude/forge-learnings/{framework}.md` only at PREFLIGHT, also as MEDIUM-seeded PREEMPT items — same blind-spot downstream.

## Non-Goals

- **Not changing PREEMPT discovery.** `shared/learnings/memory-discovery.md` and its auto-discovery path stay exactly as they are. Phase 4 touches only the *read* path.
- **Not changing `fg-700-retrospective`'s extraction logic.** The retrospective still decides what to write; this phase only extends it to *update counts* based on injection telemetry.
- **No learnings UI.** No new skill, no dashboard. `/forge-ask insights` already surfaces PREEMPT health; that stays untouched for now.
- **No new storage.** Everything lives in the existing `shared/learnings/*.md` files, the existing `.forge/events.jsonl` event log, and the existing OTel span stream.

## Approach

Three architectural choices considered:

1. **Ambient context file.** Write a selected-learnings snapshot to `.forge/current-learnings.md` at PREFLIGHT and have every subagent read it. *Rejected.* No per-agent filtering; snapshot goes stale as the run proceeds through stages that reveal new domain hotspots.
2. **Per-agent embedded blocks (this design).** The orchestrator calls a pure selector function just before each dispatch; results are formatted as a `## Relevant Learnings` block appended to the dispatch prompt. The selector is agent-aware, stage-aware, and domain-aware.
3. **Agent-side pull.** Each agent queries the selector itself via a shared MCP tool. *Rejected for now.* Adds MCP surface, couples every agent to a stateful store, and makes dispatch prompts non-reproducible for test fixtures.

Choice **2** keeps the orchestrator as the sole writer of agent context (the invariant in `shared/agent-communication.md:142`), keeps the selector pure and testable, and is stable enough for contract tests to assert on.

**Reference patterns.** LangGraph's `langgraph.store.base.BaseStore` exposes a namespaced key-value API where agents call `store.search(namespace, query)` at each node — pull-based. CrewAI's short-term memory wraps the agent's LLM call so retrieval happens *inside* the agent rather than at the dispatch seam. Our divergence: forge keeps the orchestrator as the sole context writer (preserving our deterministic dispatch-prompt contract) and uses a pure-function selector so tests can assert on exact output. Injection at the dispatch seam — not inside the agent — also plays nicer with our isolated-subagent model (`shared/agents.md`), where subagents see only their dispatch prompt.

## Components

### 1. Selector service (`shared/learnings_selector.py`)

Pure function, stdlib + existing `hooks._py.memory_decay`:

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class LearningItem:
    id: str
    source_path: str            # file path + anchor
    body: str                   # markdown snippet, already truncated
    base_confidence: float
    confidence_now: float       # decayed at selection time
    half_life_days: int
    applied_count: int
    last_applied: str | None    # ISO-8601
    applies_to: tuple[str, ...] # {"planner", "implementer", "reviewer.security", ...}
    domain_tags: tuple[str, ...]
    archived: bool

def select_for_dispatch(
    agent: str,
    stage: str,
    domain_tags: list[str],
    component: str | None,
    candidates: list[LearningItem],
    now: datetime,
    max_items: int = 6,
    min_confidence: float = 0.4,
    sparse_threshold: int = 10,
) -> list[LearningItem]: ...
```

`candidates` are pre-loaded by a thin I/O wrapper (`shared/learnings_io.py`) that walks `shared/learnings/*.md` and `~/.claude/forge-learnings/*.md`, parsing the v2 frontmatter (see §5). The wrapper is the *only* side-effectful part; unit tests hit `select_for_dispatch` with hand-built `candidates`.

**Ranking formula** (deterministic, tie-broken by `id`):

```
score = confidence_now
        * domain_match_score
        * recency_bonus
        * cross_project_penalty

domain_match_score = |tags ∩ domain_tags| / max(1, |tags|)   # tags = learning's domain_tags
recency_bonus      = 1.0 if applied within 30 days
                     0.85 if 30-90 days
                     0.7  if >90 days or never applied
cross_project_penalty = 0.85 if source_path under ~/.claude/forge-learnings/
                        AND current project's learnings_density > sparse_threshold
                        else 1.0
```

Filters applied before ranking: `archived=False`; `agent` name or its role-prefix (`reviewer.security`, `reviewer.architecture`, etc.) must appear in `applies_to`; `confidence_now ≥ min_confidence`. Items that pass are sorted by `score` descending and truncated to `max_items`.

`sparse_threshold` (default 10, exposed as module constant
`SPARSE_THRESHOLD` in `hooks/_py/memory_decay.py`) controls the
cross-project penalty switch: the penalty applies only when the current
project's `learnings_density` (count of candidate items sourced under
`shared/learnings/` for the active framework/component) exceeds this
threshold. Sparse projects therefore benefit fully from cross-project
priors; dense projects down-weight them in favour of local evidence.

### 2. Orchestrator injection (`fg-100-orchestrator`)

New substage between dispatch prep and the actual `Task` call. The orchestrator's dispatch helper:

```
1. Read current task's domain_tags from state.json (set during EXPLORE/PLAN).
2. Load candidates via learnings_io (cached per-run; invalidated at LEARN).
3. Call select_for_dispatch(agent=<agent_name>, stage=<STAGE>, ...).
4. Format results into the "## Relevant Learnings" block (exact format below).
5. Append block to dispatch prompt *after* task description, *before* any tool
   hints. Skip entirely when selector returns [].
6. Emit one `forge.learning.injected` event via `emit_event_mirror` per selected item (see §7).
```

**Stable injection format** (contract tests assert on this verbatim):

```markdown
## Relevant Learnings (from prior runs)

The following patterns recurred in this codebase. Consider them during your
work, but verify each — they are priors, not rules.

1. [confidence 0.82, 3× applied] Persistence layer tends to leak
   `@Transactional` boundaries. Look for handler methods calling repository
   methods without explicit transaction scope.
   - Source: shared/learnings/spring-persistence.md#tx-scope
   - Decay: 30d half-life, last applied 2026-04-18

2. [confidence 0.71, 1× applied] Kotest `describe` blocks with shared state…
   (body truncated at 400 chars)
   - Source: shared/learnings/kotest.md#shared-state
   - Decay: 30d half-life, last applied 2026-03-29
```

Rules: **max 6 items**, body truncated at **300 chars** on the last whitespace
boundary before 300 with `…` suffix (≈450 tokens block total). These tighter
bounds preserve the existing `<2k dispatch prompts` budget at
`agents/fg-100-orchestrator.md:77` without requiring a bump. `confidence`
rounded to 2 decimals; `applied N×` omitted when `applied_count == 0`;
`last applied <ISO-date>` omitted when `last_applied is None`.

(The earlier stage-notes `2,000 tokens` cap at `shared/agent-communication.md:36`
is unrelated — that governs inter-stage notes, not dispatch prompts.)

### 3. Per-agent relevance filter

Each learning's frontmatter (§5) declares `applies_to`. Canonical values:

- `planner` — architecture, design, API shape priors
- `implementer` — API pitfalls, framework gotchas, deprecation warnings, scaffold patterns
- `reviewer.code`, `reviewer.security`, `reviewer.architecture`, `reviewer.frontend`, `reviewer.performance`, `reviewer.dependency`, `reviewer.docs`, `reviewer.infra`, `reviewer.license` — mapped 1:1 to `fg-410..419`
- `quality_gate` — meta-learnings (e.g., "runs plateau when score hits 82 with ≥3 WARNINGs")
- `test_gate` — flaky-test priors, mutation-testing hotspots
- `bug_investigator` — root-cause patterns

The orchestrator maps `agent` → role key before calling the selector. `fg-411-security-reviewer` → `reviewer.security`; `fg-300-implementer` → `implementer`; unknown agents → empty filter → selector returns `[]`.

**Agent → role-key mapping** (authoritative; cross-linked from
`shared/agent-communication.md` §Learning Markers):

```
planner               → fg-200-planner
implementer           → fg-300-implementer
reviewer.code         → fg-410-code-reviewer
reviewer.security     → fg-411-security-reviewer
reviewer.architecture → fg-412-architecture-reviewer
reviewer.frontend     → fg-413-frontend-reviewer
reviewer.license      → fg-414-license-reviewer
reviewer.performance  → fg-416-performance-reviewer
reviewer.dependency   → fg-417-dependency-reviewer
reviewer.docs         → fg-418-docs-consistency-reviewer
reviewer.infra        → fg-419-infra-deploy-reviewer
```

`quality_gate` maps to `fg-400-quality-gate`; `test_gate` to `fg-500-test-gate`;
`bug_investigator` to `fg-020-bug-investigator`. The mapping lives
in code at `hooks/_py/agent_role_map.py` (single source of truth).

Domain affinity from `shared/checks/category-registry.json` is NOT reused here — learnings pre-declare `domain_tags` like `["spring", "persistence"]` which the selector matches against the run's `domain_tags`. This keeps the learnings schema independent of the findings-category registry (category names evolve; learning tags should not churn).

### 3.1. Marker Protocol (false-positive attribution)

Reinforcement and false-positive write-back are driven by **explicit markers
in stage notes** — never by fuzzy overlap between findings and learnings.
This mirrors the existing `PREEMPT_APPLIED` / `PREEMPT_SKIPPED` contract at
`shared/agent-communication.md:261–270`.

Markers an agent may emit:

- `LEARNING_APPLIED: <id>` — the learning guided the agent's output (a
  reviewer flagged the pattern, the planner folded it into the plan, the
  implementer consulted it before a decision). Emitted by planner,
  implementer, quality gate, reviewers.
- `LEARNING_FP: <id> reason=<short-free-text>` — the learning was shown but
  is **inapplicable** or **wrong** for this run. The only signal that
  triggers `apply_false_positive`. Reviewers emit this when they read an
  injected learning and reject it; implementers emit it analogously to
  `PREEMPT_SKIPPED`.
- `LEARNING_VINDICATED: <id> reason=<...>` — user-initiated (or a later
  retrospective's) override that a past FP was unjustified; writes the
  `forge.learning.vindicated` event.

The retrospective **only** decrements `base_confidence` on `LEARNING_FP` or
`PREEMPT_SKIPPED` markers. A reviewer raising a CRITICAL finding in the same
`domain_tag` is **not** sufficient evidence of a false-positive — that rule
was too coarse and would punish learnings for being *topical* rather than
*wrong*. See AC9 below for the updated acceptance criterion.

### 4. Decay + reinforcement math

The existing `hooks/_py/memory_decay.py` already implements the curve. This phase exposes it as the single source of truth and adds the selector's unit tests.

```
confidence_now(item, now) = min(
    MAX_BASE_CONFIDENCE,
    base_confidence * math.exp(-λ * Δt_days)
)
where λ = math.log(2) / half_life_days
      Δt_days = clamp((now - last_success_at).total_seconds() / 86400, 0, 365)
```

Units: `half_life_days` is days (integer), `Δt_days` is fractional days, `λ` is per-day. `MAX_BASE_CONFIDENCE = 0.95`. The existing code uses `math.pow(2.0, -Δt/h)` which is mathematically identical to `math.exp(-ln(2)·Δt/h)`; we keep `math.pow` in code and document the equivalent `math.exp` form so tests can assert either.

**Reinforcement** (on `PREEMPT_APPLIED` or equivalent review-side signal):

```
base_confidence := min(0.95, base_confidence + 0.05)
last_applied    := now
applied_count   += 1
pre_fp_base     := null          # clear any stale FP snapshot on success
```

**False positive** (on `PREEMPT_SKIPPED: <inapplicability reason>` or an
explicit `LEARNING_FP: <id>` marker in stage notes — see §3.1 Marker Protocol
below; the retrospective **only** decrements on these explicit markers, never
on inferred category/file overlap):

```
pre_fp_base            := base_confidence            # snapshot before penalty
base_confidence        := base_confidence * 0.80
last_false_positive_at := now
false_positive_count   += 1
```

`pre_fp_base` is a new frontmatter field (nullable, default `null`). It holds
the exact pre-penalty `base_confidence` so vindication can restore losslessly.
It is cleared on the next `apply_success` (see reinforcement block above —
append `pre_fp_base := null` to that transition).

**Rollback / vindication.** A user may mark a rejection as wrong via an
event-log entry `{"type": "forge.learning.vindicated", "id": "<item-id>"}`.
The retrospective reads it and:

```
base_confidence        := pre_fp_base                # restore exact snapshot
pre_fp_base            := null
false_positive_count   -= 1
last_false_positive_at := null
```

If `pre_fp_base is None` (defensive — shouldn't happen) the retrospective
logs a WARNING and falls back to `base_confidence := min(0.95, base * 1.25)`,
explicitly marking the item in the write-back log line.

**Why snapshot, not division.** `base * 0.80 / 0.80` is algebraically the
identity but floating-point lossy. Repeated FP/vindicate cycles would drift
upward and eventually touch the 0.95 ceiling. The snapshot restores bit-exact.
See test #4 below.

**Archival floor.** After retrospective write-back: if `confidence_now < 0.1`
AND `(now - last_applied).days > 90` (or `last_applied is None` AND
`(now - first_seen).days > 90`) → set `archived = true`. Archived items are
skipped by the selector *and* by the loader (saves parse time).

**Unit tests** (`tests/unit/test_learnings_decay.py`, CI-only, 5 scenarios):

1. *Fresh learning*: `base=0.75, age=0d, half_life=30` → `confidence_now ≈ 0.75`.
2. *One half-life*: `base=0.80, age=30d, half_life=30` → `confidence_now ≈ 0.40`.
3. *Success reinforcement hits ceiling*: 20 consecutive `apply_success` on a `base=0.85` item → final `base == 0.95`.
4. *False-positive penalty is lossless over N cycles*: start `base=0.80`. Apply 100 consecutive `apply_false_positive` + `vindicate` pairs. Final `base` **exactly equals** `0.80` (bit-exact `==`, not just `abs(...) < 1e-9`); `pre_fp_base is None` after the last vindicate; `false_positive_count == 0`. A second test asserts single-cycle `base=0.80 → apply_false_positive → 0.64 → vindicate → 0.80` (bit-exact).
5. *Archival floor*: `base=0.30, age=180d, half_life=14, last_applied=None, first_seen=180d ago` → `confidence_now < 0.1` AND `archived == True`.

### 5. Learnings file schema v2

Every `shared/learnings/*.md` and `~/.claude/forge-learnings/*.md` gets a structured frontmatter:

```yaml
---
schema_version: 2
items:
  - id: "spring-tx-scope-leak"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 5
    last_applied: "2026-04-18T14:22:33Z"
    first_seen: "2026-01-04T10:00:00Z"
    false_positive_count: 0
    last_false_positive_at: null
    applies_to: ["planner", "implementer", "reviewer.security"]
    domain_tags: ["spring", "persistence"]
    source: "cross-project"       # auto-discovered | cross-project | canonical
    archived: false
    body_ref: "#tx-scope"         # anchor in the markdown body
---
# Human-readable learnings

## tx-scope
The pattern is: handlers call repository methods without an explicit
@Transactional boundary, so writes happen in auto-commit mode and rollback
on exception is impossible…
```

Fields:

- `id` — stable, kebab-case, globally unique within the file. Used as selector sort tiebreaker and as OTel attribute.
- `base_confidence` — authoritative value; selector computes `confidence_now` from it each call.
- `half_life_days` — overrides the per-source default from `hooks/_py/memory_decay.py:HALF_LIFE_DAYS` when set.
- `applied_count` / `false_positive_count` — monotonic counters; only decremented via explicit vindication.
- `last_applied` / `last_false_positive_at` — ISO-8601 UTC. Missing → never.
- `first_seen` — required for archival floor. Migration (see §Migration below) stamps file mtime. Note: `first_seen` mtime is install-time for git-tracked files (`git checkout` rewrites mtime on clone); this is an accepted approximation and is corrected on the next retrospective update when an item's actual first-observation timestamp is re-derived from `.forge/events.jsonl`.
- `applies_to` — canonical role keys from §3.
- `domain_tags` — free-form but stabilised against the set of framework/language/layer tokens used by `shared/domain-detection.md`.
- `source` — drives default `half_life_days` when the field is absent.
- `body_ref` — markdown anchor; the loader extracts the corresponding `##` section and truncates at 400 chars for the selector's `body` field.

**Migration.** One-shot script `scripts/migrate_learnings_schema.py` parses
the existing **hybrid** format (file-level frontmatter PLUS per-item prose
markers) and emits v2 frontmatter in place. The real fixtures under
`shared/learnings/` today look like `shared/learnings/spring.md`:

```markdown
---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
---
# Cross-Project Learnings: spring

## PREEMPT items

### KS-PREEMPT-001: R2DBC updates all columns
- **Domain:** persistence
- **Pattern:** R2DBC update adapters must fetch-then-set ...
- **Applies when:** `persistence: r2dbc`
- **Confidence:** HIGH
- **Hit count:** 0
```

The migrator **preserves** the file-level frontmatter keys it recognises
(`decay_tier`, `last_success_at`, `last_false_positive_at`) — they inform
the per-item defaults — and produces one `items:` entry per `###` PREEMPT
heading. Derivation rules (all applied in order; each `item` gets every
field):

| v2 field | Source |
|---|---|
| `id` | Derived from the `###` heading. If the heading starts with a token matching `^[A-Z][A-Z0-9-]+-\d+:` (e.g., `KS-PREEMPT-001:`), the id is that token stripped of the trailing `:` and lowercased with `-` kept (→ `ks-preempt-001`). Otherwise the id is the kebab-case slug of the remaining heading text. |
| `base_confidence` | Per-item `**Confidence:** HIGH/MEDIUM/LOW` line mapped: `HIGH → 0.85`, `MEDIUM → 0.65`, `LOW → 0.45`. If absent, use file-level `default_base_confidence` or `0.75`. Note: these per-item numbers differ from the heading-text-map documented earlier in `shared/learnings/spring.md` (`HIGH → 0.95`) — the v2 spec deliberately lowers them so `+0.05` reinforcement still has headroom under the 0.95 ceiling. |
| `half_life_days` | From file-level `decay_tier` via `hooks/_py/memory_decay.py` source-defaults: `auto-discovered → 14`, `cross-project → 30`, `canonical → 90`. |
| `applied_count` | Per-item `**Hit count:** N` line. Missing → `0`. |
| `last_applied` | File-level `last_success_at` if `applied_count > 0`, else `null`. (Per-item precision is lost; accepted trade-off.) |
| `first_seen` | File mtime (approximation — see §7 minor notes). |
| `false_positive_count` | `0` (no historical per-item FP data). |
| `last_false_positive_at` | File-level `last_false_positive_at` when non-null AND `applied_count == 0`, else `null`. |
| `pre_fp_base` | `null`. |
| `applies_to` | `["planner", "implementer", "reviewer.code"]` — conservative default; a second manual pass refines reviewer roles per-item. |
| `domain_tags` | First, the `**Domain:** <tag>` line if present. Then union with tokens parsed from the filename stem (`kotlin.md → ["kotlin"]`, `spring-persistence.md → ["spring", "persistence"]`). De-duplicated, order-preserved. |
| `source` | File-level `decay_tier` verbatim (`cross-project`, `auto-discovered`, `canonical`). |
| `archived` | `true` iff the heading text contains `(archived)` or the file-level `decay_tier == "archived"`; else `false`. |
| `body_ref` | `#<id>` — the migrator inserts an HTML anchor `<a id="<id>"></a>` immediately after the `###` heading so existing heading-slug anchors keep working. |

The body prose (`- **Pattern:** …`, `- **Applies when:** …`, etc.) is left
untouched below the frontmatter; the loader extracts 400 chars starting
from the `body_ref` anchor for injection.

The migrator is idempotent: re-running on a v2 file is a no-op. Run once,
commit, delete the script (per the "no backcompat, no migration shims" rule).

### 6. Retrospective write-back

`fg-700-retrospective` currently updates hit counts from `preempt_items_status`. Extend its Stage 9 logic:

1. Read the event log (`.forge/events.jsonl` → `hooks/_py/otel.replay`) and collect all `forge.learning.injected`, `forge.learning.applied`, `forge.learning.fp`, and `forge.learning.vindicated` events for the run.
2. For each `(agent, learning_id)` pair observed in `forge.learning.injected`:
   - If the downstream stage reached `PASS` **and** the same `(agent, learning_id)` appears in a `forge.learning.applied` event (implementer `PREEMPT_APPLIED` marker or reviewer/planner `LEARNING_APPLIED: <id>` marker, translated to the event by the orchestrator): `apply_success(item, now)`.
   - If a `forge.learning.fp` event exists for `learning_id` (driven by a `LEARNING_FP: <id>` marker or an inapplicability-flagged `PREEMPT_SKIPPED`): `apply_false_positive(item, now)`. **Do not infer FPs from finding/domain overlap** — see §3.1.
   - If a `forge.learning.vindicated` event exists: `apply_vindication(item, now)` using the `pre_fp_base` snapshot.
   - Else: no update (pure time-decay applies on next PREFLIGHT).
3. Recompute `confidence_now` and the archival floor; set `archived = true` for items under the floor. Write the updated v2 frontmatter back atomically.
4. Emit one structured-output line per updated item: `learning-update: id=<id> Δbase=<delta> archived=<bool>`.

Reinforcement for planner/quality-gate uses the same `learning.applied` event — the planner emits it as part of its plan structured output (new field `plan.learnings_used: [ids]`); the quality gate does so via a final summary attribute.

### 7. Telemetry

New events emitted via the existing `emit_event_mirror` pattern in
`hooks/_py/otel.py:207` — the durability-first path that writes to
`.forge/events.jsonl` first (fsync'd by F07) and mirrors onto the active
span as attributes. We do **not** introduce a new `span.add_event` idiom.
All attribute keys use the `forge.*` prefix (Phase 6 reviewer flagged
`learning.*` as inconsistent with the rest of the attribute catalog in
`hooks/_py/otel_attributes.py`).

Events are emitted inside the orchestrator's dispatch helper while the
`otel.agent_span` context for the target subagent is active:

```python
from hooks._py import otel

with otel.agent_span(name=agent, model=..., description=...):
    for item in selected:
        otel.emit_event_mirror({
            "type": "forge.learning.injected",
            "forge.learning.id": item.id,
            "forge.learning.confidence_now": round(item.confidence_now, 4),
            "forge.learning.applied_count": item.applied_count,
            "forge.learning.source_path": item.source_path,
            "forge.agent.name": agent,
            "forge.stage": stage,
        })
    # ... Task(subagent) dispatch ...
```

Reciprocal event `forge.learning.applied` is emitted by the orchestrator
when it parses a `PREEMPT_APPLIED` or `LEARNING_APPLIED` marker from stage
notes, with the same `forge.learning.id` / `forge.agent.name` / `forge.stage`
attributes. `forge.learning.fp` is emitted on `LEARNING_FP` / inapplicability
`PREEMPT_SKIPPED`; `forge.learning.vindicated` on user vindication.

Retrospective reads all four event types via `otel.replay` (authoritative
path; §Durability in `shared/observability.md`).

New attribute names to register in `hooks/_py/otel_attributes.py`:

```python
FORGE_LEARNING_ID             = "forge.learning.id"
FORGE_LEARNING_CONFIDENCE_NOW = "forge.learning.confidence_now"
FORGE_LEARNING_APPLIED_COUNT  = "forge.learning.applied_count"
FORGE_LEARNING_SOURCE_PATH    = "forge.learning.source_path"
```

Attribute cardinality: `forge.learning.id` is per-item (bounded by the
learnings corpus, ~500 items today); safe as attribute, never as span name.

## Data Model

- **`LearningItem`** — see §1. Immutable, constructed by `learnings_io`, passed by value into the selector.
- **Schema v2 frontmatter** — see §5 for field-by-field description.
- **`forge.learning.injected` event** — schema in §7; lives in `.forge/events.jsonl` and mirrored onto the active span as attributes via `emit_event_mirror`.
- **`forge.learning.applied` event** — `{type: "forge.learning.applied", forge.run_id, forge.agent.name, forge.stage, forge.learning.id, file, line}`; written by the orchestrator on marker parse.
- **`forge.learning.fp` event** — `{type: "forge.learning.fp", forge.run_id, forge.learning.id, reason}`; written on `LEARNING_FP` / inapplicable `PREEMPT_SKIPPED`.
- **`forge.learning.vindicated` event** — `{type: "forge.learning.vindicated", forge.run_id, forge.learning.id, reason}`; written by user action (future `/forge-ask insights --vindicate <id>` skill, out of scope here — the event consumer is specced now so it lands right the first time).

## Data Flow

```
LEARN (retrospective) → writes v2 frontmatter      (source of truth on disk)
    ↓
next PREFLIGHT → learnings_io.load_all()           (parse all .md frontmatter)
    ↓
orchestrator caches candidates per-run             (invalidated at LEARN)
    ↓
per-dispatch → select_for_dispatch(...)            (pure; O(N log N) on ~500 items)
    ↓
formatted ## Relevant Learnings block appended to dispatch prompt
    ↓
subagent reads block, may emit PREEMPT_APPLIED / LEARNING_APPLIED / LEARNING_FP markers
    ↓
orchestrator parses markers → emit_event_mirror(forge.learning.applied | .fp)
    ↓
at dispatch: emit_event_mirror(forge.learning.injected) per selected item
    ↓
LEARN reads events via otel.replay → apply_success / apply_false_positive
    ↓
back to top
```

## Error Handling

- **Schema v1 file encountered post-migration.** Skip the file, log one WARNING per run: `"learnings: v1 file at <path> — rerun scripts/migrate_learnings_schema.py"`. Selector proceeds with remaining v2 files.
- **Frontmatter parse error.** Skip the file, log WARNING with parser exception summary. No silent item loss — count skipped files in retrospective.
- **OTel disabled / exporter unavailable.** Selector still runs; event emissions become no-ops via the existing `otel._STATE.enabled` guard (`hooks/_py/otel.py:102`). Retrospective falls back to reading markers directly from stage notes (today's path).
- **Candidates exceed selector budget.** Hard cap `max_items = 6`; selector truncates post-ranking. Logged as INFO in stage notes: `"learnings: 47 candidates → 6 injected for fg-300-implementer"`.
- **`domain_tags` empty for a task.** Selector falls back to role-only filter; `domain_match_score` defaults to `0.5` so items aren't totally suppressed.
- **Clock skew / future `last_applied`.** `Δt_days` clamped to `[0, 365]` in the existing decay code; selector inherits this.

## Testing Strategy

- **Pure-function tests** (`tests/unit/test_learnings_selector.py`): 8+ cases — agent-role filter, domain intersection, archived skip, confidence floor, recency tiers, tiebreak by `id`, empty `candidates`, `max_items=6` truncation with stable ordering.
- **Decay unit tests** (`tests/unit/test_learnings_decay.py`): 5 scenarios from §4.
- **Injection format contract test** (`tests/contract/learnings_injection_format.bats`): assert on the verbatim markdown block given a fixed `LearningItem` list; catches accidental format drift.
- **Integration test** (`tests/integration/learnings_dispatch_loop.py`): run a fake pipeline with a scripted orchestrator, feed known candidates, assert `learning.injected` events fired with expected `learning.id` + `agent.name` combinations and that `apply_success` was invoked on exactly the items with matching `LEARNING_APPLIED` markers.
- **No local test runs per repo policy.** CI is the only runner.

## Documentation Updates

- `CLAUDE.md` — §Learnings/PREEMPT system gets a "Read path (Phase 4)" subsection; §Core contracts adds the selector module; §Agents gets a "## Learnings Injection" one-liner per affected agent.
- `shared/learnings/README.md` — replace §PREEMPT Lifecycle prose with a pointer to the selector and add a §Read Path section mirroring the existing §Write Path structure.
- `shared/learnings/decay.md` — replace prose formula with the explicit `math.exp` form from §4; keep worked examples; cross-reference `tests/unit/test_learnings_decay.py`.
- `shared/cross-project-learnings.md` — document the `cross_project_penalty` factor and the "sparse history" override.
- `agents/fg-200-planner.md`, `agents/fg-300-implementer.md`, `agents/fg-400-quality-gate.md`, `agents/fg-410..419-*.md` — each gains a `## Learnings Injection` section (3–5 lines): what role key maps to this agent, where the block appears in their prompt, and the expected marker format on return.
- `shared/observability.md` — §Attributes gets `forge.learning.id`, `forge.learning.confidence_now`, `forge.learning.applied_count`, `forge.learning.source_path` under a new "Learning events" subsection; cardinality table updated. Documents the four event types (`forge.learning.injected | applied | fp | vindicated`) as emitted via `emit_event_mirror`.
- `shared/agent-communication.md` — new §Learning Markers subsection parallel to §PREEMPT Markers, documenting `LEARNING_APPLIED: <id>`, `LEARNING_FP: <id> reason=<...>`, and the agent → role-key mapping table cross-linked from §3 of this spec.

## Acceptance Criteria

1. `shared/learnings_selector.py` exports `select_for_dispatch` with the signature in §1; 100 % unit-test coverage on the pure function.
2. `hooks/_py/memory_decay.py` is the single module consulted for decay math; no other module recomputes the curve. **Enforcement:** a structural test at `tests/structural/learnings_decay_singleton.bats` greps the repo and fails if any file outside `hooks/_py/memory_decay.py` contains `math.pow` with `half_life` as a nearby token (within 3 lines), or `math.exp` alongside `λ` / `lambda_` variable adjacency. The test is a regex grep, not a taint analysis — simple and deterministic.
3. `scripts/migrate_learnings_schema.py` converts every existing `shared/learnings/*.md` file to v2 in-place in a single commit; running it again is a no-op (idempotent).
4. `fg-100-orchestrator` appends the `## Relevant Learnings` block to dispatch prompts for: `fg-200-planner`, `fg-300-implementer`, `fg-400-quality-gate`, and every reviewer `fg-410..fg-419`. Verified by a contract test that greps dispatch fixtures for the exact header string.
5. Selector never returns more than 6 items per call (default `max_items=6`); verified by unit test.
6. Injection format matches the verbatim sample in §2; verified by `tests/contract/learnings_injection_format.bats`.
7. Every injection emits a `forge.learning.injected` event via `emit_event_mirror` with `forge.learning.id`, `forge.learning.confidence_now`, `forge.agent.name`, `forge.stage` attributes. Verified by integration test inspecting `.forge/events.jsonl`.
8. `fg-700-retrospective` updates `base_confidence` and `applied_count` for items that produced `forge.learning.applied` events during the run; verified by integration test that runs two fake pipelines and asserts the second run sees increased `applied_count`.
9. False-positive write-back triggers `base_confidence *= 0.80` **only** on an explicit `LEARNING_FP: <id>` marker in stage notes (or a `PREEMPT_SKIPPED` with inapplicability reason that references the same id). A reviewer raising a CRITICAL in the learning's domain is **not** sufficient. Verified by two integration tests: (a) CRITICAL in same `domain_tag` without marker → `base_confidence` unchanged; (b) explicit `LEARNING_FP` marker → `base_confidence *= 0.80` AND `pre_fp_base` snapshot recorded.
10. Items crossing the archival floor (`confidence_now < 0.1` AND `last_applied` gap > 90 d) are set `archived: true` by the retrospective; verified by unit test on the frontmatter writer.
11. `applies_to` filter is honored — a `fg-411-security-reviewer` dispatch never receives an item whose `applies_to` omits `reviewer.security`; verified by unit test.
12. Schema v1 files encountered at runtime produce a single WARNING and are skipped (do not crash the selector); verified by unit test with a crafted v1 fixture.

## Open Questions

1. **Reviewer-side marker emission.** Reviewers today produce structured findings, not free-form prose. Adding `LEARNING_APPLIED: <id>` likely goes into their structured output block (schema `coordinator-output/v1`, `shared/agent-communication.md:291`). Does that require a schema bump or can it live under `findings[].learnings_referenced: [id]`? Leaning toward the latter; deferring to implementation.
2. **Cross-project penalty threshold.** `learnings_density > sparse_threshold` needs a concrete value. Proposal: `sparse = len(candidates from shared/learnings/{framework}.md) < 5`. Revisit after one week of telemetry.
3. **Archival visibility in `/forge-ask insights`.** Archived items currently still render in the insights "PREEMPT health" panel. Should the read path filter them too, or should insights grow an `--include-archived` flag? Not in scope for Phase 4 but the decision affects the archival semantics — flagging for follow-up.
