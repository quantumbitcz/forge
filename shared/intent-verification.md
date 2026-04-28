# Intent Verification & Implementer Voting (Phase 7)

Phase 7 closes the "plan misread intent" gap with two coordinated gates.

## F35 — Intent Verification Gate (Stage 5 VERIFY → Stage 9 SHIP)

### Why

`fg-300-implementer` writes both the RED test and the GREEN code. If the
planner misread the requirement, the test encodes the misreading and GREEN
satisfies it — all downstream gates (critic, reviewers, build/test/lint) see
green. Reviewers check test↔code fidelity; none of them replay the original
user requirement against the running system.

### Architecture

```
Stage 5 VERIFY Phase A passes
  │
  ▼
orchestrator.build_intent_verifier_context(state)   ◄── Layer-1 enforcement
  │                                                      (allow-list keys only)
  ▼
.forge/dispatch-contexts/fg-540-<ts>.json           ◄── ephemeral; grep target
  │                                                      for AC-702 test
  ▼
Agent(fg-540-intent-verifier, filtered_context)     ◄── Layer-2 tripwire inside
  │                                                      agent (defense-in-depth)
  ▼
per-AC probes via hooks/_py/intent_probe.py         ◄── sandbox, forbidden-host
  │                                                      denylist
  ▼
.forge/runs/<run_id>/findings/fg-540.jsonl          ◄── finding schema v2
  │                                                      (nullable file/line)
  ▼
state.intent_verification_results[]
  │
  ▼
fg-590-pre-ship-verifier reads results
  │
  ▼
SHIP iff 0 CRITICAL INTENT-MISSED and verified_pct >= strict_ac_required_pct
```

### Two-layer context isolation

**Layer 1 — Orchestrator allow-list** (in `build_intent_verifier_context`).
This is the enforcement: any key outside ALLOWED_KEYS raises
`IntentContextLeak`. The contract test greps the persisted brief for
forbidden substrings (AC-702).

**Layer 2 — Agent tripwire** (in fg-540 system prompt, "Context Exclusion
Contract" clause). Defense-in-depth. If the agent sees a forbidden key,
it emits `INTENT-CONTRACT-VIOLATION` CRITICAL for all ACs and halts.
This is model-compliance behavior — a jailbroken model could ignore it.
Its job is narrowing the blast radius of a Layer-1 regression, not
defending against adversarial context injection.

## F36 — Confidence-Gated Implementer Voting (Stage 4 IMPLEMENT)

### Why

Single-sample LLM implementations have nontrivial stochastic failure rate,
especially on LOW-confidence or high-risk tasks. Full N=3 voting everywhere
(F33) was rejected on cost grounds. F36 threads the needle: N=2 on the
narrow slice where a single sample is most likely wrong.

### Voting Gate

See `shared/agent-communication.md` § risk_tags Contract for the full
trigger list. Summary:

1. `impl_voting.enabled == true`
2. Budget remaining >= 30 % (computed from Phase 6 fields
   `state.cost.remaining_usd / state.cost.ceiling_usd`)
3. Any of: LOW confidence, `task.risk_tags` intersects
   `trigger_on_risk_tags`, or recent-regression history for touched files.

### Dispatch topology

```
task enters Stage 4
  │
  ▼
should_vote(task, state, config) ──► false ──► dispatch_single(task) (today's path)
  │
  ▼ true
fg-101 create <task> sample_1 at .forge/votes/<task>/sample_1
fg-101 create <task> sample_2 at .forge/votes/<task>/sample_2
  │                                                            (both from parent HEAD)
  ▼
Agent(fg-300, vote_sample, sub_a) ║ Agent(fg-300, vote_sample, sub_b)  ◄── parallel
                                                                           15-min per-sample timeout
  ▼
Agent(fg-302-diff-judge, sub_a, sub_b, touched_files)
  │
  ├── SAME      ──► pick smallest-line-count sample → cherry-pick onto main
  │                    → cleanup both sub-worktrees
  │
  └── DIVERGES  ──► Agent(fg-300, vote_tiebreak, divergence_notes)
                       │
                       ├── reconciles     ──► cherry-pick tiebreak onto main
                       │                       → cleanup
                       │
                       └── still diverges ──► autonomous: smallest-diff →
                                              IMPL-VOTE-UNRESOLVED WARNING
                                              interactive: AskUserQuestion 3-way diff
```

### Diff Judge — structural AST

The diff is **syntactic** (post-`ast.parse` for Python; CST hash for
tree-sitter languages), NOT semantic — operand reorderings, import
reorderings, and added/removed docstrings register as `DIVERGES` by design,
and the tiebreak reconciles them.

Python: stdlib `ast` with canonicalized dump + SHA256. Supported
tree-sitter languages (per `tree-sitter-language-pack` 1.6.3+ (2026-04)):
TS, JS, Kotlin, Go, Rust, Java, C, C++, Ruby, PHP, Swift. Fall back to
whitespace+comment-normalized text diff for any language where the grammar
wheel is absent OR the parser fails on the actual sample. Degraded mode
emits `IMPL-VOTE-DEGRADED` INFO and reduces judge confidence to MEDIUM (one
degraded file) or LOW (all degraded). Under degraded mode, behaviorally-
equivalent rewrites (variable renames, control-flow reshapes) register as
DIVERGES and trigger spurious tiebreaks — acceptable because (a) it's a
minority of touched files and (b) the tiebreak reconciles.

### Cost-skip threshold (30 %) is deliberately earlier than Phase 6 (20 %)

Voting doubles a task's cost. Hitting the Phase 6 implementer throttle
(20 %) with a vote already in flight would either abort the vote mid-air
or push the run over-budget. The 10-point buffer preserves main-impl
budget for when the vote finishes.

## Cross-references

- `shared/agent-communication.md` § risk_tags Contract — producer/consumer
- `shared/confidence-scoring.md` — `effective_confidence` used by the gate
- `shared/living-specifications.md` — AC registry consumed by fg-540
- `shared/observability.md` — `forge.intent.*` and `forge.impl_vote.*` spans
- `agents/fg-540-intent-verifier.md` — verifier system prompt
- `agents/fg-302-diff-judge.md` — judge system prompt
- `agents/fg-590-pre-ship-verifier.md` § Step 6 — SHIP gate clauses
