# Review — Phase 13 Memory Decay (Ebbinghaus) Design Spec

**Spec:** `docs/superpowers/specs/2026-04-19-13-memory-decay-ebbinghaus-design.md`
**Reviewer date:** 2026-04-19
**Verdict:** **APPROVE — ship as-is (2 minor recommendations).**

---

## 1. Criterion-by-criterion check

| # | Criterion | Evidence | Pass? |
|--:|-----------|----------|------:|
| 1 | All 12 sections | §1 Goal, §2 Motivation, §3 Scope, §4 Architecture, §5 Components, §6 Data/State/Config, §7 Compatibility, §8 Testing Strategy, §9 Rollout, §10 Risks / Open Questions, §11 Success Criteria, §12 References — all present. | PASS |
| 2 | No placeholders | No `TBD`, `TODO`, `FIXME`, `<…>`, or "to be determined" strings anywhere in the spec. Every numeric (14/30/90 days, 0.75/0.5/0.3 thresholds, 0.05 bonus, 0.20 penalty, 1e-6 tolerance, ≥25 % reduction target) is concrete. | PASS |
| 3 | Formula exact `base × 2^(-Δt/half_life)` | §4.1 line 63: `confidence(t) = base_confidence × 2^(-Δt_days / half_life_days)`. Exact form. Units defined (`Δt_days = (now - last_success_at) / 86_400_000` ms). | PASS |
| 4 | Per-type half-lives quantified | §4.1 table: `auto-discovered = 14 days`, `cross-project = 30 days`, `canonical = 90 days`. Also duplicated in §6.1 YAML config defaults. Type-resolution fallback defined. | PASS |
| 5 | Threshold mapping HIGH/MEDIUM/LOW/ARCHIVED | §4.3 table: `c ≥ 0.75` HIGH, `0.5 ≤ c < 0.75` MEDIUM, `0.3 ≤ c < 0.5` LOW, `c < 0.3` ARCHIVED. Boundaries are half-open, consistent, and behavior per tier is spelled out (load / rank / filter at PREFLIGHT). | PASS |
| 6 | False-positive penalty + success boost numeric | §4.2: success → `base += 0.05` capped at 1.0 and `last_success_at = now`; false positive → `base *= 0.80` and `last_success_at = now` and `last_false_positive_at = now`. Numeric, deterministic, both referenced again in §6.1 config block. | PASS |
| 7 | Clock-skew handling — clamp `Δt` to `[0, 365]` | §10 Risk #4: "retrospective clamps `Δt_days` to `[0, 365]` before applying the formula, logs a warning when clamped." Exact clamp range matches the review criterion. | PASS |
| 8 | Migrator behavior explicit (warm start) | §2 last paragraph, §3 in-scope, §4.6 (migration field semantics), §5 (`.forge/memory/*.json` row — "migrate on load"), §7 Compatibility (full migration algorithm incl. legacy-tier → `base_confidence` mapping: HIGH→1.0, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3), §10 Risk #2 calls out warm-start tradeoff. Idempotency asserted (§7 and test 9). | PASS |
| 9 | Lazy-read / authoritative-write model | §4.4 is dedicated to this. Explicit two-touchpoint contract: (1) PREFLIGHT loader calls `effective_confidence(item, now)` read-only; (2) LEARN stage (`fg-700`) writes authoritative `confidence` + tier + reinforcement/penalty events back. "Between runs, records sit untouched — time elapses 'for free' in storage." | PASS |
| 10 | 2 alternatives rejected with rationale | §4.5: Alternative A (linear decay) — rejected for abrupt cut-off, no memory-theory grounding, equivalent-to-counter-once-pinned. Alternative B (power-law, Rubin & Wenzel 1996) — rejected for extra parameter cost with marginal gain at 14–90 d timescales, but left behind `memory.decay.curve: power_law` config slot for future swap. Both rationales specific; chosen option explicitly justified against both. | PASS |

**All 10 required criteria pass.** The spec is complete, self-consistent, and ships with a non-trivial testing plan (10 unit tests + grid-based eval harness).

---

## 2. What the spec does well

1. **Single source of truth convention.** `shared/learnings/decay.md` is introduced as the canonical reference; every other doc (`README.md`, `memory-discovery.md`, `rule-promotion.md`, `CLAUDE.md`, `fg-100-orchestrator.md`, `fg-700-retrospective.md`) is updated to point at it rather than duplicate. This is exactly the convention `shared/` already follows for other contracts (`scoring.md`, `state-schema.md`, `agent-defaults.md`) and prevents drift.
2. **Decoupling from the `.forge/knowledge/` state machine.** §3 Out-of-scope and §10 Risk #3 are explicit: the CANDIDATE/VALIDATED/ACTIVE/ARCHIVED knowledge lifecycle is *not* replaced, and ACTIVE knowledge items are projected into PREEMPT with `type: canonical` (90-day HL) only for PREEMPT ranking. Keeping layers decoupled in v1 is the right call and the spec names the open question it is deferring.
3. **Testing strategy is formula-verifiable, not vibes-based.** The 10-test unit suite pins the math to `1e-9` tolerance at 0, 1, and 2 half-lives and tests tier boundaries at the exact cutoffs (0.749 vs 0.750, 0.499 vs 0.500, 0.299 vs 0.300). The eval harness uses a `type × age` grid, which catches half-life-swap regressions. This will hold up under refactor.
4. **Rollout plan has an observability hook.** §9 introduces a per-run summary line ("decay: N demoted, M archived, K reinforced") plus a concrete revert criterion (>20 % of HIGH items archived in week one → revert via config). That's a real feedback loop, not "we'll see how it goes".
5. **Warm-start tradeoff is named, not hidden.** §10 Risk #2 explicitly acknowledges the migration stamps every item with a fresh `last_success_at`, meaning truly-stale rules will survive day one and only decay on the first "domain-active-but-unused" run. This is the correct behavior (avoids mass-archive) and the spec reasons about it rather than papering over it.

---

## 3. Issues / recommendations (top 3, all non-blocking)

### Issue 1 — `base_confidence` ratchet to 1.0 creates an asymmetric ceiling (minor)

**Where:** §4.2 success path and §10 Risk #5.

**Observation:** `+0.05` additive per success capped at 1.0 means a popular rule accumulates to `base = 1.0` after 5+ hits and then a single false positive drops it only to 0.80 — still HIGH-tier. The spec flags this as Risk #5 and accepts it for v1 ("frequent successes are meaningful signal"), but the false-positive penalty is now effectively dampened for popular rules (20 % of 1.0 = 0.20 drop, still HIGH) vs freshly-promoted rules (20 % of 0.75 = 0.15 drop, MEDIUM). A pattern that turns subtly wrong after being historically correct — the exact "stale-confident memory" failure mode the spec quotes in §2 as motivation — is the case where the 1.0 ceiling hurts most.

**Recommendation (optional, v1):** consider capping `base_confidence` at 0.95 instead of 1.0, or making a second consecutive false-positive apply a compounded penalty (`base *= 0.80` *twice* within N runs → `base *= 0.64`). Either narrows the gap between accumulated confidence and one-shot punishment. The spec already leaves this revisit as Risk #5, so this is a nit — the config knobs in §6.1 make it a one-line change post-rollout if telemetry supports it.

### Issue 2 — `last_false_positive_at` is defined but unused (minor)

**Where:** §4.6 field table line 140 ("Informational + used for analytics") and §5 item record JSON §6.2.

**Observation:** The field is stored on every record and updated on every false positive, but no code path described in §4, §5, or §8 reads it to gate behavior. It is "informational" and may feed future analytics. That's fine, but a field that's always written and never read has a habit of silently diverging from reality (migrations forget it, tests don't exercise it, readers assume a semantic that writers don't honor). Since nothing in v1 depends on it, two options:

- **Option A (lighter):** remove the field from v1 and add it when analytics need it — YAGNI.
- **Option B (keep field, add a reader):** have `fg-700-retrospective`'s post-run summary (§9 "decay: N demoted...") include a "last FP in last 7 days: K items" line, so the field gets exercised and surfaces in telemetry immediately.

**Recommendation:** Option B. It costs one log line, validates the field is being written correctly from day one, and gives the `base_confidence` ratchet discussion in Issue 1 real data.

### Issue 3 — Config schema allows override but docstring on reinforcement knobs is thin (suggestion)

**Where:** §6.1 config block.

**Observation:** The YAML lists `success_bonus: 0.05` and `false_positive_penalty: 0.20` as tunable, and §6.1 prose warns that `half_life_days` and `curve` are "documented as stable knobs — changing them changes every agent's decay behavior." The same warning should apply to the reinforcement knobs — they interact non-linearly with the thresholds (if a user sets `success_bonus: 0.2` and `false_positive_penalty: 0.05`, they invert the decay model) and can silently produce a system where false positives never demote. Right now §6.1 is silent on their tuning boundaries.

**Recommendation:** Add one line to the prose after the YAML: "Reinforcement knobs (`success_bonus`, `false_positive_penalty`) are invariants of the decay model — change only with matching threshold tuning and telemetry validation. A `success_bonus` > `false_positive_penalty` inverts the stale-memory protection." Cheap change, preempts a foot-gun.

---

## 4. Verdict

**APPROVE.** All 10 review criteria pass. The spec is implementation-ready:

- Formula, thresholds, numeric tuning, migration path, and rollback are all concrete and testable.
- Alternatives are rejected with cited rationale (not just dismissed).
- The `decay.md` single-source-of-truth pattern is consistent with existing Forge conventions in `shared/`.
- Testing strategy encodes the math at floating-point tolerance and ships a grid-based eval harness — both will survive refactor.
- Rollout plan includes an observability hook and a concrete revert criterion.

The three issues above are all non-blocking quality nits. Issue 2 (add a reader for `last_false_positive_at`) is the most useful to address before merge because it costs almost nothing and immediately validates that a write-only field is being written correctly. Issues 1 and 3 can land in a follow-up once real telemetry exists.

**Ready for implementation.**

---

## 5. Relevant files

- Spec under review: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-13-memory-decay-ebbinghaus-design.md`
- Existing memory docs that will be rewritten:
  - `/Users/denissajnar/IdeaProjects/forge/shared/learnings/README.md` (§PREEMPT Lifecycle)
  - `/Users/denissajnar/IdeaProjects/forge/shared/learnings/memory-discovery.md` (§Promotion and Decay)
  - `/Users/denissajnar/IdeaProjects/forge/shared/learnings/rule-promotion.md` (§Decay Rules)
- New artifacts planned:
  - `/Users/denissajnar/IdeaProjects/forge/shared/learnings/decay.md`
  - `/Users/denissajnar/IdeaProjects/forge/hooks/_py/memory_decay.py`
  - `/Users/denissajnar/IdeaProjects/forge/tests/unit/memory_decay_test.py`
  - `/Users/denissajnar/IdeaProjects/forge/tests/eval/memory_decay_eval.sh`
- Affected agents: `/Users/denissajnar/IdeaProjects/forge/agents/fg-100-orchestrator.md` (PREFLIGHT loader), `/Users/denissajnar/IdeaProjects/forge/agents/fg-700-retrospective.md` (LEARN writer)
- Top-level doc to update: `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md` (§Gotchas → Convergence & review bullet on PREEMPT decay)
