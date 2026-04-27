# Forge Mega-Spec: Skill Consolidation + Superpowers Pattern Parity

**Status:** Draft (brainstorming output, expanded to mega scope)
**Date:** 2026-04-27
**Author:** Denis Šajnar (with Claude)
**Supersedes:** Earlier "Phase 9 (Pattern Parity)" plan that was to be a separate spec — absorbed here per user request: "I want to have it all and working and maybe even better."

## Summary

This spec does two coordinated things in one ship:

1. **Skill surface consolidation** — replace 29 user-facing skills with three (`/forge`, `/forge-ask`, `/forge-admin`), absorb `/forge-init` into auto-bootstrap, make every feature-mode invocation start with BRAINSTORMING. Hybrid grammar inside `/forge` (explicit verbs win, plain text falls through to the intent classifier). No backwards compatibility — atomic deletion of 28 skill directories, atomic creation of two (with one rewritten in place).

2. **Superpowers pattern parity** — port the proven patterns from the superpowers plugin into the corresponding forge agents, so forge does not require superpowers as a runtime dependency but matches its quality. Five agent uplifts (planner, reviewer pipeline, post-run, bug investigator, PR builder), a polish pass on five already-strong agents (TDD, verification, parallel dispatch, plan execution, worktrees), and four "beyond superpowers" enhancements that exploit forge's multi-agent architecture (cross-reviewer consistency, brainstorm transcript reuse, hypothesis branching, structured PR-finishing dialog).

The two halves share an implementation train because both touch the entry path (`/forge` invocation, BRAINSTORMING stage, `fg-010-shaper`), but ship in granular commits (~25 atomic commits) so each piece can be reverted or paused independently.

## Goals

### Skill consolidation

1. Reduce skill-surface complexity from 29 directories to 3 (~90 % reduction).
2. Eliminate the explicit init step: `/forge "<request>"` on a fresh project must work.
3. Always brainstorm features before planning, with a single config opt-out (`brainstorm.enabled: false`) for emergency disable.
4. Preserve all existing capability. No agent is deleted; only the skill-level wrappers around them.
5. Preserve all current parallelization (sprint, task, reviewer levels).
6. Match the brainstorming behavior to the superpowers pattern (one question at a time, propose 2-3 approaches, sectioned design with approval gates) without taking a runtime dependency on the superpowers plugin.

### Pattern parity

7. **Planner uplift** — `fg-200-planner` produces plans matching `superpowers:writing-plans` shape (TDD ordering, RED/GREEN/REFACTOR scaffolds per task, canonical implementer-prompt and spec-reviewer-prompt templates embedded in the plan output, explicit risk markers).
8. **Reviewer pipeline uplift** — every reviewer (`fg-410..fg-419`) emits a structured report matching `superpowers:requesting-code-review` (Strengths / Critical / Important / Minor / Recommendations / Assessment-with-verdict) **alongside** existing scoring findings.
9. **Post-run / receiving-feedback uplift** — `fg-710-post-run` adopts `superpowers:receiving-code-review` discipline: classify each piece of PR feedback, generate a defense response for disputable items before accepting, log defenses to PR thread.
10. **Debugging uplift** — `fg-020-bug-investigator` adopts `superpowers:systematic-debugging` discipline: hypothesis register with falsifiability tests, evidence collection before fix, hard veto on fix-without-root-cause.
11. **Branch finishing uplift** — `fg-600-pr-builder` adopts `superpowers:finishing-a-development-branch` shape: present user with merge/PR/cleanup options via `AskUserQuestion`, run cleanup checklist.
12. **Strong-agent polish** — verify and tighten parity for already-strong agents: `fg-300-implementer` (TDD), `fg-590-pre-ship-verifier` (verification-before-completion), `fg-100-orchestrator` (subagent-driven-development + dispatching-parallel-agents + executing-plans), `fg-101-worktree-manager` (using-git-worktrees).

### Beyond superpowers

13. **Cross-reviewer consistency voting** — exploit forge's nine reviewers running in parallel: when ≥3 reviewers flag the same finding (same dedup key), promote confidence to HIGH automatically, even if individual reviewers rated it MEDIUM. Reduces false positives that single-fresh-context review can't catch.
14. **Brainstorm transcript mining** — `fg-010-shaper` writes its Q&A transcript to `.forge/brainstorm-transcripts/<run_id>.jsonl`. Future shaper runs query the transcript store via the existing F29 run-history-store FTS5 index for similar features and pre-load likely questions, cutting average shaper rounds from ~5 to ~3 on familiar feature types.
15. **Hypothesis branching for bug investigation** — `fg-020-bug-investigator` forms up to three competing hypotheses in parallel (sub-agent dispatch, Tier-3), evidence-tests each, and prunes by Bayesian update. Faster convergence on hard bugs than linear hypothesis-test-narrow.
16. **Structured PR-finishing dialog** — `fg-600-pr-builder` uses `AskUserQuestion` rather than free-text prompts for the merge/PR/cleanup decision. Better UI affordance, autonomous-mode default applied without prompting.

## Non-goals

- **Optional aliases for old skill names.** Per personal-tool stance, deletion is atomic, no shims.
- **`fg-300-implementer` core rewrite.** Already strong; only polish ACs are in scope.
- **`fg-100-orchestrator` core rewrite.** Already strong; polish only — adding the BRAINSTORMING stage is the only structural change.
- **Replacing scoring with prose verdicts.** Reviewer parity adds prose alongside scoring; scoring stays authoritative.
- **EXPLORE parallelization by aspect.** Out of scope — separate Phase 10 if ever pursued.
- **`fg-101-worktree-manager` rewrite.** Already strong; polish only.

## Architecture

### §1 — Three skills

#### `/forge` — write surface

```yaml
name: forge
description: "[writes] Build, fix, deploy, review, or modify code in this project. Universal entry for the forge pipeline. Auto-bootstraps on first run; brainstorms before planning when given a feature description. Use for any productive action: implementing features, fixing bugs, reviewing branches, deploying, committing, running migrations."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
ui: { tasks: true, ask: true, plan_mode: true }
```

**Hybrid grammar:**

| Form | Behavior |
|---|---|
| `/forge run "<feature description>"` | Explicit feature pipeline (BRAINSTORM → ... → SHIP). |
| `/forge fix "<bug description or ticket ID>"` | Bugfix pipeline. Skips BRAINSTORM. |
| `/forge sprint [--parallel] "<feat>"...` or `/forge sprint <linear-cycle-id>` | Sprint orchestration. |
| `/forge review [--full] [--scope=changed\|all] [--fix]` | Review pipeline. |
| `/forge verify [--build\|--config\|--all]` | Build/lint/test or config validation. |
| `/forge deploy <env>` | Deployment. |
| `/forge commit` | Generate conventional commit from staged changes. |
| `/forge migrate "<from> to <to>"` | Migration pipeline. |
| `/forge bootstrap [<stack>]` | Greenfield project scaffold. |
| `/forge docs [<scope>]` | Docs generation. |
| `/forge audit` | Security audit. |
| `/forge "<free-text>"` | Falls through to `shared/intent-classification.md`. Default → `run` mode. |

**Flags (apply to relevant subcommands):**
- `--dry-run` — preview only; PREFLIGHT → VALIDATE; no worktree, no commits.
- `--autonomous` — no `AskUserQuestion` calls; auto-decisions logged with `[AUTO]` prefix; honors `autonomous: true` in `forge.local.md`.
- `--from=<stage>` — resume from a specific pipeline stage.
- `--spec <path>` — start from an existing spec; for `run`, skips BRAINSTORM if spec is well-formed.
- `--parallel` — only valid for `sprint` (deprecated alias for explicit `sprint`).
- `--background` — enqueue for background execution; output to `.forge/alerts.json`.

**Subcommand fallback rules:**
- Bare `/forge` (no args) prints usage and exits 0.
- `/forge --help` prints subcommand list and flag matrix.
- `/forge <unknown-verb> <args>` falls through to NL classifier with the full string. (Avoids the "did you mean" UX wart.)
- `/forge "fix the login bug"` (no explicit verb) classifies as bugfix via existing intent classifier.

**Argument and flag positioning:**
- Multi-word arguments may be quoted or unquoted. Quoting is recommended: `/forge run "add CSV export"` is unambiguous; `/forge run add CSV export` works but blurs into the NL fallback path.
- Flags must appear before the free-text argument: `/forge run --dry-run "add CSV export"`. Flags after the argument are an error — fail fast with usage.
- For `sprint` with a Linear cycle ID, the format is `/forge sprint <id>` where `<id>` matches the Linear API identifier shape. Exact regex deferred to plan-stage (depends on Linear MCP configuration); for this spec, the dispatcher accepts any non-empty string and lets the downstream Linear MCP call validate.

#### `/forge-ask` — read-only surface

```yaml
name: forge-ask
description: "[read-only] Query forge state, codebase knowledge, run history, or analytics. Never mutates project state. Use to check pipeline status, search wiki/graph for code answers, view past runs, see analytics, or get an onboarding tour."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep', 'Agent']
ui: { tasks: false, ask: false, plan_mode: false }
```

**Subcommand grammar (no NL fallback):**

| Form | Behavior |
|---|---|
| `/forge-ask "<question>"` | Default action. Codebase Q&A via wiki + graph + explore cache + docs index. |
| `/forge-ask status` | Current pipeline state. |
| `/forge-ask history [--limit=N] [--filter=<expr>]` | Past runs from `.forge/run-history.db`. |
| `/forge-ask insights [--scope=<run\|cycle\|all>]` | Quality, cost, convergence trends. |
| `/forge-ask profile [<run-id>]` | Per-stage timing and cost breakdown. |
| `/forge-ask tour` | 5-stop guided introduction. |

**Removed from this skill (deleted, not absorbed):** `/forge-help` was already deleted in Phase 2. `/forge-tour` becomes `/forge-ask tour` (single-line subcommand, not a top-level skill).

#### `/forge-admin` — state management surface

```yaml
name: forge-admin
description: "[writes] Manage forge state and configuration: recovery, abort, config edits, session handoff, automations, playbooks, output compression, knowledge graph maintenance. Use to recover from broken pipeline state, edit settings, manage long-lived state."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
ui: { tasks: true, ask: true, plan_mode: false }
```

**Subcommand grammar (two-level dispatch where existing skills had sub-subcommands):**

| Form | Behavior |
|---|---|
| `/forge-admin recover diagnose\|repair\|reset\|resume\|rollback` | State diagnostics and repair. |
| `/forge-admin abort` | Graceful stop of active run. |
| `/forge-admin config [wizard\|<key=val>]` | Interactive config editor. `wizard` runs the multi-question flow lifted from `/forge-init`. |
| `/forge-admin handoff [list\|show\|resume\|search\|<text>]` | Session handoff (default action with text arg = write). |
| `/forge-admin automation [list\|add\|remove\|test]` | Event-driven trigger management. |
| `/forge-admin playbooks [list\|run <id>\|create\|analyze]` | Playbook management. |
| `/forge-admin compress [agents\|output\|status\|help]` | Token-cost compression controls. |
| `/forge-admin graph init\|status\|query <cypher>\|rebuild\|debug` | Knowledge-graph operations. |
| `/forge-admin refine [<playbook-id>]` | Apply playbook refinement proposals. |

### §2 — Auto-bootstrap

**Trigger condition:** `/forge` invoked with `.claude/forge.local.md` absent.

The runtime directory `.forge/` is **not** a trigger. Clearing `.forge/` (e.g. via `/forge-admin recover reset`) must not re-trigger bootstrap. Config file is the contract; runtime state is the cache.

**Detection logic:** Reuse the existing detection in `fg-050-project-bootstrapper` and `shared/check-environment.sh`. Lift the detection branch of `skills/forge-init/SKILL.md` into a callable helper `shared/bootstrap-detect.py` so both auto-bootstrap and `/forge bootstrap` invoke the same code path. No new detection code is written; the existing logic is moved.

**Interaction shape — one consolidated AskUserQuestion:**

```
I detected: <stack-summary>.
  language: Kotlin 2.0.21
  framework: Spring Boot 3.4
  testing: JUnit 5
  build: Gradle 8.10

Bootstrap with these defaults?

  [proceed]      — write forge.local.md and continue with your request
  [open wizard]  — full multi-question setup
  [cancel]       — stop, do nothing
```

Default option: `[proceed]`. After bootstrap, the user's original request continues without re-prompting.

**Autonomous mode behavior:**
- With `autonomous: true` in any config or `--autonomous` flag, **skip the prompt entirely**.
- Detect, write `forge.local.md`, log `[AUTO] bootstrapped with detected defaults: <stack>` to `forge-log.md`.
- Proceed to the user's request.

**Failure modes:**
- **Detection ambiguous** (no recognizable build tool, mixed stacks at root, multiple package managers without a clear primary): abort with "couldn't auto-bootstrap; run `/forge-admin config wizard`". No silent half-init.
- **Write fails** (permissions, disk full): abort the run; do not proceed with the user's original request. Print error and exit non-zero.
- **`forge.local.md` is present but malformed:** treat as configured but broken. Do **not** auto-bootstrap (config exists). Surface a hard error pointing to `/forge-admin config` or `/forge verify --config`. (`forge verify --config` is the existing pre-flight validation skill; bootstrap is for "no config", not "broken config".)

**Effect on `/forge bootstrap`:** Stays as an explicit subcommand for greenfield project creation (currently `/forge-bootstrap`). Auto-bootstrap is the *implicit* path for already-coded projects; `/forge bootstrap <stack>` is the *explicit* path for empty directories. They share `shared/bootstrap-detect.py` but call different downstream agents (`fg-050-project-bootstrapper` for explicit greenfield; only the detect-and-write portion for auto-bootstrap).

### §3 — Brainstorm-first feature flow

#### New pseudo-stage: BRAINSTORM

The pipeline state machine gains one stage that precedes EXPLORE:

```
old:  PREFLIGHT → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → ...
new:  PREFLIGHT → BRAINSTORMING → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → ...
```

**Modes that skip BRAINSTORMING:**

| Trigger | Reason |
|---|---|
| `/forge fix ...` or `bugfix:` prefix | `fg-020-bug-investigator` is the bug-mode equivalent of brainstorming. |
| `/forge migrate ...` or `migrate:` prefix | `fg-160-migration-planner` plays this role for migrations. |
| `/forge bootstrap ...` or `bootstrap:` prefix | `fg-050-project-bootstrapper` plays the role for greenfield. |
| `--from=<stage>` resuming past BRAINSTORMING | Idempotent resume. |
| `--spec <path>` with a well-formed spec | Spec is treated as already-brainstormed. Spec well-formedness check: presence of all of (objective, scope, acceptance criteria); absence triggers an explicit "spec is incomplete; run BRAINSTORM" prompt unless `--autonomous`. |

#### `fg-010-shaper` rewrite

The agent's prompt is rewritten to adopt the superpowers brainstorming pattern, owned in-tree (no superpowers runtime dependency). Concretely, the agent:

1. **Explores project context** — reads `CLAUDE.md`, the most recent N commits (default N=20), graph for related modules. Caches results in `.forge/brainstorm-cache.json` to avoid re-exploration on resume.
2. **Asks clarifying questions one at a time** — multiple-choice when possible (uses `AskUserQuestion`). Stops asking when it can articulate purpose, constraints, success criteria.
3. **Proposes 2-3 approaches with tradeoffs** — explicit recommendation among them, reasoning included.
4. **Presents design in sections with approval gates** — architecture, components, data flow, error handling, testing. Each section gets its own `AskUserQuestion` ("looks right?").
5. **Writes spec** to `docs/superpowers/specs/YYYY-MM-DD-<slug>-design.md` (path configurable via `forge-config.md`'s `brainstorm.spec_dir`). Commits the spec.
6. **Self-review pass** — placeholder scan, internal consistency, scope check, ambiguity check. Fixes inline.
7. **Hands off to user** — `AskUserQuestion`: "Spec written. Approve to proceed to planning?"
8. **Transitions to `fg-200-planner`** with the spec path in `state.brainstorm.spec_path`.

The threshold logic (`<50 words missing 3+ of actors/entities/surface/criteria`) is **removed**. Always-on for feature mode is the new default.

#### Autonomous-mode degradation

When `autonomous: true` or `--autonomous`, `fg-010-shaper` runs a degraded one-shot:
- No `AskUserQuestion`. No `EnterPlanMode`.
- Reads input verbatim as the spec content.
- Auto-extracts ACs using a new helper `shared/ac-extractor.py` with explicit input/output contract:
  - **Input:** raw text string.
  - **Output:** `{objective: str, acceptance_criteria: list[str], confidence: "high"|"medium"|"low"}`.
  - **Implementation:** regex pass that matches (a) lines starting with `Given/When/Then`, (b) numbered list items (`^\s*\d+[.)]`), (c) bullets prefixed with imperative verbs from a known list (must, should, will, ensure, validate, return, expose, accept, reject). Returns `confidence: low` when fewer than two distinct AC matches are found, `medium` for 2-4, `high` for 5+.
  - This is **not** the intent classifier. It's a separate, single-purpose extractor; the intent classifier remains responsible for run/fix/sprint/etc. routing only.
- Writes a minimal spec to the same path: header + objective + extracted ACs + a frontmatter line `autonomous: true` + a body note `**Note:** spec auto-generated from raw input under `--autonomous` mode; extractor confidence: <level>`.
- Commits the spec.
- Logs `[AUTO] brainstorm skipped — input treated as spec (extractor confidence: <level>)`.
- Proceeds to EXPLORING. (Downstream stages, especially `fg-210-validator`, see the confidence level and may flag low-confidence specs as REVISE — but that's their existing responsibility, not this spec's.)

This preserves the BRAINSTORMING stage in the state machine for telemetry consistency while honoring the autonomous never-blocks invariant.

#### Resume semantics

If the pipeline is interrupted during BRAINSTORMING:
- **Interactive resume** with a spec already written (`state.brainstorm.spec_path` exists and the file exists) → `fg-010-shaper` reads the spec and asks "Resume from spec? Or restart brainstorming?".
- **Interactive resume** with no spec yet → restart BRAINSTORMING from scratch (questions cache in `.forge/brainstorm-cache.json` is honored; previously-asked questions are not re-asked).
- **Autonomous resume** (any case) → if a spec exists, proceed to EXPLORING with that spec; if no spec, regenerate the autonomous one-shot spec from the original input (re-read from `state.brainstorm.original_input`) and proceed. No prompts.

### §4 — Planner uplift (`fg-200-planner`)

**Pattern source:** `superpowers:writing-plans`.

**Current shape:** `fg-200-planner` produces a structured plan with stories, tasks, ACs, parallel groups, risk assessment per task, and a Challenge Brief. Validator (`fg-210`) rejects plans missing the Challenge Brief.

**Gap vs. superpowers pattern:**
- No per-task TDD scaffold (the "write test for X" → "implement X" task pair).
- Implementer dispatch prompts are improvised by `fg-100-orchestrator` rather than templated.
- Spec-compliance reviewer prompts are similarly improvised.
- No explicit "reviewer prompts attached to plan" section.

**Uplift:** rewrite `agents/fg-200-planner.md` to produce a plan structured as:

```
## Plan: <feature-name>

### Phase 1: <phase-name>

#### Task 1.1: Write test for <component>
**Type:** test (RED)
**File:** <test-path>
**Risk:** low|medium|high
**Implementer prompt:** [embed canonical implementer-prompt.md template]
**Spec-reviewer prompt:** [embed canonical spec-reviewer-prompt.md template]
**ACs covered:** AC-XXX-NNN, AC-XXX-NNN

#### Task 1.2: Implement <component> to pass test
**Type:** implementation (GREEN)
**File:** <impl-path>
**Risk:** ...
**Depends on:** Task 1.1
...

#### Task 1.3: Refactor <component>
**Type:** refactor (REFACTOR)
...
```

Templates `implementer-prompt.md` and `spec-reviewer-prompt.md` live at `shared/prompts/` (lifted from the canonical superpowers shapes — content is in-tree, no runtime dependency). The planner injects these per task with placeholder substitution (`{TASK_DESCRIPTION}`, `{ACS}`, `{FILE_PATHS}`).

**Plan validation:** `fg-210-validator` is updated to also enforce: every implementation task has a preceding test task; every task has an implementer prompt; every test task has a spec-reviewer prompt.

**Autonomous mode:** unchanged — planner already runs without prompts. The new templates are mechanical so they apply to autonomous output too.

### §5 — Reviewer pipeline uplift (`fg-400-quality-gate` + `fg-410..fg-419`)

**Pattern source:** `superpowers:requesting-code-review`.

**Current shape:** quality gate dispatches reviewers in batches; each reviewer emits findings JSON (file:line, category, severity). Score computed per `shared/scoring.md`. No prose summary, no explicit verdict per reviewer.

**Gap vs. superpowers pattern:** the canonical reviewer template has Strengths / Critical / Important / Minor / Recommendations / Assessment-with-verdict. forge has only the structured findings. A user looking at a reviewer's report sees a list of issues without context — no acknowledged strengths, no verdict, no recommendations beyond the issues themselves.

**Uplift:** every reviewer emits **two** outputs per dispatch:

1. **Findings JSON** (existing; feeds scoring engine and dedup) — unchanged contract.
2. **Prose report** (new) at `.forge/runs/<run_id>/reports/<reviewer>.md` matching the structured shape. Contents:
   - `## Strengths` — bullet list of what the reviewer found well-done.
   - `## Issues` — same dedup keys as findings JSON, prose-formatted, grouped by Critical / Important / Minor.
   - `## Recommendations` — strategic improvements not tied to specific findings.
   - `## Assessment` — `**Ready to merge:** Yes | No | With fixes`. `**Reasoning:** <1-2 sentences>`.

The prose report and findings JSON share dedup keys so the merge between them is deterministic. The orchestrator surfaces the prose to the user in `/forge review` output; scoring continues to consume only JSON.

**Cross-reviewer consistency voting (beyond superpowers, goal 13):** `fg-400-quality-gate` adds a post-deduplication pass:
- For each unique dedup key, count how many reviewers flagged it.
- If ≥3 reviewers flag the same key, promote confidence to HIGH (1.0 multiplier) regardless of individual reviewer ratings.
- Logged as `consistency_promoted: true` on the finding so analytics can track impact.
- Config: `quality_gate.consistency_promotion.threshold` (default 3, range 2-9), `quality_gate.consistency_promotion.enabled` (default true).

### §6 — Post-run / receiving-feedback uplift (`fg-710-post-run`)

**Pattern source:** `superpowers:receiving-code-review`.

**Current shape:** `fg-710-post-run` watches for PR rejection events, classifies the reason (design, implementation, test, doc), and routes the pipeline back to the relevant stage. Counters: `feedback_loop_count` (escalates at 2).

**Gap vs. superpowers pattern:** the receiving-code-review skill mandates a per-comment decision: actionable, wrong (push back), or preference (acknowledge). forge currently treats all feedback as actionable.

**Uplift:** new step in `fg-710` workflow, between "classify" and "route":

1. For each piece of feedback, run a fresh-context defense check via Tier-3 sub-agent dispatch:
   - Input: the feedback text, the changed code, the test suite, recent commits.
   - Output: `{verdict: "actionable" | "wrong" | "preference", reasoning: str, evidence: str}`.
2. If `verdict: wrong`, generate a defense response (`reasoning + evidence`) and post to the PR conversation thread via the GitHub MCP. Mark the feedback as "addressed: defended" in `.forge/runs/<run_id>/feedback-decisions.jsonl`.
3. If `verdict: preference`, post an acknowledgment without making code changes. Mark as "addressed: acknowledged".
4. If `verdict: actionable`, route to the relevant stage as today.

**`feedback_loop_count` semantics updated:** only "actionable" feedback increments the counter. "Defended" and "acknowledged" feedback does not — preventing the counter from escalating on a string of disputable comments.

**Config:** `post_run.defense_enabled` (default true), `post_run.defense_min_evidence` (default true — require a code/test reference in the defense response).

**Autonomous mode:** disabled (no MCP push without confirmation). Autonomous defaults to "actionable" for all feedback when MCP write is not available.

### §7 — Debugging uplift (`fg-020-bug-investigator`)

**Pattern source:** `superpowers:systematic-debugging`.

**Current shape:** `fg-020-bug-investigator` reproduces the bug (max 3 attempts), then proceeds to plan a fix. Validation by 4 perspectives. Patterns logged to `.forge/forge-log.md`.

**Gap vs. superpowers pattern:** systematic-debugging mandates: hypothesis register, evidence collection, falsifiability, hard veto on fix-without-root-cause. forge's investigator has reproduction but no explicit hypothesis-tracking; it can pattern-match a fix without articulating which cause it confirms.

**Uplift:** add a hypothesis-tracking step:

1. After reproduction, generate `state.bug.hypotheses[]` — up to 3 competing hypotheses about the root cause. Each entry: `{id, statement, falsifiability_test, evidence_required, status: "untested"}`.
2. **Hypothesis branching (beyond superpowers, goal 15):** if config `bug.hypothesis_branching.enabled` (default true), dispatch up to 3 sub-investigators in parallel — each tests one hypothesis. Sub-investigators use Tier-3 model (cheap), output `{hypothesis_id, evidence: list[str], passes_test: bool, confidence: "high"|"medium"|"low"}`.
3. **Bayesian pruning:** for each tested hypothesis, update probability via Bayes rule (priors uniform; likelihoods derived from confidence). Drop hypotheses below 0.10 posterior.
4. **Fix gate:** the planner (`fg-200`) refuses to plan a fix until at least one hypothesis has `passes_test: true` and posterior ≥ 0.50. If all hypotheses fail, escalate to user with the hypothesis register attached.

**Falsifiability test format:** each hypothesis must include a concrete check, e.g. "if you set `X=null`, the bug should occur" or "the stack trace should show frame `Y`". The check is run by the sub-investigator before declaring `passes_test`.

**State schema:** `state.bug = {hypotheses: list, branching_used: bool, fix_gate_passed: bool, ...}`.

**Autonomous mode:** runs all hypothesis branching without user prompts. If fix gate fails, log `[AUTO] bug investigation inconclusive — aborting fix attempt` and exit non-zero (no silent half-fix).

### §8 — Branch finishing uplift (`fg-600-pr-builder`)

**Pattern source:** `superpowers:finishing-a-development-branch`.

**Current shape:** `fg-600-pr-builder` creates a feature branch, stages commits grouped by logical layer, opens a PR with quality gate results. No user dialog about merge strategy or cleanup.

**Gap vs. superpowers pattern:** finishing-a-development-branch asks the user to decide how to integrate the work (merge, PR, cleanup). forge's PR-builder just builds the PR.

**Uplift:** new step before PR creation — `AskUserQuestion`-driven dialog (beyond superpowers UI affordance, goal 16):

```
Pipeline ready to ship. Choose how to finish:

  [open-pr]       — create pull request, target = main (default)
  [open-pr-draft] — create draft PR, mark as not ready for review
  [direct-push]   — push to main directly (no PR; only available if user has
                    push permissions and policy allows; rare)
  [stash]         — keep work in worktree, no PR (manual finish later)
  [abandon]       — close worktree, abandon branch (with confirmation prompt)
```

Default: `[open-pr]`. Autonomous mode: respects `pr_builder.default_strategy` config, default `open-pr`.

**Cleanup checklist** (runs after the chosen strategy completes):
- Delete the worktree (`fg-101-worktree-manager`).
- Update `.forge/run-history.db` with strategy outcome.
- If linked to a Linear/GitHub issue, post a status update.
- If a feature flag was added, log a TODO for removal (existing F23 behavior).
- Suggest a `/schedule` follow-up for any deferred cleanup (existing schedule skill — kept).

**Config:** `pr_builder.default_strategy: open-pr | open-pr-draft | direct-push | stash`, `pr_builder.cleanup_checklist_enabled: true`.

### §9 — Strong-agent polish

These agents already match their superpowers counterparts well. Polish ACs verify the match and tighten edge cases.

#### §9.1 — `fg-300-implementer` (TDD)

Match against `superpowers:test-driven-development`:
- Verify test-first ordering (RED before GREEN) is enforced — already done by the new planner output (§4); polish AC is on the implementer side.
- Add explicit "if test passes immediately without implementation change, fail loudly" check (test-driven-development rule: "test must fail first").

#### §9.2 — `fg-590-pre-ship-verifier` (verification-before-completion)

Match against `superpowers:verification-before-completion`:
- Already runs fresh build+test+lint+review. Polish: add explicit "evidence file" output (`.forge/evidence.json`) — already done by Phase 1.
- Polish AC: assert PR builder refuses without `verdict: SHIP` (already enforced; AC adds the structural test).

#### §9.3 — `fg-100-orchestrator` (subagent-driven-development + dispatching-parallel-agents + executing-plans)

Match against three superpowers patterns:
- **subagent-driven-development:** review checkpoint after each task. Already done via `fg-301-implementer-critic` between GREEN and REFACTOR.
- **dispatching-parallel-agents:** "single message, multiple Task uses" rule. Polish AC: structural check that orchestrator dispatches use single tool-use blocks for parallel groups.
- **executing-plans:** review after each batch. Polish AC: structural check that orchestrator emits a checkpoint after every 3 tasks.

#### §9.4 — `fg-101-worktree-manager` (using-git-worktrees)

Match against `superpowers:using-git-worktrees`:
- Already isolates work in `.forge/worktree/`. Polish: add stale-worktree detection (worktrees older than 30 days flagged for cleanup).
- Polish AC: assert smart directory selection (existing) and safety verification (existing).

### §10 — Beyond-superpowers improvements (in-line)

The four enhancements (goals 13-16) live inside the relevant uplift sections rather than as a separate section to keep them context-bound:

- §5 includes cross-reviewer consistency voting (goal 13).
- `fg-010-shaper` (§3) gains transcript mining (goal 14) — see implementation note below.
- §7 includes hypothesis branching (goal 15).
- §8 includes structured PR-finishing dialog (goal 16).

**Goal 14 implementation:** `fg-010-shaper` writes `.forge/brainstorm-transcripts/<run_id>.jsonl` (one entry per question/answer round). On a new feature, before asking questions, the agent queries the F29 run-history-store FTS5 index for similar features (cosine on description embeddings if available; else BM25 on the spec body). Top-3 historical transcripts are loaded; their question patterns inform the agent's prompt ("you have asked X% of users about authentication for similar features — consider asking it now"). No automatic question reuse — the agent decides what to ask, the transcripts are advisory context.

**Config:** `brainstorm.transcript_mining.enabled: true`, `brainstorm.transcript_mining.top_k: 3`.

### §11 — State schema impact

**State schema version:** Bump in lockstep with Phase 5's coordinated v2.0.0 bump. If this spec ships before Phase 5, take an interim v1.11.0; otherwise roll into v2.0.0.

**New fields:**

```jsonc
{
  "stage": "BRAINSTORMING",  // new enum value
  "brainstorm": {
    "spec_path": "docs/superpowers/specs/2026-04-27-add-export-csv-design.md",
    "original_input": "add CSV export to the user list",
    "started_at": "2026-04-27T14:23:11Z",
    "completed_at": "2026-04-27T14:31:42Z",
    "autonomous": false,
    "questions_asked": 4,
    "approaches_proposed": 3,
    "section_approvals": ["architecture", "components", "data_flow", "error_handling", "testing"]
  }
}
```

**Recovery treatment:** BRAINSTORMING is in the `resumable_stages` set. State-transition rules added to `shared/state-transitions.md`:
- `PREFLIGHT → BRAINSTORMING` when `mode == feature` and brainstorm is enabled.
- `BRAINSTORMING → EXPLORING` on completion.
- `BRAINSTORMING → ABORTED` on user abort.
- `BRAINSTORMING → BRAINSTORMING` (self-loop) on resume from cache.

#### §11.1 — Config schema additions

The following keys are added to `forge-config.md` (plugin defaults) and validated by `shared/preflight-constraints.md`:

```yaml
brainstorm:
  enabled: true                  # default true; set false to short-circuit BRAINSTORMING (feature mode → EXPLORING)
  spec_dir: docs/superpowers/specs/   # default; where fg-010-shaper writes specs
  autonomous_extractor_min_confidence: low   # one of: low, medium, high; below this, autonomous mode aborts instead of proceeding to EXPLORING
```

Validation rules:
- `brainstorm.enabled` must be boolean.
- `brainstorm.spec_dir` must be a string. The parent directory must exist or be creatable (write probe at PREFLIGHT).
- `brainstorm.autonomous_extractor_min_confidence` must be one of the three enum values.

These keys are NOT subject to retrospective auto-tuning (they're behavior toggles, not numeric thresholds). Add them to the `<!-- locked -->` section in the generated `forge-config.md`.

### §12 — Migration mechanics (the breaking change)

The bulk of the implementation work. The change is mechanically large because the consolidation rewrites every reference to `/forge-*` skills across the codebase.

**Pre-flight (zero commits):** Run `grep -rln '/forge-' --include='*.md' --include='*.json' --include='*.py' --include='*.yml' --include='*.yaml' --include='*.bats' --include='*.sh' .` and snapshot the file list to `.forge/migration-callsites.txt`. This list is the literal input for commit 4's sed pass — eliminates "we forgot to grep $X" failure modes.

**Ground truth from `ls skills/` (verified 2026-04-27):** 29 skill directories exist. After this spec lands: 1 stays (`forge-ask`, edited in place), 28 are deleted, 2 are newly created (`forge`, `forge-admin`). Net delta: 28 deleted, 2 created, 1 edited. `forge-help` is **still present** today — Phase 2's deletion claim of `/forge-help` was never executed; this spec executes it as part of the 28.

**Commit ordering (atomic, granular — ~25 commits):**

The train is split into four phases. Phases A and B are independent and can ship in parallel branches; phase C depends on B; phase D can ship anytime after A. Within each phase, commits are sequential.

#### Phase A — Helpers and schema (independent, can ship first)

1. **Commit A1 — add `shared/ac-extractor.py`:** New helper for autonomous BRAINSTORMING. Contract per §3. Tests at `tests/unit/ac_extractor_test.py` covering: numbered list, given/when/then, imperative bullets, low-confidence (<2 ACs), high-confidence (≥5 ACs).
2. **Commit A2 — extract `shared/bootstrap-detect.py`:** Lift detection logic from `skills/forge-init/SKILL.md` (still on disk) into the helper. Module exposes `detect_stack() -> dict`, `write_forge_local_md(stack, path) -> None`. Tests at `tests/unit/bootstrap_detect_test.py` covering: Kotlin/Spring, TypeScript/Next, Python/FastAPI, ambiguous-stack rejection, write-failure handling. Pure addition.
3. **Commit A3 — `shared/preflight-constraints.md` updates:** Add validation rules for `brainstorm.{enabled,spec_dir,autonomous_extractor_min_confidence,transcript_mining.{enabled,top_k}}`, `quality_gate.consistency_promotion.{enabled,threshold}`, `bug.hypothesis_branching.enabled`, `post_run.{defense_enabled,defense_min_evidence}`, `pr_builder.{default_strategy,cleanup_checklist_enabled}`. Per-key validation rules per §11.1.
4. **Commit A4 — `shared/intent-classification.md` updates:** Extend to recognize all 11 verbs (`run|fix|sprint|review|verify|deploy|commit|migrate|bootstrap|docs|audit`). Define `vague` outcome with concrete signal-count threshold (default <2). Update existing tests under `tests/unit/intent-classification/`.
5. **Commit A5 — state schema bump:** Update `shared/state-schema.md` to add the `BRAINSTORMING` enum value, `state.brainstorm` object (per §11), `state.bug.hypotheses[]` (per §7), `state.feedback_decisions` (per §6). Bump schema version (next available minor: v1.11.0 if Phase 5 hasn't landed, else v2.1.0). Update `shared/state-transitions.md` with BRAINSTORMING transitions per §11. Update `shared/stage-contract.md` to define the new stage.

#### Phase B — Skill surface and dispatch (depends on A2 only)

6. **Commit B1 — create `skills/forge/SKILL.md`:** Full implementation of hybrid grammar (§1). Calls `shared/bootstrap-detect.py` on missing `forge.local.md` (§2). Dispatches to existing agents.
7. **Commit B2 — create `skills/forge-admin/SKILL.md`:** Full implementation of subcommand grammar (§1). Dispatches.
8. **Commit B3 — rewrite `skills/forge-ask/SKILL.md` in place:** Absorb status/history/insights/profile/tour subcommands; default action is codebase Q&A.
9. **Commit B4 — pre-flight grep capture:** Snapshot `grep -rln '/forge-' --include='*.md' --include='*.json' --include='*.py' --include='*.yml' --include='*.yaml' --include='*.bats' --include='*.sh' .` to `tests/structural/migration-callsites.txt` (checked in). Used as the literal input for B5–B10 sed passes and as the test fixture for AC-S005 stragglers.
10. **Commit B5 — rewire `docs/`:** All files under `docs/superpowers/specs/` and `docs/superpowers/plans/`, plus `README.md`, `CLAUDE.md`. Apply mapping table (§12.1).
11. **Commit B6 — rewire `tests/`:** All `.bats` files and any test fixture under `tests/scenarios/`.
12. **Commit B7 — rewire `agents/`:** All 48 agent `.md` files. Especially fg-100, fg-700, fg-710, and any agent emitting user-facing skill suggestions or learnings markers.
13. **Commit B8 — rewire `shared/` (~56 files):** Apply mapping table to every file in the §12 enumeration. Includes `shared/intent-classification.md` (already partly updated in A4 — reconciliation pass).
14. **Commit B9 — rewire `modules/` (~49 files):** Every framework's `local-template.md` and `forge-config-template.md`. Plus any `modules/**/conventions.md` that references skills.
15. **Commit B10 — rewire root + manifests:** `plugin.json`, `marketplace.json`, hooks under `hooks/` that emit skill-name diagnostics.
16. **Commit B11 — `shared/skill-subcommand-pattern.md` decision:** Either delete (preferred — pattern is now internal to the three SKILL.md bodies) or rewrite to describe the three-skill dispatch model. Decision goes to plan-stage; spec flags the choice.
17. **Commit B12 — atomic deletion of 28 retired skills:** `git rm -r` all 28 directories listed in §12 ground-truth check. Must come AFTER B5–B10 rewiring is verified clean.
18. **Commit B13 — add new tests:** `tests/unit/skill-execution/forge-dispatch.bats` (11 verbs + 3 NL fallback), `tests/unit/skill-execution/spec-wellformed.bats`, `tests/structural/fg-010-shaper-shape.bats`, `tests/scenarios/autonomous-cold-start.bats`. Extend `tests/structural/skill-consolidation.bats` to enforce exactly 3 skill dirs. Add `tests/structural/skill-references-allowlist.txt`.

#### Phase C — Brainstorming behavior (depends on A and B)

19. **Commit C1 — rewrite `agents/fg-010-shaper.md`:** Adopt the seven-step pattern (§3). Section headings exactly match `tests/structural/fg-010-shaper-shape.bats` regex. Autonomous degradation per §3. Transcript mining per §10 (writes `.forge/brainstorm-transcripts/<run_id>.jsonl`).
20. **Commit C2 — update `agents/fg-100-orchestrator.md`:** Recognize BRAINSTORMING stage. Dispatch fg-010-shaper for feature mode; skip for bug/migrate/bootstrap. Honor `brainstorm.enabled: false` short-circuit. Resume semantics per §3.

#### Phase D — Pattern parity uplifts (independent of B; can ship in parallel branches)

21. **Commit D1 — rewrite `agents/fg-200-planner.md`:** Adopt writing-plans pattern (§4). Per-task TDD scaffold. Embed prompt templates from `shared/prompts/implementer-prompt.md` and `shared/prompts/spec-reviewer-prompt.md` (new files added in this commit).
22. **Commit D2 — `fg-210-validator` updates:** Enforce TDD ordering, prompt presence, spec-reviewer presence. Updates AC validation matrix.
23. **Commit D3 — reviewer pipeline uplift:** Update each `agents/fg-410..fg-419.md` to emit prose report alongside findings JSON (§5). Update `agents/fg-400-quality-gate.md` to write reports to `.forge/runs/<run_id>/reports/<reviewer>.md`.
24. **Commit D4 — cross-reviewer consistency voting:** Add post-dedup pass to `agents/fg-400-quality-gate.md` (§5 beyond-superpowers). Logs `consistency_promoted` on findings.
25. **Commit D5 — rewrite `agents/fg-710-post-run.md`:** Adopt receiving-code-review pattern (§6). Defense check sub-agent dispatch. Update `feedback_loop_count` semantics. New file `.forge/runs/<run_id>/feedback-decisions.jsonl`.
26. **Commit D6 — rewrite `agents/fg-020-bug-investigator.md`:** Adopt systematic-debugging pattern (§7). Hypothesis register. Hypothesis branching sub-investigators. Bayesian pruning. Fix gate.
27. **Commit D7 — rewrite `agents/fg-600-pr-builder.md`:** Adopt finishing-a-development-branch shape (§8). AskUserQuestion-driven dialog. Cleanup checklist.
28. **Commit D8 — strong-agent polish:** Targeted updates to `fg-300-implementer` (test-must-fail-first check), `fg-590-pre-ship-verifier` (evidence assertion test), `fg-100-orchestrator` (parallel-dispatch and post-batch checkpoint structural tests), `fg-101-worktree-manager` (stale-worktree detection).
29. **Commit D9 — pattern-parity tests:** Structural and scenario tests for D1–D8: planner output shape, reviewer prose presence, defense flow, hypothesis register, PR-finishing dialog, polish edge cases.

#### Phase E — Documentation rollup (last, depends on all)

30. **Commit E1 — `CLAUDE.md` and `README.md` mega update:** Reflect new skill surface, BRAINSTORMING stage, all uplifts, beyond-superpowers improvements. Add a "Pattern parity" section listing which superpowers patterns are mirrored where.
31. **Commit E2 — feature matrix update:** Regenerate `<!-- FEATURE_MATRIX_START -->` block in CLAUDE.md (per Phase 2 spec) with new entries for transcript mining, hypothesis branching, consistency voting, defense checking.

**Total: 31 commits across 5 phases.** Phases A and D can run in parallel branches if sub-pipelines support it; phases B and C are serial.

#### §12.1 — Old → new mapping table (search/replace source of truth)

```
/forge-init                  →  (auto on /forge or /forge bootstrap or /forge-admin config wizard)
/forge-run                   →  /forge run
/forge-fix                   →  /forge fix
/forge-shape                 →  (absorbed into BRAINSTORMING in /forge run)
/forge-sprint                →  /forge sprint
/forge-review                →  /forge review
/forge-verify                →  /forge verify
/forge-deploy                →  /forge deploy
/forge-commit                →  /forge commit
/forge-migration             →  /forge migrate
/forge-bootstrap             →  /forge bootstrap
/forge-docs-generate         →  /forge docs
/forge-security-audit        →  /forge audit
/forge-status                →  /forge-ask status
/forge-history               →  /forge-ask history
/forge-insights              →  /forge-ask insights
/forge-profile               →  /forge-ask profile
/forge-tour                  →  /forge-ask tour
/forge-help                  →  (deleted in Phase 2; remove any remaining refs)
/forge-ask                   →  /forge-ask
/forge-recover               →  /forge-admin recover
/forge-abort                 →  /forge-admin abort
/forge-config                →  /forge-admin config
/forge-handoff               →  /forge-admin handoff
/forge-automation            →  /forge-admin automation
/forge-playbooks             →  /forge-admin playbooks
/forge-playbook-refine       →  /forge-admin refine
/forge-compress              →  /forge-admin compress
/forge-graph                 →  /forge-admin graph
```

This table is the authoritative source for the rewiring commit. The implementation plan will codify it as a sed/awk script that the implementer runs against the repo, then verifies with grep.

### §13 — Parallelization (preserved)

All current parallel-execution patterns continue to work in the new surface:

| Level | Mechanism | New invocation |
|---|---|---|
| Feature | `fg-090-sprint-orchestrator` + `fg-015-scope-decomposer` | `/forge sprint --parallel "<feat A>" "<feat B>"` |
| Task | `fg-102-conflict-resolver` (scaffolders serial → conflict detect → implementers parallel) | Internal — happens during `/forge run` IMPLEMENTING stage |
| Reviewer | `fg-400-quality-gate` parallel batch dispatch | Internal — happens during `/forge run` REVIEWING stage |

`--parallel` flag continues to be valid for `/forge sprint`. (Out of scope for this spec: parallelizing EXPLORE by aspect; that lands in Phase 10.)

### §14 — Open coordination questions

1. **State schema bump ordering.** Phase 5 coordinates a v2.0.0 bump for `plan_judge_loops`, `impl_judge_loops`, `judge_verdicts[]`, plus removals of `critic_revisions` and `implementer_reflection_cycles`. Phase 5's spec (read 2026-04-27) does **not** mention `state.brainstorm`; rolling into v2.0.0 would require an explicit edit to Phase 5's spec, which is undesirable cross-coupling between in-flight specs.
   - **Default (chosen by this spec):** Take a fresh `v1.11.0` (if Phase 5 has not landed yet) or `v2.1.0` (if Phase 5 has landed). Decoupled — this spec ships independently of Phase 5's release cadence.
   - Implementation note: the plan-stage will inspect `shared/state-schema.md` at the time of execution and pick whichever next-minor version is correct given the live schema version. No coordination with Phase 5 is required.

2. **OTel namespace.** Phase 1 standardizes `forge.*`. New events under `forge.brainstorm.*` (started, questions_asked, approaches_proposed, spec_written, completed, aborted) fit cleanly. No conflict.

3. **Phase 7 (Intent Assurance) interaction.** `fg-540-intent-verifier` checks ACs at VERIFY. With BRAINSTORMING writing the spec to a known path (`state.brainstorm.spec_path`), `fg-540` reads ACs from there. Tight integration, no conflict — but Phase 7's spec must be updated to consume `state.brainstorm.spec_path` as the AC source when present, falling back to the old behavior when absent (e.g., bugfix mode where there's no brainstorm spec).

4. **Phase 9 (Superpowers Pattern Parity) — out of scope here, but tightly related.** This spec lifts the brainstorming pattern. Phase 9 lifts the writing-plans, requesting-code-review, receiving-code-review, systematic-debugging, and finishing-a-development-branch patterns into the corresponding forge agents. Phase 9 is a separate spec in this directory (date: TBD by orchestrator), sized at ~15-25 ACs covering the seven agent uplifts. It depends on this spec for the BRAINSTORMING pseudo-stage but is otherwise independent.

## Acceptance criteria

### Skill surface (5)

- **AC-S001:** `skills/` contains exactly three subdirectories: `forge/`, `forge-ask/`, `forge-admin/`. No others.
- **AC-S002:** Each of the three skills has valid frontmatter (`name`, `description` matching the patterns in §1, `allowed-tools`, `ui:`).
- **AC-S003:** All 26 retired skill directories are absent from `skills/` (full list in §5 commit 2).
- **AC-S004:** `tests/structural/skill-consolidation.bats` enforces AC-S001 and AC-S003.
- **AC-S005:** No file under `docs/`, `tests/`, `agents/`, `skills/`, `hooks/`, `shared/`, `plugin.json`, `marketplace.json`, `README.md`, or `CLAUDE.md` references any retired skill name. `grep -rn "/forge-init\|/forge-run\|/forge-fix\|...\|/forge-graph"` returns zero results except for paths listed in `tests/structural/skill-references-allowlist.txt` (which holds intentional historical references in CHANGELOG, release notes, or migration docs). The allowlist file is checked into git.

### Hybrid grammar (5)

- **AC-S006:** `/forge run "X"`, `/forge fix "X"`, `/forge sprint ...`, `/forge review`, `/forge verify`, `/forge deploy <env>`, `/forge commit`, `/forge migrate "X to Y"`, `/forge bootstrap <stack>`, `/forge docs`, `/forge audit` each dispatch to the correct downstream agent flow.
- **AC-S007:** `/forge "<free-text>"` (no explicit verb) routes through `shared/intent-classification.md` and dispatches to whichever mode the classifier returns. When the classifier returns its `vague` outcome (signal-count < 2 per the contract added in commit 7), the dispatch defaults to `run` (which then enters BRAINSTORMING and lets the shaper resolve ambiguity). Verified by unit tests at `tests/unit/skill-execution/forge-dispatch.bats` containing at least 11 tests — one per verb (`run`, `fix`, `sprint`, `review`, `verify`, `deploy`, `commit`, `migrate`, `bootstrap`, `docs`, `audit`) — plus 3 tests for the NL fallback (vague-input, classifier-resolved-input, ambiguous-flag-positioning).
- **AC-S008:** `/forge --help` prints the full subcommand list and flag matrix; exits 0.
- **AC-S009:** `/forge` (no args) prints usage; exits 0.
- **AC-S010:** `/forge <unknown-verb> <args>` does NOT print "did you mean"; falls through to NL classifier with the full string. Verified by `tests/unit/skill-execution/forge-dispatch.bats::test_unknown_verb_falls_through` asserting (a) no string `"did you mean"` in stdout/stderr, (b) classifier was invoked with the full original argument string.

### Read and admin surfaces (4)

- **AC-S011:** `/forge-ask <question>` (with text) defaults to codebase Q&A. `/forge-ask status|history|insights|profile|tour` dispatch to their named handlers.
- **AC-S012:** `/forge-ask` writes nothing — verified by a contract test that runs every subcommand and asserts `git status` is unchanged after.
- **AC-S013:** `/forge-admin <area> [<action>]` dispatches correctly for all areas listed in §1: recover, abort, config, handoff, automation, playbooks, compress, graph, refine.
- **AC-S014:** `/forge-admin graph query <cypher>` rejects any non-read-only Cypher (existing constraint, ported).

### Auto-bootstrap (4)

- **AC-S015:** `/forge "<request>"` invoked with `.claude/forge.local.md` absent triggers auto-bootstrap. Detection runs, single confirmation prompt fires, default option `[proceed]` writes `forge.local.md`, then user's original request continues.
- **AC-S016:** Auto-bootstrap is **not** triggered by `.forge/` absence alone. Test: clear `.forge/` while keeping `forge.local.md`, run `/forge`, assert no bootstrap prompt fires.
- **AC-S017:** `--autonomous` or `autonomous: true` skips the confirmation prompt; writes `forge.local.md` with detected defaults; logs `[AUTO] bootstrapped...`.
- **AC-S018:** Detection failure aborts with explicit error pointing to `/forge-admin config wizard`. Malformed `forge.local.md` aborts with explicit error pointing to `/forge verify --config` (does **not** auto-bootstrap on top of broken config).

### BRAINSTORMING stage (5)

- **AC-S019:** Feature-mode invocations of `/forge` (explicit `run` or NL classifier → `run`) traverse PREFLIGHT → BRAINSTORMING → EXPLORING. Verified by scenario test.
- **AC-S020:** Bugfix, migration, bootstrap modes skip BRAINSTORMING. Verified by scenario test for each mode.
- **AC-S021:** `fg-010-shaper`'s rewritten prompt implements all seven steps from §3. Verified by a structural agent-prompt test at `tests/structural/fg-010-shaper-shape.bats` that greps `agents/fg-010-shaper.md` for the exact section headings `## Explore project context`, `## Ask clarifying questions`, `## Propose 2-3 approaches`, `## Present design sections`, `## Write spec`, `## Self-review`, `## Handoff` and asserts each appears exactly once. The headings are normative for the agent's prompt structure.
- **AC-S022:** `--autonomous` mode runs degraded one-shot: no `AskUserQuestion`, treats input as spec, writes spec, logs `[AUTO] brainstorm skipped`. Verified by scenario test.
- **AC-S023:** Resume during BRAINSTORMING with existing spec prompts user to resume-from-spec or restart. Verified by scenario test.

### State and telemetry (3)

- **AC-S024:** State schema includes `state.stage = "BRAINSTORMING"` enum and `state.brainstorm` object with all fields from §11.
- **AC-S025:** OTel events fire at brainstorm start, question, approaches proposal, spec write, completion/abort. Namespace `forge.brainstorm.*`.
- **AC-S026:** `state-transitions.md` documents the four BRAINSTORMING transitions from §11.
- **AC-S027:** `/forge --autonomous "<request>"` invoked on a project with no `forge.local.md` chains auto-bootstrap → BRAINSTORMING → EXPLORING in a single uninterrupted run. Both `[AUTO] bootstrapped...` and `[AUTO] brainstorm skipped...` log lines appear in `.forge/forge-log.md`. The pipeline reaches EXPLORING. If either step fails, the pipeline aborts cleanly with no partial state (`forge.local.md` is either fully written or not written; spec doc is either fully written or not written). Verified by scenario test at `tests/scenarios/autonomous-cold-start.bats`.
- **AC-S028:** Config keys `brainstorm.spec_dir` (default `docs/superpowers/specs/`) and `brainstorm.enabled` (default `true`) are validated by `shared/preflight-constraints.md`. Setting `brainstorm.enabled: false` short-circuits BRAINSTORMING — feature mode goes straight to EXPLORING. Setting an invalid `brainstorm.spec_dir` (non-existent and non-creatable parent) fails PREFLIGHT with a clear error.
- **AC-S029:** `/forge run --spec <path>` parses the spec file at `<path>` for the regex `^## (Objective|Goal|Goals)$`, `^## (Scope|Non-goals)$`, and `^## (Acceptance [Cc]riteria|ACs)$`. All three sections must be present (case-sensitive on the regex). If any is missing, interactive mode prompts "spec at `<path>` is incomplete (missing: <list>); run BRAINSTORMING instead?" and autonomous mode aborts the run with the same diagnostic. Verified by unit test at `tests/unit/skill-execution/spec-wellformed.bats`.

### Planner uplift (8)

- **AC-PLAN-001:** `agents/fg-200-planner.md` produces plans where every implementation task has a preceding test task. Verified by `tests/structural/planner-tdd-ordering.bats` parsing a sample plan output and asserting the `Type: test` task ID appears in `Depends on:` of the corresponding `Type: implementation` task.
- **AC-PLAN-002:** Each task in planner output includes an embedded `Implementer prompt:` section sourced from `shared/prompts/implementer-prompt.md` with placeholder substitution (`{TASK_DESCRIPTION}`, `{ACS}`, `{FILE_PATHS}`).
- **AC-PLAN-003:** Each test task includes an embedded `Spec-reviewer prompt:` section sourced from `shared/prompts/spec-reviewer-prompt.md` with the same substitution contract.
- **AC-PLAN-004:** Each task carries explicit `Risk:` field with value `low | medium | high` (no other values accepted).
- **AC-PLAN-005:** `agents/fg-210-validator.md` rejects plans missing any TDD ordering, prompt embedding, or risk marker. Verdict: `REVISE`. Verified by unit test running validator against synthetic broken plans.
- **AC-PLAN-006:** Files `shared/prompts/implementer-prompt.md` and `shared/prompts/spec-reviewer-prompt.md` exist with the canonical superpowers shapes (verbatim or near-verbatim with attribution comment).
- **AC-PLAN-007:** Planner output is reproducible — running the planner twice on the same spec yields plans with the same task structure (modulo task IDs which may be timestamp-based).
- **AC-PLAN-008:** Autonomous mode produces planner output that satisfies AC-PLAN-001 through AC-PLAN-005 without user prompts.

### Reviewer pipeline uplift (6)

- **AC-REVIEW-001:** Each reviewer agent (`fg-410..fg-419`) emits two outputs: findings JSON (existing path) and prose report at `.forge/runs/<run_id>/reports/<reviewer>.md`.
- **AC-REVIEW-002:** Prose report contains exactly the section headings `## Strengths`, `## Issues`, `## Recommendations`, `## Assessment`, with `## Issues` further subdivided into `### Critical (Must Fix)`, `### Important (Should Fix)`, `### Minor (Nice to Have)`. Verified by structural test parsing the report markdown.
- **AC-REVIEW-003:** `## Assessment` section includes `**Ready to merge:** Yes | No | With fixes` and `**Reasoning:** <text>`. Both fields required.
- **AC-REVIEW-004:** Findings JSON and prose report share dedup keys (`(component, file, line, category)` per scoring). For each issue in the prose report, the same dedup key appears in findings JSON. Verified by reconciliation test.
- **AC-REVIEW-005:** `agents/fg-400-quality-gate.md` post-deduplication promotes a finding to HIGH confidence (1.0 multiplier) when ≥3 reviewers flag the same dedup key. Logged as `consistency_promoted: true` on the finding. Threshold configurable via `quality_gate.consistency_promotion.threshold`.
- **AC-REVIEW-006:** Setting `quality_gate.consistency_promotion.enabled: false` disables promotion (no findings carry `consistency_promoted: true`). Verified by integration test with synthetic findings.

### Post-run / receiving-feedback uplift (5)

- **AC-FEEDBACK-001:** `agents/fg-710-post-run.md` runs a defense check sub-agent dispatch for each piece of PR rejection feedback. Output schema: `{verdict: "actionable" | "wrong" | "preference", reasoning: str, evidence: str}`.
- **AC-FEEDBACK-002:** When `verdict: wrong`, defense response (reasoning + evidence) is posted to the PR conversation thread via GitHub MCP. Logged as `addressed: defended` in `.forge/runs/<run_id>/feedback-decisions.jsonl`.
- **AC-FEEDBACK-003:** When `verdict: preference`, acknowledgment is posted; logged as `addressed: acknowledged`. No code changes made for that comment.
- **AC-FEEDBACK-004:** `feedback_loop_count` increments only for `actionable` feedback. Defended/acknowledged feedback does not increment.
- **AC-FEEDBACK-005:** Autonomous mode without GitHub MCP write access defaults all verdicts to `actionable` (matches today's behavior; documented degradation).

### Debugging uplift (7)

- **AC-DEBUG-001:** `agents/fg-020-bug-investigator.md` writes `state.bug.hypotheses[]` after reproduction, with each entry containing `{id, statement, falsifiability_test, evidence_required, status}`.
- **AC-DEBUG-002:** When `bug.hypothesis_branching.enabled: true` (default), up to 3 hypothesis sub-investigators dispatch in parallel via single tool-use block. Each emits `{hypothesis_id, evidence: list[str], passes_test: bool, confidence: "high" | "medium" | "low"}`.
- **AC-DEBUG-003:** Bayesian pruning step updates each hypothesis's posterior probability per the formula in §7. Hypotheses below 0.10 posterior are dropped.
- **AC-DEBUG-004:** Fix gate: `agents/fg-200-planner.md` (in bugfix mode) refuses to plan a fix until `state.bug.fix_gate_passed: true`. Gate condition: ≥1 hypothesis with `passes_test: true` AND posterior ≥ 0.50.
- **AC-DEBUG-005:** When all hypotheses fail the gate, interactive mode escalates to user with the hypothesis register attached; autonomous mode logs `[AUTO] bug investigation inconclusive — aborting fix attempt` and exits non-zero.
- **AC-DEBUG-006:** Each hypothesis carries a falsifiability test in `falsifiability_test` field. Sub-investigator runs the test before declaring `passes_test`.
- **AC-DEBUG-007:** Setting `bug.hypothesis_branching.enabled: false` falls back to single-hypothesis serial investigation (legacy behavior).

### Branch finishing uplift (5)

- **AC-BRANCH-001:** `agents/fg-600-pr-builder.md` presents `AskUserQuestion` with the five options listed in §8 (`open-pr | open-pr-draft | direct-push | stash | abandon`). Default option: `open-pr`.
- **AC-BRANCH-002:** Autonomous mode applies `pr_builder.default_strategy` config (default `open-pr`) without prompting.
- **AC-BRANCH-003:** Cleanup checklist runs after the chosen strategy completes: worktree deletion, run-history update, Linear/GitHub issue link update (if linked), feature-flag TODO logging, schedule-follow-up suggestion.
- **AC-BRANCH-004:** Setting `pr_builder.cleanup_checklist_enabled: false` skips the cleanup phase but does not skip core PR creation.
- **AC-BRANCH-005:** `[abandon]` option requires a second confirmation `AskUserQuestion` before destructive cleanup.

### Strong-agent polish (5)

- **AC-POLISH-001:** `agents/fg-300-implementer.md` includes the test-must-fail-first check: when a fresh test passes immediately without implementation change, log a CRITICAL finding (`TEST-NOT-FAILING`) and abort the task.
- **AC-POLISH-002:** `agents/fg-590-pre-ship-verifier.md` writes `.forge/evidence.json` with all four signals (build, test, lint, review verdict). PR builder asserts `evidence.verdict == "SHIP"` before proceeding.
- **AC-POLISH-003:** `agents/fg-100-orchestrator.md` parallel-dispatch sites use single tool-use blocks. Verified by `tests/structural/orchestrator-parallel-dispatch.bats` parsing the agent file for `<Task>` blocks and asserting groups marked `parallel: true` are dispatched in one block.
- **AC-POLISH-004:** `agents/fg-100-orchestrator.md` emits a checkpoint after every 3 tasks (matches `superpowers:executing-plans`). Verified by structural test.
- **AC-POLISH-005:** `agents/fg-101-worktree-manager.md` flags worktrees older than 30 days as stale, logs `WORKTREE-STALE` finding for cleanup. Configurable via `worktree.stale_after_days` (default 30).

### Beyond-superpowers (4)

- **AC-BEYOND-001:** `agents/fg-010-shaper.md` writes Q&A transcripts to `.forge/brainstorm-transcripts/<run_id>.jsonl` (one entry per question/answer round).
- **AC-BEYOND-002:** Before asking questions, fg-010-shaper queries the F29 run-history-store FTS5 index for similar features (top-K via `brainstorm.transcript_mining.top_k`, default 3). Top-K transcripts are loaded and exposed to the agent's reasoning context.
- **AC-BEYOND-003:** Setting `brainstorm.transcript_mining.enabled: false` skips the FTS5 query and proceeds with no historical context.
- **AC-BEYOND-004:** When `quality_gate.consistency_promotion.enabled: true` and ≥3 reviewers flag the same dedup key, the finding's confidence weight is `1.0` regardless of individual reviewer ratings (verified by AC-REVIEW-005, restated here for the beyond-superpowers thread).

## Risks

1. **Scope blast radius.** ~200+ callsite rewires. Risk: missed reference. Mitigation: B4 pre-flight grep snapshot is the literal input to B5–B10; AC-S005 grep test catches stragglers; CI fails until clean.
2. **Brainstorm fatigue.** Always-on brainstorm could feel slow for users who already have crisp specs. Mitigation: `--spec <path>` skip-with-existing-spec, autonomous degradation, and `brainstorm.enabled: false` emergency disable.
3. **Intent classifier weakness.** Hybrid grammar relies on the NL classifier handling 11 verbs cleanly. Risk: misroute. Mitigation: A4 expands classifier explicitly; AC-S007 + 11 new unit tests cover the verb matrix.
4. **Schema bump coupling with Phase 5.** If Phase 5 ships first, take v2.1.0; otherwise v1.11.0. Mitigation: A5 inspects live schema at execution time and picks the next minor.
5. **Autonomous AC extraction quality.** Heuristic extractor produces low-quality specs on prose-heavy input. Mitigation: confidence level surfaces to validator; low-confidence specs flagged as REVISE downstream.
6. **Defense-check false positives (post-run uplift).** Sub-agent might dispute legitimate feedback. Mitigation: defense response is logged + posted (transparent), reviewer can re-comment, `feedback_loop_count` still escalates if "actionable" feedback recurs.
7. **Hypothesis-branching cost.** Three parallel sub-investigators × Tier-3 model multiplies bug-investigation cost ~3x. Mitigation: only fires for hard bugs (config gateable); Tier-3 is the cheap tier; Bayesian pruning ends investigation as soon as a hypothesis confirms.
8. **Cross-reviewer consistency over-promotion.** ≥3 reviewers might agree on a stylistic Minor finding, promoting it to HIGH. Mitigation: promotion is logged separately (`consistency_promoted: true`); analytics track impact; threshold tunable.
9. **Plan-train length.** 31 commits is a lot to merge. Mitigation: phases A and D are independent and can ship on parallel branches; phases B and C are serial.
10. **Coupled agent rewrites.** Five agent rewrites + four polish updates × N test suites = a wide blast radius. Mitigation: each commit is atomic and revertable; D9 pattern-parity tests gate each rewrite.

## Out of scope

- **EXPLORE parallelization by aspect** — separate Phase 10 if ever pursued.
- **Backwards-compatibility shims** — explicitly rejected per personal-tool stance.
- **Replacing scoring with prose verdicts** — reviewer parity adds prose alongside scoring; scoring stays authoritative.
- **`fg-300-implementer` core rewrite, `fg-100-orchestrator` core rewrite, `fg-101-worktree-manager` core rewrite** — already strong; only polish ACs in scope.
- **External superpowers plugin runtime dependency** — patterns are ported in-tree; no `superpowers:` skill is invoked at forge runtime.

## File touchpoints (preview, full enumeration in plan)

### Skill consolidation half

- **Created:**
  - `skills/forge/SKILL.md`, `skills/forge-admin/SKILL.md` (new skill directories — B1, B2).
  - `shared/bootstrap-detect.py` (lifted detection helper — A2).
  - `shared/ac-extractor.py` (autonomous AC extractor — A1).
  - `tests/structural/migration-callsites.txt` (pre-flight grep snapshot — B4).
  - `tests/structural/skill-references-allowlist.txt` (allowlist for AC-S005 — B13).
  - `tests/unit/skill-execution/forge-dispatch.bats`, `tests/unit/skill-execution/spec-wellformed.bats`, `tests/unit/bootstrap_detect_test.py`, `tests/unit/ac_extractor_test.py`, `tests/structural/fg-010-shaper-shape.bats`, `tests/scenarios/autonomous-cold-start.bats` (new tests — B13).
- **Deleted:** 28 skill directories (B12 — full list in §12).
- **Heavily edited:** `skills/forge-ask/SKILL.md` (B3), `agents/fg-010-shaper.md` (C1), `agents/fg-100-orchestrator.md` (C2 + D8), `shared/{state-schema,state-transitions,stage-contract}.md` (A5), `shared/intent-classification.md` (A4 + B8 reconciliation), `shared/preflight-constraints.md` (A3), `shared/skill-subcommand-pattern.md` (B11), `CLAUDE.md`, `README.md` (E1).
- **Lightly edited (rewiring only):** all 8 phase specs in `docs/superpowers/specs/` (B5), all 8 phase plans (B5), all 48 agent `.md` files (B7), all 56 markdown files under `shared/` (B8), all ~49 module templates (B9), `plugin.json`, `marketplace.json`, hooks (B10).

### Pattern parity half

- **Created:**
  - `shared/prompts/implementer-prompt.md` (D1) — canonical implementer dispatch template.
  - `shared/prompts/spec-reviewer-prompt.md` (D1) — canonical spec compliance reviewer template.
  - `tests/structural/planner-tdd-ordering.bats` (D9) — verifies planner output shape.
  - `tests/structural/reviewer-prose-shape.bats` (D9) — verifies prose report headings.
  - `tests/structural/fg-020-hypothesis-register.bats` (D9) — verifies hypothesis register schema.
  - `tests/structural/fg-600-pr-finishing-dialog.bats` (D9) — verifies AskUserQuestion dialog options.
  - `tests/structural/orchestrator-parallel-dispatch.bats` (D9) — verifies single tool-use parallel block.
  - `.forge/runs/<run_id>/reports/<reviewer>.md` (runtime artifact directory, gitignored).
  - `.forge/runs/<run_id>/feedback-decisions.jsonl` (runtime artifact, gitignored).
  - `.forge/brainstorm-transcripts/<run_id>.jsonl` (runtime artifact, gitignored, survives `/forge-admin recover reset`).
- **Heavily edited:**
  - `agents/fg-200-planner.md` (D1) — full rewrite for writing-plans pattern.
  - `agents/fg-210-validator.md` (D2) — extended validation matrix.
  - `agents/fg-410..fg-419.md` — 9 reviewer files updated for prose output (D3).
  - `agents/fg-400-quality-gate.md` (D3 + D4) — prose report orchestration + cross-reviewer consistency promotion.
  - `agents/fg-710-post-run.md` (D5) — full rewrite for receiving-code-review pattern.
  - `agents/fg-020-bug-investigator.md` (D6) — full rewrite for systematic-debugging pattern.
  - `agents/fg-600-pr-builder.md` (D7) — full rewrite for finishing-branch pattern.
  - `agents/fg-300-implementer.md` (D8) — test-must-fail-first check.
  - `agents/fg-590-pre-ship-verifier.md` (D8) — evidence assertion structural test.
  - `agents/fg-101-worktree-manager.md` (D8) — stale-worktree detection.
  - `shared/state-schema.md` (A5 + D5 + D6 — `state.bug.hypotheses[]`, `state.feedback_decisions`).
  - `shared/preflight-constraints.md` (A3 — all new config keys).
- **Lightly edited:** `CLAUDE.md` (E1) — pattern parity section, feature matrix update (E2).
