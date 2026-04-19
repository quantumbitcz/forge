# Phase 13 — Memory Decay (Ebbinghaus Exponential Curve)

**Date:** 2026-04-19
**Phase:** 13 (A+ roadmap)
**Priority:** P2
**Status:** Design

---

## 1. Goal

Replace Forge's counter-based PREEMPT decay ("10 unused runs → demote; 1 false positive = 3 unused") with a time-aware Ebbinghaus exponential forgetting curve `confidence(t) = base × 2^(-Δt / half_life)`, where `half_life` varies by item type (auto-discovered 14d, canonical 90d, cross-project 30d), so that staleness (confidently-wrong memories) is distinguished from irrelevance and rules unused for six months decay very differently from rules unused for six runs.

---

## 2. Motivation

Audit finding **W15 — counter-based decay conflates staleness with irrelevance**. The current model in `shared/learnings/README.md` §PREEMPT Lifecycle counts *consecutive unused runs* and ignores wall-clock time: a rule that hasn't matched in ten pipeline runs over two days is demoted at the same rate as one unused over six months. This produces two failure modes the system cannot separate:

1. **Stale-confident memory** — a rule whose underlying framework or codebase truth has shifted, but which still scores HIGH because it was applied heavily in the recent past. Mem0's *State of AI Agent Memory 2026* (https://mem0.ai/blog/state-of-ai-agent-memory-2026) names this as a distinct failure class from plain irrelevance and argues that run-count-based decay is the root cause.
2. **Sporadic-but-valid memory** — a rule that fires only when its domain is touched (e.g. a database migration convention) and sees ten "unused" runs simply because the project stayed in application code. The counter model demotes it unfairly.

The Ebbinghaus forgetting curve (Ebbinghaus, *Über das Gedächtnis*, 1885; formalized in psychology and re-used across spaced-repetition memory systems and modern agent memory stacks including Mem0, MemGPT, and Letta) is the standard calibration: retention decays exponentially with wall-clock time, with a characteristic half-life that depends on the strength and type of the memory trace. Applying it here lets us track "this memory has not been reinforced in *N days*" — the actual signal — instead of a proxy that happens to correlate only when pipelines run at a fixed cadence.

No backwards compatibility with the counter-based model is kept. A one-time on-load migrator stamps existing items with `last_success_at = now` and lets them decay from a warm start.

**References:**
- W15 audit finding (2026-04-19 A+ audit)
- Mem0, *State of AI Agent Memory 2026*: https://mem0.ai/blog/state-of-ai-agent-memory-2026
- Ebbinghaus, H. (1885). *Über das Gedächtnis.* — origin of the exponential forgetting curve.

---

## 3. Scope

### In scope

- New decay function with time-aware parameters, exported from `shared/learnings/decay.md` and implemented in `hooks/_py/memory_decay.py`.
- Per-item-type half-life: auto-discovered = 14 days, cross-project (`shared/learnings/*.md` items) = 30 days, canonical (user-confirmed / promoted) = 90 days.
- False-positive penalty: drops `base_confidence` by 20 % and resets the elapsed-time clock (`last_false_positive_at = now`).
- Success rejuvenation: resets the clock (`last_success_at = now`) and adds +5 % to `base_confidence`, capped at 1.0.
- Retrospective (`fg-700`) computes decay on every run during the LEARN stage, writes updated confidences back to `forge-log.md` and `.forge/memory/` records.
- `.forge/memory/` item records gain three new fields: `last_success_at`, `last_false_positive_at`, `base_confidence`.
- One-time migrator stamps every existing memory record with `last_success_at = now` on first load after upgrade, then the system runs normally.
- Unit tests for the decay function; CI-only eval harness that injects stale/fresh memories and asserts the half-life math.
- Thresholds table: `confidence ≥ 0.75` = HIGH, `0.5 ≤ c < 0.75` = MEDIUM, `0.3 ≤ c < 0.5` = LOW, `c < 0.3` = ARCHIVED.

### Out of scope

- Per-user or per-project customization of half-life values (the three categories are fixed in v1 — can be added later if telemetry demands).
- Embedding-similarity-based memory merging (Mem0 does this; separate phase).
- Changes to the auto-discovery pipeline itself (`shared/learnings/memory-discovery.md` §Discovery Flow) — only its decay semantics change.
- Changes to the `.forge/knowledge/` active knowledge base state machine. Knowledge items already have an explicit CANDIDATE/VALIDATED/ACTIVE/ARCHIVED lifecycle and do not use the PREEMPT confidence-decay model.
- Local test execution by the implementing engineer — CI runs tests.

---

## 4. Architecture

### 4.1 Decay formula

```
confidence(t) = base_confidence × 2^(-Δt_days / half_life_days)
```

where `Δt_days = (now - last_success_at) / 86_400_000` (ms), `base_confidence ∈ [0, 1]` (default 0.75), and `half_life_days` is chosen from the item's type:

| Item type                             | Half-life (days) | Intuition |
|--------------------------------------|-----------------:|-----------|
| `auto-discovered`                     |               14 | Auto-detected patterns are cheap to re-discover; if they stop reinforcing, archive quickly. (Matches current 2× decay intent.) |
| `cross-project` (`shared/learnings/`) |               30 | Module-generic wisdom decays moderately — framework APIs shift on release cadences of months. |
| `canonical` (user-confirmed, promoted, or `.forge/knowledge/` ACTIVE) | 90 | Human-validated rules are the most stable memory trace; halve only after a quarter of disuse. |

**Type resolution:** item record's explicit `type` field wins; otherwise infer from existing fields (`source: auto-discovered` → auto-discovered; file lives under `shared/learnings/` → cross-project; `source: user-confirmed` or `state: ACTIVE` → canonical; default → cross-project).

### 4.2 Reinforcement and penalty

**Successful application** (agent reported `PREEMPT_APPLIED` with the item's id in the current run, or retrospective detected a hit in stage notes):

```
last_success_at = now
base_confidence = min(1.0, base_confidence + 0.05)
```

**Confirmed false positive** (agent reported `PREEMPT_SKIPPED` with `reason: false_positive`, or retrospective concluded the item's pattern was misapplied):

```
last_false_positive_at = now
base_confidence = base_confidence * 0.80
last_success_at = now   # reset elapsed-time clock so the 20% drop shows immediately as a new base,
                         # not as a compounded base × decay value
```

Setting `last_success_at = now` on false positive is intentional: the clock restart separates the penalty (a 20 % haircut) from accumulated decay so the two effects don't compound into an over-punishment on the same event.

### 4.3 Confidence thresholds

The exponential curve produces a continuous `confidence ∈ [0, 1]`. Existing agents expect a discrete tier (HIGH/MEDIUM/LOW/ARCHIVED). Thresholds are fixed, not configurable in v1:

| Confidence `c` | Tier     | Behavior |
|---------------:|----------|----------|
| `c ≥ 0.75`     | HIGH     | Loaded at PREFLIGHT, weighted normally in PREEMPT injection. |
| `0.5 ≤ c < 0.75` | MEDIUM | Loaded at PREFLIGHT, weighted normally. |
| `0.3 ≤ c < 0.5`  | LOW    | Loaded at PREFLIGHT but ranked last in dedup tie-breaks. |
| `c < 0.3`        | ARCHIVED | Not loaded at PREFLIGHT. Moved to bottom of `forge-log.md`. |

An item re-promotes tiers naturally when `last_success_at` is updated or `base_confidence` is raised.

### 4.4 When decay is computed

Decay is computed **lazily** at two touchpoints:

1. **At PREFLIGHT**, when the orchestrator loads PREEMPT items from `forge-log.md` and `shared/learnings/*.md`. The loader calls `memory_decay.effective_confidence(item, now)` on each item and attaches the tier. This is read-only — it does not write decayed values back.
2. **At LEARN**, `fg-700-retrospective` writes back the authoritative `confidence` and tier to each item's record, together with any reinforcement (`last_success_at`) or penalty (`last_false_positive_at`, `base_confidence *= 0.8`) events generated by the current run. Archived items (new tier = ARCHIVED) are moved to the archive block of `forge-log.md`.

Between runs, records sit untouched — time elapses "for free" in storage. A single `now` stamp at each touchpoint produces a deterministic decay value.

### 4.5 Alternatives considered

**Alternative A — Linear decay** (`confidence(t) = max(0, base - k·Δt)`).
- Pros: trivial; intuitive; one multiplication.
- Cons: abrupt cut-off at `base / k`; no memory-theory grounding; indistinguishable from the counter model once `k` is pinned to a run cadence. Rejected.

**Alternative B — Power-law decay** (`confidence(t) = base × (1 + Δt/τ)^(-α)`).
- Pros: fatter tail (old-but-still-reinforced memories decay more slowly) — better matches long-term retention studies (Rubin & Wenzel, 1996).
- Cons: two parameters per category instead of one (`τ`, `α`), harder to reason about and tune; marginal gain over exponential at the timescales we care about (14–90 days); not standard in agent-memory systems surveyed. Rejected for v1. Can be swapped in later behind the `memory.decay.curve: power_law` config slot.

**Chosen — Ebbinghaus exponential.**
- One parameter per category (`half_life_days`).
- Aligns with Mem0 / Letta / MemGPT prior art.
- Composable with half-life variation per type, which directly addresses the audit finding (auto-discovered should decay faster than canonical).

### 4.6 State fields on a memory item record

Every memory item record (whether in `forge-log.md` frontmatter, `shared/learnings/*.md` frontmatter, or `.forge/memory/*.json`) gains:

| Field                      | Type       | Semantics |
|---------------------------|------------|-----------|
| `last_success_at`          | ISO 8601   | Timestamp of most recent reinforcement. Initialized by migrator to migration time. Reset to `now` on every hit and on every false positive (see §4.2). |
| `last_false_positive_at`   | ISO 8601 \| null | Timestamp of most recent confirmed false positive. Informational + used for analytics. |
| `base_confidence`          | float [0,1] | Current post-reinforcement / post-penalty base confidence. Default 0.75 on new items. |
| `type`                     | enum       | `auto-discovered` \| `cross-project` \| `canonical`. Derived from `source`/location if absent. |

The legacy fields `runs_since_last_hit`, `decay_multiplier`, and the `HIGH → MEDIUM` after-10-runs rule are removed from the canonical memory schema.

---

## 5. Components

| Component | Action | Notes |
|-----------|--------|-------|
| `shared/learnings/decay.md` | **New.** Canonical reference for the decay formula, half-lives, thresholds, reinforcement/penalty rules, and the lazy computation contract. Referenced from `agent-defaults.md` so every agent inherits the contract. |
| `hooks/_py/memory_decay.py` | **New.** Pure Python module (no deps beyond stdlib). Exports: `effective_confidence(item, now) -> float`, `tier(confidence) -> str`, `apply_success(item, now) -> item`, `apply_false_positive(item, now) -> item`, `migrate_item(item, now) -> item`, `HALF_LIFE_DAYS` constant dict, `THRESHOLDS` constant dict. Called from retrospective and PREFLIGHT loader. No I/O — caller supplies/saves the record. |
| `agents/fg-700-retrospective.md` | **Modify.** LEARN-stage logic updated: (a) call `memory_decay.apply_success` for each hit recorded in stage notes; (b) call `memory_decay.apply_false_positive` for each `PREEMPT_SKIPPED{reason:false_positive}`; (c) call `memory_decay.effective_confidence` + `tier` before writing the item back; (d) move items whose tier = ARCHIVED to the archive block. Remove references to `runs_since_last_hit` and `decay_multiplier`. |
| `shared/learnings/memory-discovery.md` | **Modify.** §Promotion and Decay rewritten to reference `decay.md` (single source of truth). Drop the "5 unused runs" and `decay_multiplier: 2` tables — replaced by `type: auto-discovered` → 14-day half-life. Keep the promotion logic (MEDIUM → HIGH after 3 successful applications). |
| `shared/learnings/rule-promotion.md` | **Modify.** §Decay Rules section: replace "5 inactive runs → demote" with "Rule's ACTIVE knowledge item's confidence drops below 0.3 tier threshold per `decay.md` → demote". Point at `decay.md`. |
| `shared/learnings/README.md` | **Modify.** §PREEMPT Lifecycle table replaced with a pointer to `decay.md`. The legacy counter-based table is struck through with a one-line "Superseded by Ebbinghaus decay (Phase 13, 2026-04-19)" note. |
| PREFLIGHT loader (lives inside `fg-100-orchestrator.md` PREEMPT-injection logic) | **Modify.** Calls `memory_decay.effective_confidence` + `tier` at load time. Does not write back. Archived items filtered out. |
| `.forge/memory/*.json` records | **Migrate on load.** On first PREFLIGHT after upgrade, every record missing `last_success_at` is passed through `memory_decay.migrate_item(item, now)` which stamps `last_success_at = now`, `last_false_positive_at = null`, `base_confidence = (HIGH ? 1.0 : MEDIUM ? 0.75 : LOW ? 0.5)` translated from the legacy tier field, and `type` derived per §4.1. Then written back. |
| Tests — `tests/unit/memory_decay_test.py` | **New.** Pure-Python unit tests for the decay function (formula, thresholds, reinforcement, penalty, migration). |
| Tests — `tests/eval/memory_decay_eval.sh` | **New.** Eval harness that constructs synthetic `.forge/memory/` fixtures with spread of ages and types, runs a dry LEARN pass, and asserts the resulting tiers match the expected formula to within floating-point tolerance (`abs(actual - expected) < 1e-6`). Runs in CI only. |
| `CLAUDE.md` | **Modify.** §Gotchas/Convergence & review — replace "PREEMPT decay: 10 unused → HIGH→MEDIUM→LOW→ARCHIVED. 1 false positive = 3 unused." with a one-line pointer to `shared/learnings/decay.md`. Bump version note to reflect Phase 13 change. |

---

## 6. Data / State / Config

### 6.1 `forge-config.md` schema additions

```yaml
memory:
  decay:
    curve: ebbinghaus        # ebbinghaus | linear | power_law (only ebbinghaus implemented in v1)
    half_life_days:
      auto_discovered: 14
      cross_project: 30
      canonical: 90
    base_confidence_default: 0.75
    thresholds:
      high: 0.75
      medium: 0.5
      low: 0.3
      # archived = below low
    reinforcement:
      success_bonus: 0.05    # additive, capped at 1.0
      false_positive_penalty: 0.20  # multiplicative: new_base = base * (1 - penalty)
```

Defaults shipped in `forge-config.md` at plugin level; project `forge.local.md` can override any leaf (but half-life and curve are documented as stable knobs — changing them changes every agent's decay behavior).

### 6.2 Memory item record schema (the canonical form after migration)

```json
{
  "id": "auto-forge-naming-003",
  "pattern": "services suffixed with `Service`",
  "type": "auto-discovered",
  "source": "auto-discovered",
  "base_confidence": 0.75,
  "last_success_at": "2026-04-17T09:12:44Z",
  "last_false_positive_at": null,
  "hit_count": 4,
  "discovered_run": "run-2026-04-11-0001",
  "domain": "naming",
  "evidence": { "files_matching": ["..."], "files_violating": [] }
}
```

For items stored as Markdown frontmatter (forge-log.md, shared/learnings/*.md), the same keys are encoded as YAML frontmatter — no format change, just additional keys. Retrospective rewrites the frontmatter atomically via the same routines it already uses.

### 6.3 `.forge/memory/` directory contract

`.forge/memory/` is the on-disk store for per-project memory records (one JSON file per item, or a single `items.jsonl` — whichever the existing retrospective writer uses; this phase doesn't restructure the directory). The directory survives `/forge-recover reset`, consistent with other learning-related state.

---

## 7. Compatibility

**Hard breaking — no backwards compatibility.**

- The legacy decay fields (`runs_since_last_hit`, `decay_multiplier`) are removed from the schema. Records still carrying them after migration are ignored and overwritten.
- The legacy decay rules in `README.md`, `memory-discovery.md`, `rule-promotion.md`, and `CLAUDE.md` are replaced outright.
- **Migration path** (one-time, idempotent): on the first PREFLIGHT run after upgrade, any memory record lacking `last_success_at` is passed through `memory_decay.migrate_item(item, now)`:
  - `last_success_at := now` (warm-start: every existing item effectively gets a "fresh" reinforcement at migration time — this prevents a mass-archive on day one)
  - `last_false_positive_at := null`
  - `base_confidence := 1.0` if legacy tier = HIGH, else 0.75 if MEDIUM, else 0.5 if LOW, else 0.3 if ARCHIVED
  - `type` derived per §4.1
  - legacy fields deleted
- Migrator runs exactly once per record (detect by presence of `last_success_at`). No rollback path. If the user wants a clean slate, they delete `.forge/memory/` and `.claude/forge-log.md` manually.
- Shared learnings shipped in the plugin (`shared/learnings/*.md`) are migrated as part of the PR that lands this phase — authors hand-stamp `last_success_at`, `base_confidence`, and `type` in their frontmatter. No runtime migration needed for plugin-shipped files.

---

## 8. Testing Strategy

**Unit tests — `tests/unit/memory_decay_test.py`** (pure Python, no Forge runtime):

1. `test_formula_at_zero_time_returns_base` — `effective_confidence(item, item.last_success_at) == item.base_confidence`.
2. `test_formula_at_one_half_life_is_half_base` — item with `type=auto-discovered`, `last_success_at = now - 14d` → `c ≈ base/2` (tolerance 1e-9).
3. `test_formula_at_two_half_lives_is_quarter_base` — same, at 28 days → `c ≈ base/4`.
4. `test_type_half_life_selection` — same Δt applied to three items of three types produces three distinct confidences matching their half-life.
5. `test_tier_boundaries` — confidences 0.749, 0.75, 0.499, 0.5, 0.299, 0.3 land in MEDIUM, HIGH, LOW, MEDIUM, ARCHIVED, LOW respectively.
6. `test_apply_success_resets_clock_and_adds_bonus` — `last_success_at` = passed `now`; `base_confidence` increased by 0.05; capped at 1.0.
7. `test_apply_false_positive_drops_and_resets` — `base_confidence` multiplied by 0.8; `last_success_at` = `now`; `last_false_positive_at` = `now`.
8. `test_migrate_legacy_high_item` — legacy record with `confidence: HIGH`, no `last_success_at` → post-migration has `base_confidence = 1.0`, `last_success_at = now`, `type` inferred, legacy fields removed.
9. `test_migrate_is_idempotent` — calling `migrate_item` twice produces the same output as calling once.
10. `test_type_inference` — explicit `type`, `source: auto-discovered`, `source: user-confirmed`, `shared/learnings/` path-only, and default-fallback all resolve correctly.

**Eval harness — `tests/eval/memory_decay_eval.sh`** (CI only, shell + Python):

- Builds a fixture `.forge/memory/` with ~30 synthetic items spanning (type × age) grid: `{auto-discovered, cross-project, canonical} × {fresh=0d, mid=half-life, stale=3×half-life}`.
- Runs a dry LEARN pass via `python3 hooks/_py/memory_decay.py --dry-run-recompute fixture/` (mode added behind `--dry-run-recompute` flag).
- Parses the output tiers and asserts: fresh items → HIGH; mid → MEDIUM; stale → ARCHIVED. False-positive path: inject a `PREEMPT_SKIPPED{reason:false_positive}` event and assert `base_confidence` drops by 20 % ± 1e-9.

**CI assertion (half-life math correctness):** the unit tests above encode the math; CI runs them on every PR touching `hooks/_py/memory_decay.py` or `shared/learnings/decay.md`.

No local test execution is expected; CI is authoritative per plugin policy.

---

## 9. Rollout

Single PR. Scope:

1. Land `hooks/_py/memory_decay.py` with its unit tests.
2. Land `shared/learnings/decay.md` as the canonical reference.
3. Rewrite the affected sections of `README.md`, `memory-discovery.md`, `rule-promotion.md`, `CLAUDE.md`, `fg-100-orchestrator.md` (PREFLIGHT loader), and `fg-700-retrospective.md` (LEARN writer).
4. Hand-stamp `last_success_at`, `base_confidence`, `type` into the frontmatter of every shipped `shared/learnings/*.md` item.
5. Land the eval harness and wire it into CI.

Migration runs automatically on the first PREFLIGHT after the PR merges in any consuming project. No opt-in flag.

Post-merge observation window: the retrospective logs a summary line per run — "decay: N items demoted, M items archived, K items reinforced" — so we can watch the first week and spot mis-tuned half-lives. If telemetry shows mass archiving (>20 % of HIGH items archived in the first week), revert via `memory.decay.half_life_days` override in `forge-config.md` until tuned.

---

## 10. Risks / Open Questions

1. **Half-life calibration** — 14 / 30 / 90 days are reasoned-not-measured defaults. If real pipelines run weekly on a given repo, 14 days = 2 runs, which may be too aggressive. Mitigation: the config knobs in §6.1 allow per-project override; telemetry counter from the rollout plan surfaces miscalibration.
2. **Warm-start gaming** — the migrator stamps every existing item with `last_success_at = now`, so day 1 looks artificially healthy. A truly stale rule that's been around but unused for a year decays from full strength rather than from archive. Acceptable for v1; the first real "unused" event (a run where its domain is active and it doesn't fire) doesn't reinforce, so within one half-life the stale rule naturally demotes.
3. **Interaction with `.forge/knowledge/` active knowledge lifecycle** — knowledge items have their own state machine (CANDIDATE/VALIDATED/ACTIVE/ARCHIVED) that is *not* being replaced. When an ACTIVE knowledge item is projected into PREEMPT form at PREFLIGHT (per README.md §Integration with PREEMPT), the projected PREEMPT item inherits `type: canonical` (90-day half-life) and is subject to Ebbinghaus decay *for the purpose of PREEMPT ranking only*. The underlying knowledge state machine is untouched. Open question: should the projected PREEMPT decay feed back into the knowledge item's effectiveness metrics? Deferred — no, keep layers decoupled in v1.
4. **Clock skew / time travel** — reliance on wall-clock `now` means a system with a wildly wrong clock (or a user who sets their clock forward to "age" rules) can skew decay. Mitigation: retrospective clamps `Δt_days` to `[0, 365]` before applying the formula, logs a warning when clamped.
5. **`base_confidence` ratchet** — the `+0.05` per success, capped at 1.0, means a popular rule eventually sits at `base = 1.0` and resists any single false-positive (which drops it to 0.8). Is that desirable? Yes for v1 — frequent successes are meaningful signal — but we should revisit if false-positive rates on canonical items exceed 5 % in telemetry.
6. **False-positive clock reset combined with penalty** — setting `last_success_at = now` on a false positive prevents over-punishment but also means a pattern that's currently firing wrong decays from a fresh clock. Open question: should false-positive instead leave the clock alone and let decay compound? Chosen behavior (reset) is simpler and matches Mem0's "recent signal is signal" stance; revisit if stale-confident patterns re-emerge.

---

## 11. Success Criteria

1. **Stale rules auto-archive.** A rule whose `last_success_at` is older than `3 × half_life_days` for its type ends the run in ARCHIVED tier (e.g. a canonical rule untouched for 270 days archives; an auto-discovered rule untouched for 42 days archives). Verifiable in the eval harness.
2. **False-positive rate on auto-discovered items drops.** Measured via `fg-700-retrospective`'s run-over-run telemetry (new counter: `auto_discovered_false_positive_rate`). Target: a ≥25 % relative reduction over five runs following migration in any project with ≥10 auto-discovered items. Acceptance criterion for the phase, measurable once telemetry has accumulated.
3. **No mass-archive at migration.** First PREFLIGHT after upgrade archives ≤5 % of previously-HIGH items (thanks to the warm-start stamp). Check in eval harness with a migrated fixture.
4. **Canonical items dominate long-term survival.** After 180 days of simulated continuous-but-sparse use (eval harness), canonical items retain `c ≥ 0.5` (still MEDIUM+), cross-project items sit near 0.25–0.35 (LOW/boundary), auto-discovered items without reinforcement are archived.
5. **Documentation is internally consistent.** No file references the old "10 unused runs" rule except the struck-through historical note in `README.md`. CI link-check passes.

---

## 12. References

- **W15 audit finding** — 2026-04-19 A+ audit (staleness vs irrelevance, counter-based decay weakness).
- **Mem0, *State of AI Agent Memory 2026***: https://mem0.ai/blog/state-of-ai-agent-memory-2026 — staleness as a distinct failure mode; Ebbinghaus curve as prior art in agent memory systems.
- **Ebbinghaus, H. (1885).** *Über das Gedächtnis. Untersuchungen zur experimentellen Psychologie.* Duncker & Humblot, Leipzig. — origin of the exponential forgetting curve.
- **Rubin, D. C., & Wenzel, A. E. (1996).** One hundred years of forgetting: A quantitative description of retention. *Psychological Review*, 103(4), 734–760. — power-law vs exponential comparison (informs §4.5 alternative B).
- **Forge internal docs** — `shared/learnings/README.md` §PREEMPT Lifecycle (superseded); `shared/learnings/memory-discovery.md` §Promotion and Decay (rewritten); `shared/learnings/rule-promotion.md` §Decay Rules (rewritten); `agents/fg-700-retrospective.md` (modified); `CLAUDE.md` §Gotchas (updated).
