# Phase 07 — Agent Layer Refactor

**Status:** DESIGN
**Priority:** P1
**Author:** forge maintainers
**Date:** 2026-04-19
**Phase:** 07 of the A+ roadmap

---

## 1. Goal

Bring the 42-agent population into contract compliance (Tier-4 frontmatter, `trigger:` docs on conditional agents), split two oversized reviewers along ownership seams, and close four coverage gaps (i18n, migration verification, observability bootstrap, resilience testing) plus a license-compliance split-off — taking the registry to 47 agents with no latent scoring categories.

## 2. Motivation

Audit waves **W7** (UI-frontmatter consistency) and **W8** (coverage gaps) surfaced three classes of defect:

- **Spec drift:** 12 Tier-4 agents ship a `ui:` block despite `shared/agent-role-hierarchy.md` calling for explicit omission. `tests/contract/ui-frontmatter-consistency.bats` currently accepts the violation because the spec it enforces is ambiguous. With the block present, future tiering changes are silently breakable.
- **Dark scoring categories:** `I18N-*`, `MIGRATION-*`, `RESILIENCE-*` are registered in `shared/checks/category-registry.json` and referenced by F16/F24/(implicit-F-resilience) but **no agent emits them**. Findings get attributed to `fg-410-code-reviewer` by accident of affinity, which muddies retro analytics and blocks learnings-promotion.
- **Undocumented dispatch conditions:** `fg-320`, `fg-515`, `fg-610`, `fg-650`, `fg-620` are conditionally dispatched but their gating lives only in orchestrator prose. A machine-readable `trigger:` field is the prerequisite for Phase 08's dispatch-graph generator.
- **Reviewer sprawl:** `fg-413` (534 lines) and `fg-417` (333 lines) each own two distinct domains. Their size drives reviewer token cost disproportionately and makes quality-gate parallelism less effective.

Phase 07 fixes all three classes in a single PR before Phase 08 starts auto-generating dispatch diagrams against the registry.

## 3. Scope

### 3.1 In scope

Verified against `/Users/denissajnar/IdeaProjects/forge/agents/` and `shared/agent-role-hierarchy.md`:

1. **Remove `ui:` frontmatter** from the 12 Tier-4 agents:
   `fg-101-worktree-manager`, `fg-102-conflict-resolver`, `fg-205-planning-critic`, `fg-410-code-reviewer`, `fg-411-security-reviewer`, `fg-412-architecture-reviewer`, `fg-413-frontend-reviewer`, `fg-416-performance-reviewer`, `fg-417-dependency-reviewer`, `fg-418-docs-consistency-reviewer`, `fg-419-infra-deploy-reviewer`, `fg-510-mutation-analyzer`.
2. **Add `trigger:` frontmatter** to conditionally-dispatched agents:
   `fg-320-frontend-polisher` (frontend files present + `frontend_polish.enabled`), `fg-515-property-test-generator` (`property_testing.enabled`), `fg-610-infra-deploy-verifier` (k8s/IaC detected), `fg-620-deploy-verifier` (deployment strategy != `none`), `fg-650-preview-validator` (preview URL available). Also retrofit the two new conditional agents introduced below.
3. **Split `fg-417-dependency-reviewer.md`** into:
   - `fg-417-dependency-reviewer.md` — CVE/outdated/unmaintained/version-compat only (`DEP-CVE-*`, `DEP-OUTDATED-*`, `DEP-UNMAINTAINED`, `DEP-DEPRECATED`, `DEP-CONFLICT-*`, `DEP-LANG-*`, `DEP-API-*`).
   - `fg-414-license-reviewer.md` *(new)* — SPDX + license compliance (`DEP-LICENSE-*`, new `LICENSE-POLICY-*` categories).
4. **Slim `fg-413-frontend-reviewer.md`** from 534 → ~380 lines by removing Part D (performance, ~60 lines) and merging it into `fg-416-performance-reviewer.md` under a new "Frontend Performance" subsection. `fg-413` keeps Part A (conventions), Part B (design), Part C (a11y static + dynamic), Part E (cross-browser visual).
5. **Add 5 new agents** (see §5.3 for full frontmatter sketches):
   - `fg-155-i18n-validator` — PREFLIGHT Tier-3
   - `fg-505-migration-verifier` — VERIFY Tier-3 *(conditional: migration mode)*
   - `fg-143-observability-bootstrap` — PREFLIGHT Tier-3 *(conditional: `observability.enabled`)*
   - `fg-555-resilience-tester` — VERIFY Tier-3 *(conditional: `agents.resilience_testing.enabled`)*
   - `fg-414-license-reviewer` — REVIEW Tier-4 *(from the fg-417 split)*
6. **Documentation updates:**
   - `shared/agent-colors.md` — add 5 new agents with collision-free colors.
   - `shared/agents.md` (Phase 06 output) — regenerate registry table.
   - `shared/agent-role-hierarchy.md` — update tier tables, dispatch graph.
   - `CLAUDE.md` — "42 agents" → "47 agents" (four sites).
   - `shared/checks/category-registry.json` — add new categories, re-wire affinity.
7. **New learnings files** (one per new domain): `shared/learnings/i18n.md`, `shared/learnings/migration.md`, `shared/learnings/resilience.md`, `shared/learnings/observability.md`, `shared/learnings/license-compliance.md`.

### 3.2 Out of scope

- **Merging `fg-205-planning-critic` into `fg-210-validator`:** rejected. The critic's adversarial independence is load-bearing — it writes findings `fg-210` *consumes*. Combining them collapses the two-writer invariant and removes the ability for the validator to weigh critic findings alongside its own 7-perspective output. Re-raising this requires a separate phase with an explicit proposal.
- Hook rewrites, check-engine L0/L1 changes, MCP-server changes — none needed for this refactor.
- `fg-400-quality-gate` dispatch batching rules — untouched except for the one new reviewer (`fg-414-license-reviewer`) and the absorbed frontend-perf section inside `fg-416`.

## 4. Architecture

### 4.1 Agent count math

```
Current population          : 42 agents
+ fg-155-i18n-validator     : +1
+ fg-505-migration-verifier : +1
+ fg-143-observability-boot : +1
+ fg-555-resilience-tester  : +1
+ fg-414-license-reviewer   : +1  (split from fg-417; fg-417 stays)
────────────────────────────────
Post-Phase 07 population    : 47 agents
```

No deletions; `fg-417` is slimmed, not replaced.

### 4.2 Updated tier distribution

| Tier | Current | Δ | Post-07 |
|---|---|---|---|
| Tier 1 (tasks+ask+plan) | 6 | 0 | 6 |
| Tier 2 (tasks+ask) | 9 | 0 | 9 |
| Tier 3 (tasks) | 16 | +4 (fg-143, fg-155, fg-505, fg-555) | 20 |
| Tier 4 (silent) | 12 (12 violating) | +1 (fg-414) | 13 (0 violating) |
| **Total** | **43** *(listed)* ¹ | +5 | **47** |

¹ Hierarchy doc currently lists 43 entries; the 42-agent count excludes `fg-000` (there is none — the extra row is a double-listed `fg-205` placeholder to be removed when regenerating the table).

### 4.3 Dispatch graph changes

```
fg-100-orchestrator
  ├── PREFLIGHT
  │   ├── fg-101-worktree-manager
  │   ├── fg-130-docs-discoverer
  │   ├── fg-135-wiki-generator
  │   ├── fg-140-deprecation-refresh
  │   ├── fg-143-observability-bootstrap   ← NEW (conditional)
  │   ├── fg-150-test-bootstrapper
  │   ├── fg-155-i18n-validator            ← NEW
  │   └── fg-160-migration-planner         (migration mode)
  ├── VERIFYING
  │   ├── fg-505-build-verifier
  │   ├── fg-505-migration-verifier        ← NEW (migration mode, conditional)
  │   ├── fg-500-test-gate
  │   └── fg-555-resilience-tester         ← NEW (conditional)
  └── REVIEWING
      └── fg-400-quality-gate
          ├── … (existing 8) …
          └── fg-414-license-reviewer       ← NEW (always, cheap)
```

Note on `fg-505` ID collision: `fg-505-build-verifier` already exists. The migration verifier takes a new slot — **re-numbered to `fg-506-migration-verifier`** to avoid collision. (Updated from the prompt's initial `fg-505-migration-verifier`; documented here because it is the minimum-surprise fix.)

### 4.4 Alternatives considered

**Alt A — "Keep the big reviewers, just add missing agents."**
Rejected. The 534-line `fg-413` already exceeds the soft 400-line reviewer cap derived from token-budget studies in `shared/output-compression.md`. Each reviewer invocation is billed as a subagent system prompt; every line is amortized across every REVIEW stage across every run. Slimming `fg-413` pays back in hours, not months. The `fg-417` split is even more justified: CVE scanning and license compliance have *disjoint* tool chains (`npm audit` vs. `license-checker`) and disjoint severity calibration (CVE CVSS vs. SPDX policy). Keeping them fused forces one agent to load both mental models every run.

**Alt B — "Merge all four coverage gaps into fg-410-code-reviewer as new dimensions."**
Rejected. `fg-410` is already the code-quality catch-all and would balloon past 600 lines. Worse, three of the four gaps (`fg-143`, `fg-155`, `fg-506`) run in *PREFLIGHT/VERIFY* — different stages than `fg-410` (REVIEW). Merging them would require stage-aware mode switching inside one agent's body, which breaks the "one agent, one job" principle in `shared/agent-philosophy.md`.

**Alt C (chosen) — Dedicated agents per gap, split where ownership seams exist.**
Keeps agent responsibilities crisp, retros by-agent analytics stay meaningful, and the new agents compose cleanly with the existing tier/color/dispatch contracts.

## 5. Components

### 5.1 Agent files touched (23 total)

**UI-frontmatter removal (12):**
`agents/fg-101-worktree-manager.md`, `agents/fg-102-conflict-resolver.md`, `agents/fg-205-planning-critic.md`, `agents/fg-410-code-reviewer.md`, `agents/fg-411-security-reviewer.md`, `agents/fg-412-architecture-reviewer.md`, `agents/fg-413-frontend-reviewer.md`, `agents/fg-416-performance-reviewer.md`, `agents/fg-417-dependency-reviewer.md`, `agents/fg-418-docs-consistency-reviewer.md`, `agents/fg-419-infra-deploy-reviewer.md`, `agents/fg-510-mutation-analyzer.md`.

**Trigger-doc additions (5):**
`agents/fg-320-frontend-polisher.md`, `agents/fg-515-property-test-generator.md`, `agents/fg-610-infra-deploy-verifier.md`, `agents/fg-620-deploy-verifier.md`, `agents/fg-650-preview-validator.md`.

**Split (1 → 2):**
`agents/fg-417-dependency-reviewer.md` (slimmed to ~180 lines), new `agents/fg-414-license-reviewer.md`.

**Slim (1):**
`agents/fg-413-frontend-reviewer.md` (534 → ~380 lines; Part D moved to `agents/fg-416-performance-reviewer.md` which gains ~60 lines).

**New agents (4, in addition to fg-414):**
`agents/fg-155-i18n-validator.md`, `agents/fg-506-migration-verifier.md`, `agents/fg-143-observability-bootstrap.md`, `agents/fg-555-resilience-tester.md`.

### 5.2 Shared/doc files touched

| File | Change |
|---|---|
| `shared/agent-role-hierarchy.md` | Tier tables + dispatch graph; remove duplicate row |
| `shared/agent-colors.md` | 5 new rows; confirm cluster uniqueness |
| `shared/agents.md` | Regenerate (Phase 06 script) |
| `shared/agent-registry.md` | Add 5 entries |
| `shared/reviewer-boundaries.md` | Update fg-413/fg-416/fg-417/fg-414 ownership |
| `shared/checks/category-registry.json` | New categories, re-wire affinity |
| `CLAUDE.md` | "42 agents" → "47 agents" (4 sites) |
| `shared/learnings/i18n.md` | NEW |
| `shared/learnings/migration.md` | NEW |
| `shared/learnings/resilience.md` | NEW |
| `shared/learnings/observability.md` | NEW |
| `shared/learnings/license-compliance.md` | NEW |

### 5.3 New-agent frontmatter sketches

```yaml
# agents/fg-155-i18n-validator.md
---
name: fg-155-i18n-validator
description: i18n validator. Hardcoded strings, RTL/LTR bleed, locale format drift. PREFLIGHT.
model: inherit
color: crimson         # PREFLIGHT cluster has cyan/navy/teal/olive free-slot; crimson unused
tools: [Read, Glob, Grep, Bash]
trigger: always        # runs every PREFLIGHT (cheap regex pass)
ui:
  tasks: true
  ask: false
  plan_mode: false
---
```

```yaml
# agents/fg-506-migration-verifier.md
---
name: fg-506-migration-verifier
description: Migration verifier. Rollback script, idempotency, data-loss risk. VERIFY (migration mode only).
model: inherit
color: coral           # Verify/Test cluster has yellow/brown/cyan/pink used; coral free
tools: [Read, Glob, Grep, Bash]
trigger: mode == "migration"
ui:
  tasks: true
  ask: false
  plan_mode: false
---
```

```yaml
# agents/fg-143-observability-bootstrap.md
---
name: fg-143-observability-bootstrap
description: Observability bootstrapper. OTel config, metrics endpoints, log structure. PREFLIGHT.
model: inherit
color: magenta         # PREFLIGHT cluster: magenta unused
tools: [Read, Write, Edit, Glob, Grep, Bash]
trigger: observability.enabled == true
ui:
  tasks: true
  ask: false
  plan_mode: false
---
```

```yaml
# agents/fg-555-resilience-tester.md
---
name: fg-555-resilience-tester
description: Resilience tester. Circuit breakers, timeouts, retry policy, chaos smoke. VERIFY.
model: inherit
color: navy            # Verify/Test cluster: navy unused
tools: [Read, Glob, Grep, Bash]
trigger: agents.resilience_testing.enabled == true
ui:
  tasks: true
  ask: false
  plan_mode: false
---
```

```yaml
# agents/fg-414-license-reviewer.md
---
name: fg-414-license-reviewer
description: License compliance reviewer. SPDX audit, copyleft in proprietary, license-change detection.
model: inherit
color: lime            # Review cluster: lime unused (green used by fg-300 but different cluster)
tools: [Read, Bash, Glob, Grep]
trigger: always
# NO ui: block — Tier 4 silent
---
```

### 5.4 Color-collision audit (within clusters)

Verified against §2 cluster table in `shared/agent-colors.md`:

- **PREFLIGHT cluster** current colors: cyan, navy, teal, olive. Adding crimson (fg-155) + magenta (fg-143) — both unused in cluster, both unused globally in this cluster. OK.
- **Verify/Test cluster** current colors: yellow, brown, cyan, pink. Adding coral (fg-506) + navy (fg-555) — both unused in cluster. OK.
- **Review cluster** current colors: red, cyan, crimson, navy, teal, amber, purple, white, olive. Adding lime (fg-414) — unused in cluster. OK.

All five new agents fit without extending the palette.

## 6. Data / State / Config

### 6.1 New scoring categories (add to `shared/checks/category-registry.json`)

```jsonc
{
  "I18N-HARDCODED":  { "desc": "Hardcoded user-facing string", "agents": ["fg-155-i18n-validator"], "priority": 5,
                        "affinity": ["fg-155-i18n-validator", "fg-413-frontend-reviewer"] },
  "I18N-RTL":        { "desc": "LTR/RTL-unsafe CSS",          "agents": ["fg-155-i18n-validator"], "priority": 5 },
  "I18N-LOCALE":     { "desc": "Locale-unaware date/num",     "agents": ["fg-155-i18n-validator"], "priority": 5 },

  "MIGRATION-ROLLBACK-MISSING": { "severity_cap": "CRITICAL", "agents": ["fg-506-migration-verifier"] },
  "MIGRATION-NOT-IDEMPOTENT":   { "severity_cap": "CRITICAL", "agents": ["fg-506-migration-verifier"] },
  "MIGRATION-DATA-LOSS":        { "severity_cap": "CRITICAL", "agents": ["fg-506-migration-verifier"] },

  "RESILIENCE-CIRCUIT-MISSING":  { "severity_cap": "WARNING", "agents": ["fg-555-resilience-tester"] },
  "RESILIENCE-TIMEOUT-UNBOUNDED":{ "severity_cap": "CRITICAL","agents": ["fg-555-resilience-tester"] },
  "RESILIENCE-RETRY-UNBOUNDED":  { "severity_cap": "WARNING", "agents": ["fg-555-resilience-tester"] },

  "LICENSE-POLICY-VIOLATION":    { "severity_cap": "CRITICAL","agents": ["fg-414-license-reviewer"] },
  "LICENSE-UNKNOWN":             { "severity_cap": "WARNING", "agents": ["fg-414-license-reviewer"] },
  "LICENSE-CHANGE":              { "severity_cap": "WARNING", "agents": ["fg-414-license-reviewer"] },

  "OBS-MISSING":                 { "severity_cap": "WARNING", "agents": ["fg-143-observability-bootstrap"] },
  "OBS-TRACE-INCOMPLETE":        { "severity_cap": "INFO",    "agents": ["fg-143-observability-bootstrap"] }
}
```

Existing `I18N-*` affinity (currently pointing at `fg-410`/`fg-413`) updated to prefer `fg-155` first.

### 6.2 New config keys (in `forge-config-template.md` for all frameworks)

```yaml
agents:
  resilience_testing:
    enabled: false        # opt-in; chaos/load has cost + flake risk
    max_duration_s: 120
  i18n_validator:
    enabled: true         # cheap; on by default
  observability_bootstrap:
    enabled: false        # requires OTel collector config
  migration_verifier:
    enabled: true         # auto-skips outside migration mode
  license_reviewer:
    policy_file: .forge/license-policy.json   # optional; defaults to allow-list of permissive SPDX IDs
```

### 6.3 State schema — no changes

Per-agent findings already flow through `state.findings[]`; new categories slot in via the existing `category` string field. No schema-version bump.

## 7. Compatibility

**Breaking:**
- **Downstream consumers of `fg-417` findings:** anything parsing for `DEP-LICENSE-*` must now read `fg-414-license-reviewer` output instead. Retrospective, `/forge-insights`, and run-history queries need one-line grep updates (documented in rollout).
- **Any external agent extending forge frontmatter:** the `trigger:` field is now load-bearing for conditional dispatch. External agents without `trigger:` default to `trigger: always`, which preserves current behavior — but the dispatch-graph generator (Phase 08) will flag the omission.
- **`fg-400-quality-gate`** gains one reviewer; total review cost per run rises by ~1 reviewer invocation. Budget impact <2% in representative runs (license check is a single `license-checker` call).

**Non-breaking:**
- UI-frontmatter removal on Tier-4 agents: no behavior change (Tier-4 already ignored `ui:` at runtime; `tests/contract/ui-frontmatter-consistency.bats` is updated to *require* omission).
- New PREFLIGHT/VERIFY agents are conditional; default-off modes (`observability_bootstrap`, `resilience_testing`) keep the default pipeline unchanged.

Per project policy: **no backwards-compatibility shims**. Consumers update at the same commit.

## 8. Testing Strategy

**No local test execution.** All verification happens in CI after push.

1. **Expand `tests/contract/ui-frontmatter-consistency.bats`:** change "Tier 4 MAY omit ui:" to "Tier 4 MUST omit ui:"; assert the 13 Tier-4 agents (12 existing + fg-414) have no `ui:` key.
2. **New `tests/contract/agent-registry.bats`:**
   - Asserts 47 agents exist in `agents/` matching `fg-NNN-*.md`.
   - Asserts each conditional agent has a `trigger:` key with a non-empty string.
   - Asserts every `agents:` entry in `category-registry.json` points at an agent file that exists.
3. **New `tests/contract/agent-colors.bats`:** asserts cluster-scoped color uniqueness holds after the 5 additions.
4. **Eval harness (Phase 01) scenarios** — add three fixtures:
   - `evals/scenarios/i18n-hardcoded.yml`: JSX with `"Hello world"` string; expect `fg-155` emits `I18N-HARDCODED`.
   - `evals/scenarios/migration-no-rollback.yml`: SQL migration without down-script; expect `fg-506` emits `MIGRATION-ROLLBACK-MISSING` CRITICAL.
   - `evals/scenarios/resilience-unbounded-retry.yml`: Kotlin coroutine `while(true){ retry() }`; expect `fg-555` emits `RESILIENCE-RETRY-UNBOUNDED`.
5. **`tests/structural/agent-frontmatter.bats`:** parse every agent's frontmatter as YAML; assert required keys (`name`, `description`, `tools`) plus `ui:` iff tier != 4, `trigger:` iff in conditional list.
6. **Regenerate `shared/agents.md`** (Phase 06 script) and commit as part of the PR so CI sees the canonical table.

## 9. Rollout

**Single PR, single commit per logical group** (so bisect stays sharp):

1. Commit 1: ui-frontmatter removal (12 files, mechanical).
2. Commit 2: add `trigger:` to conditional agents (5 files).
3. Commit 3: fg-413 slim + fg-416 gain the moved section.
4. Commit 4: fg-417 split into fg-417 + fg-414.
5. Commit 5: 4 new agents (fg-155, fg-143, fg-506, fg-555) with frontmatter, body, learnings files.
6. Commit 6: docs regen (`agent-role-hierarchy.md`, `agent-colors.md`, `agents.md`, `agent-registry.md`, `reviewer-boundaries.md`, `CLAUDE.md`).
7. Commit 7: `category-registry.json` update + config templates.
8. Commit 8: tests (contract + eval fixtures).

Merge order into `master`: squash to a single merge commit tagged `phase07-agent-refactor`. No feature flag — the changes are structural and always-on (with per-agent config gates for the opt-in agents).

## 10. Risks / Open Questions

**R1 — `fg-506` ID collision with existing `fg-505`.** Resolved by renumbering to `fg-506`. Needs the role-hierarchy doc and all cross-references updated in lockstep.

**R2 — License-policy file default.** If a project has no `.forge/license-policy.json`, `fg-414` must fail open (WARNING at most) rather than block shipping on every project. Need a baked-in default allow-list (MIT, Apache-2.0, BSD-*, ISC, Unlicense, CC0-1.0). **Open question:** do we also allow LGPL-2.1+ by default for library projects, or leave that to the project?

**R3 — Resilience tester flakiness.** Chaos-style probes can flake in CI. Mitigation: default-off; when on, findings capped at WARNING unless `RESILIENCE-TIMEOUT-UNBOUNDED` (static-grep, not runtime).

**R4 — Token cost drift.** Five new agents + one new reviewer adds ~10-15% system-prompt tokens at steady state. Partially offset by the fg-413 slim (~60 lines × every REVIEW). Net expectation: +5-8% tokens, tracked in Phase 10 cost regression eval.

**R5 — i18n false positives.** Test strings, log messages, and dev-only UIs will trip `I18N-HARDCODED`. Mitigation: `fg-155` honors a `.forge/i18n-ignore` glob file and excludes `*.test.*`, `*.spec.*`, `__tests__/`, `*.stories.*` by default.

**R6 — Observability bootstrap is write-capable** (Edit + Write tools). It's the only new PREFLIGHT agent that mutates the repo. Must run inside `.forge/worktree`, not the user's tree — same guarantee as `fg-300-implementer`.

## 11. Success Criteria

- `tests/contract/ui-frontmatter-consistency.bats` passes with the strict "Tier 4 MUST omit ui:" assertion — **0 violations** across the registry.
- `ls agents/fg-*.md | wc -l` = 47.
- Every conditionally-dispatched agent (`fg-320`, `fg-515`, `fg-610`, `fg-620`, `fg-650`, `fg-506`, `fg-555`, `fg-143`) has a `trigger:` frontmatter key documented in the agent's file.
- `fg-413-frontend-reviewer.md` ≤ 400 lines. `fg-417-dependency-reviewer.md` ≤ 200 lines.
- Every scoring category listed in `shared/checks/category-registry.json` has at least one agent in its `agents:` array that exists on disk, AND that agent's `.md` body references the category code.
- `shared/agent-colors.md` cluster-uniqueness invariant holds (verified by `agent-colors.bats`).
- Eval harness: all three new scenarios (`i18n-hardcoded`, `migration-no-rollback`, `resilience-unbounded-retry`) pass with the expected finding category emitted by the expected agent.
- `CLAUDE.md` mentions "47 agents" (not 42) in all four occurrences.

## 12. References

- `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md` — current 42-agent roster, UI-tier definitions.
- `/Users/denissajnar/IdeaProjects/forge/shared/agent-role-hierarchy.md` — Tier tables, dispatch graph.
- `/Users/denissajnar/IdeaProjects/forge/shared/agent-colors.md` — palette, cluster rules.
- `/Users/denissajnar/IdeaProjects/forge/shared/agent-philosophy.md` — "one agent, one job" principle.
- `/Users/denissajnar/IdeaProjects/forge/shared/reviewer-boundaries.md` — ownership seams (basis for fg-417 split and fg-413 slim).
- `/Users/denissajnar/IdeaProjects/forge/shared/checks/category-registry.json` — 87-category registry to extend.
- `/Users/denissajnar/IdeaProjects/forge/agents/fg-410-code-reviewer.md` — canonical Tier-4 sample (after ui-fix).
- `/Users/denissajnar/IdeaProjects/forge/agents/fg-413-frontend-reviewer.md` — slim target.
- `/Users/denissajnar/IdeaProjects/forge/agents/fg-417-dependency-reviewer.md` — split target.
- `/Users/denissajnar/IdeaProjects/forge/tests/contract/ui-frontmatter-consistency.bats` — contract test to tighten.
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-01-evaluation-harness-design.md` — Phase 01 eval harness (host for new scenarios).
- W7 + W8 audit artifacts (inline in this spec's Motivation).
