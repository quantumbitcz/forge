# Phase 2: Contract Enforcement — Design

Date: 2026-04-22
Scope: `forge` plugin (personal tool, solo developer). No backwards compatibility; tests run in CI only.

## Goal

Close five contract and hygiene gaps that have accumulated since 3.0. Each gap is a place where a written rule exists but no CI test enforces it, or where skill surface inconsistency has made the CLI harder to reason about than necessary. The fix is never "rewrite the agent/skill" — it is "land the missing contract test, land the narrow edits that make current files pass the test, and update docs so the rule is discoverable."

## Problem Statement

1. **Implicit Tier-4-by-omission.** `shared/agents.md:19` declares: *"ui: — the UI-capability tier (1–4), explicit per shared/agent-ui.md. Implicit Tier-4-by-omission is no longer accepted."* Reality: 13 agent files ship no `ui:` block at all. Confirmed missing (`grep -l '^ui:' agents/*.md` inverse) in `agents/fg-101-worktree-manager.md`, `fg-102-conflict-resolver.md`, `fg-205-planning-critic.md`, `fg-410-code-reviewer.md`, `fg-411-security-reviewer.md`, `fg-412-architecture-reviewer.md`, `fg-413-frontend-reviewer.md`, `fg-414-license-reviewer.md`, `fg-416-performance-reviewer.md`, `fg-417-dependency-reviewer.md`, `fg-418-docs-consistency-reviewer.md`, `fg-419-infra-deploy-reviewer.md`, `fg-510-mutation-analyzer.md`. The existing contract test `tests/contract/ui-frontmatter-consistency.bats` only checks *consistency between `ui:` and `tools:` when `ui:` is present*. It does not check presence.

2. **Skill grammar drift.** 29 skills under `skills/` mix four invocation styles: flags (`/forge-verify --build`), subcommands (`/forge-graph init`), positional text (`/forge-compress output full`), and silent positional content (`/forge-graph query "MATCH (n) RETURN n"`). `skills/forge-sprint/SKILL.md:16` carries an extra malformed line after the ui block (`ui: { ask: true, tasks: true }` with no `plan_mode` key). No contract enforces which skills may use which style, and no linter rejects unknown frontmatter keys.

3. **Inspection-skill overlap.** Three skills read `.forge/state.json` with overlapping ceremony: `/forge-status` (pipeline state), `/forge-verify --config` (config validation), `/forge-recover diagnose` (pipeline health). Each repeats its own git-repo + forge-initialized prerequisite block. `/forge-help` exists purely as a static decision tree — per user memory, this duplicates what LLM routing already does well.

4. **fg-100-orchestrator size.** `wc -l agents/fg-100-orchestrator.md` = 1557. Per user memory, size is *not* a per-stage loading cost. But an orchestrator prompt of this size competes with active tool-call context and invites further growth unless a ceiling exists.

5. **Feature activation opacity.** CLAUDE.md lists F05–F34. For each, default-state (enabled/disabled/conditional) is scattered across per-feature docs. There is no single table, and there is no link between the feature catalog and actual usage. Nothing flags features that have not fired in any run for 90+ days.

## Non-Goals

- **Not** changing the 48-agent roster. No agent is added or removed.
- **Not** rewriting any skill's behavior. The only skill deletion is `/forge-help`; the only skill change is `/forge-verify` losing `--config` and `/forge-status` gaining absorbed output.
- **Not** aggressive size-cutting of `fg-100`. Budget is about growth management, not surgery.
- **Not** introducing a module for "feature lifecycle management." The matrix and lifecycle doc are prose + a generator, not a subsystem.
- **Not** adding a new config section. All of this lives in existing files.

## Approach

Five components land in the order specified under Migration / Rollout to avoid a commit where CI would fail. Each component is an edit to existing content plus at most one new Python contract test and at most one new shared doc.

## Components

### 1. `ui:` frontmatter required contract

**Rule.** Every file matching `agents/fg-*.md` MUST contain a top-level frontmatter key `ui:` whose value is a mapping with exactly the keys `tasks`, `ask`, `plan_mode`, each a boolean. Extra keys are rejected. Flow-style (`ui: { tasks: false, ask: false, plan_mode: false }`) and block-style are both accepted; the existing consistency test already handles both.

**Tier assignment for the 13 missing agents.** All land as Tier 4 (`tasks: false, ask: false, plan_mode: false`) matching their registry rows in `shared/agents.md` lines 113–126 and 334–355. Explicitly:

- `fg-101-worktree-manager`, `fg-102-conflict-resolver` — Tier 4.
- `fg-205-planning-critic` — Tier 4 (silent adversarial reviewer per `agents/fg-205-planning-critic.md:4`).
- `fg-410` through `fg-419` (all nine reviewers) — Tier 4.
- `fg-510-mutation-analyzer` — Tier 4.

No tier is changed; the registry and ui-tier sections already agree on Tier 4 for all 13.

**New test.** `tests/contract/ui_frontmatter_required.py` (pytest). For each `agents/fg-*.md`:

1. Parse frontmatter (first `---`-delimited YAML block) with `pydantic.BaseModel`. `pydantic` is the idiomatic choice in 2026 (broad ecosystem, type-hint-native; `strictyaml` has seen no releases since 2022 and its "Norway problem" stance is not needed here because our inputs are authored, not user-supplied). **`pydantic` is not currently a Forge dep** — `pyproject.toml` only declares `opentelemetry-*` and `jsonschema` under `[project.optional-dependencies].otel`, and `check_prerequisites.py` imports nothing from pydantic. This phase introduces pydantic as a **new test-only dep**. Specifically: add a `test` extras group to `pyproject.toml` (`[project.optional-dependencies].test = ["pydantic>=2.0", "pyyaml>=6.0", "pytest>=8.0"]`) and add the same three packages to the CI workflow's `pip install` step before `pytest` runs. `pyyaml` is explicit because the Python stdlib has no YAML parser and pydantic v2 does not pull it as a transitive dep.
2. Validate against a strict model:

   ```python
   class UiBlock(BaseModel, extra="forbid"):
       tasks: bool
       ask: bool
       plan_mode: bool

   class AgentFrontmatter(BaseModel, extra="allow"):
       name: str
       ui: UiBlock
   ```
3. Missing `ui:`, wrong types, or extra keys under `ui:` → test fails with the offending file path and reason.

### 2. Skill grammar + contract test

**Grammar (canonical, new doc `shared/skill-grammar.md`).**

- **Inspection / read-only skills** use flags only. Examples: `/forge-status`, `/forge-verify`, `/forge-ask`, `/forge-history`, `/forge-insights`, `/forge-profile`, `/forge-playbooks`. No subcommands permitted.
- **Multi-action (mutating) skills** use subcommands only. Examples: `/forge-graph init | rebuild | status | query | debug`, `/forge-recover diagnose | repair | reset | resume | rollback | rewind | list-checkpoints`, `/forge-compress agents | output | status | help`, `/forge-handoff ` (bare) `| list | show | resume | search`.
- **Positional args are forbidden except where the arg is free-form content.** Exactly two cases qualify: a Cypher query (`/forge-graph query "<cypher>"`) and a requirement string (`/forge-run "<requirement>"`, `/forge-fix "<description>"`). Positional "mode" tokens (`/forge-compress output full`) are rewritten as `--mode=full` in spec examples but the current behavior is preserved as a recognized form until the author of the skill decides to rename.
- **Every skill with subcommands must expose a `## Subcommands` section** listing each with a one-line purpose and a read-only/writes label. The existing `forge-recover`, `forge-compress`, and `forge-handoff` already conform; `forge-graph` needs its table promoted from prose.
- **`allowed-tools` frontmatter must list real tool names.** Unknown keys at the top level of SKILL.md frontmatter (e.g. the malformed `ui:` with missing `plan_mode` in `skills/forge-sprint/SKILL.md:16`) are rejected.

**New test.** `tests/contract/skill_grammar.py` (pytest). For each `skills/*/SKILL.md`:

1. Parse frontmatter with `pydantic`. Validate required keys: `name`, `description`, `allowed-tools`. Optional: `disable-model-invocation`, `ui` (flow-mapping with all three keys if present).
2. Classify skill by `description:` prefix — `[read-only]` or `[writes]`, per existing `shared/skill-contract.md:5`.
3. Read body headings. If body contains a `## Subcommands` heading, skill is subcommand-form; verify no `--mode=` style flags mix subcommand dispatch (flags are fine *inside* a subcommand, but the skill cannot both have `## Subcommands` and top-level mutually-exclusive flags like `--build | --config | --all`). Conversely, `[read-only]` skills may not contain a `## Subcommands` heading.
4. `allowed-tools` values must match the set known to Claude Code (loaded from `shared/skill-grammar.md` §Known Tools). **`shared/skill-grammar.md` MUST carry an explicit enumerated allow-set** — the initial list (derived from current skill frontmatter) is: `Read`, `Edit`, `Write`, `Glob`, `Grep`, `Bash`, `Task`, `TaskCreate`, `TaskUpdate`, `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode`, `Agent`, `WebFetch`, `WebSearch`, `neo4j-mcp`, `playwright-mcp`, `linear-mcp`, `slack-mcp`, `context7-mcp`, `figma-mcp`, `excalidraw-mcp`. Enforcement is two-tier: **warning** if a tool name appears that is not in the allow-set but is well-formed (likely a new plugin tool the grammar doc hasn't caught up with); **error** only for obvious typos — defined as mixed-case drift (e.g. `toolName`, `TOOLNAME`, or a close-match Levenshtein ≤ 2 to an allow-set entry). Net: the test fails the build only on typos; unknown-but-new tools emit `warnings.warn` so CI logs surface them without blocking.
5. Reject any frontmatter top-level key not in the allow-list: `{name, description, allowed-tools, disable-model-invocation, ui}`.

### 3. Skill overlap resolution

**Changes.**

- **`/forge-status`** becomes the single read-only inspection surface. Adds two sections to its Instructions: *"Config validation summary"* (the checks previously run by `/forge-verify --config`, emitted only when run without `--json` or under `--json` as a `config_validation` object) and *"Recent hook failures"* (last 5 entries from `.forge/events.jsonl` where `type == "hook_failure"`).
- **`/forge-verify`** drops `--config`. New flag matrix: `--build` (default), `--all` (runs `--build` then shells out to `/forge-status --json` for the config block and appends to its report), `--json`, `--help`. The `Subcommand: config` block in `skills/forge-verify/SKILL.md` is deleted; `Subcommand: all` is rewritten to delegate.
- **`/forge-recover diagnose`** remains but its Instructions get a new opening step: *"Run `/forge-status --json` and embed its output as the `state` field in the diagnose report."* It stops reading `.forge/state.json` directly; repair recommendations stay its sole responsibility.
- **`/forge-help`** is **deleted**. `skills/forge-help/` is removed. All references in:
  - `CLAUDE.md:15` (Start Here step 3 — rewritten to point at direct skill names).
  - `CLAUDE.md:121` (Skill selection guide row — removed).
  - `CLAUDE.md:137` (Getting started flows line — removed).
  - `CLAUDE.md:308` (Skills list — removed, count drops 29 → 28).
  - `shared/skill-contract.md:44` (header "Phase 5 baseline — 28 skills" unchanged; the count was already 28 prior to the forge-handoff addition — see Component 6 below).
  - `shared/skill-contract.md:46` (Read-only list — `forge-help` removed, count 10 → 9).
  - `README.md:136` (skill table row — removed).
  - `skills/forge-config/SKILL.md:94` (line `/forge-help — find the right skill` — removed).
  - `skills/forge-tour/SKILL.md:138` (line `**All skills:** /forge-help` — rewrite to point at the CLAUDE.md skill table).
  - `skills/forge-tour/SKILL.md:202` (line `/forge-help — full skill decision tree` — removed).
  - `tests/contract/skill-contract.bats:67` — remove `forge-help` from the literal skill-name list asserted in the read-only category.
  - `tests/lib/module-lists.bash:99` — remove the `forge-help` entry from the skills array (drops min skill count by 1).
  - `tests/structural/skill-consolidation.bats` — delete the three `forge-help` tests (`schema_version`, `total_skills 29`, Migration section); update the remaining `"total_skills":[[:space:]]*29` assertion to `28` anywhere it still appears. Per user memory `No backcompat`, this is a straight deletion — no shim, no opt-in.
  - `tests/structural/skill-descriptions.bats` — delete the four `forge-help` tests (tier-3 check, disambiguation section check, and any others that load `$SKILLS_DIR/forge-help/SKILL.md`).
  - `tests/unit/skill-execution/decision-tree-refs.bats` — this entire file tests the decision tree that only exists inside `/forge-help`. Delete the file outright (all seven tests — including `assert [ -f "$SKILLS_DIR/forge-help/SKILL.md" ]` — are moot once the skill is gone). If a replacement "file does NOT exist" assertion is wanted, `tests/contract/skill_inventory.py` (Component 3 below) already covers it.

  The justification (user memory `No self-review` / `LLM routing`) is recorded in the commit body, not in the docs themselves.

**Net skill count: 28.**

**Concurrent fix: `shared/skill-contract.md` is already stale.** The file declares `## 4. Skill categorization (Phase 5 baseline — 28 skills)` with Writes = 18 items, but `ls skills/` currently returns 29 entries because `forge-handoff` (added in 3.6.0) was never recorded in the contract. As part of this phase:

- Add `forge-handoff` to the **Writes** list in `shared/skill-contract.md:48` (the handoff skill is `[writes]` per its own SKILL.md description).
- Keep the header `Phase 5 baseline — 28 skills` — after deleting `forge-help` and adding `forge-handoff`, the total lands at exactly 28.
- Update the Writes count from "18" to "19" (adds `forge-handoff`).
- Update the Read-only count from "10" to "9" (removes `forge-help`).

### 4. fg-100-orchestrator size budget

**Ceiling.** Single-tier hard cap at 1800 lines (fail). Current 1557 sits comfortably below. No soft-warn tier per Open Question 1 resolution — pytest warnings are noise without PR-comment integration.

**New test.** `tests/contract/fg100_size_budget.py` (pytest). Counts lines in `agents/fg-100-orchestrator.md`. Emits:

- `<= 1800` → pass silently.
- `> 1800` → fail with message pointing at `shared/agent-philosophy.md` authoring rule.

**Authoring rule (recorded in `shared/agent-philosophy.md`).** Before adding a section to fg-100, check whether the content is generic agent guidance. If yes, put it in `shared/agent-defaults.md` and reference from fg-100 by prose link (e.g., *"Reviewer timeout handling: see agent-defaults.md §Timeout → INFO-to-WARNING"*). If no, add inline. This is growth management, not aggressive cutting.

### 5. Feature activation matrix + lifecycle

**New file `shared/feature-matrix.md`.** Structure:

```
# Feature Activation Matrix

<!-- FEATURE_MATRIX_START -->
| ID | Feature | Default | Last-30d Usage |
|----|---------|---------|----------------|
| F05 | Living specifications | conditional (living_specs.enabled) | unknown |
| ... (one row per F05..F34, 30 rows) ...
<!-- FEATURE_MATRIX_END -->
```

The fenced block is *the entire contents* that the generator rewrites. Everything above and below (headers, prose, deprecation path pointer to `shared/feature-lifecycle.md`) is hand-authored and immutable. **Sentinel contract:** the generator matches the exact literal byte strings `<!-- FEATURE_MATRIX_START -->` and `<!-- FEATURE_MATRIX_END -->`, each on its own line with a trailing newline, no surrounding whitespace variations. Missing either sentinel → generator exits 2 with `feature-matrix.md missing required sentinel comment`. Sentinels appear exactly once each.

**Generator `shared/feature_matrix_generator.py`** (Python, cross-platform, no bash).

- Reads the authoritative feature list from a constant `FEATURES` dict at the top of the script (ID → human name → default semantic). The dict is the source of truth; a comment points to CLAUDE.md §Features table for cross-reference.
- Connects to `.forge/run-history.db` (SQLite), runs one query: `SELECT feature_id, COUNT(*) FROM feature_usage WHERE ts >= datetime('now', '-30 days') GROUP BY feature_id`.
- Builds one table row per feature. Default column copied from the dict. Usage column is an integer or the literal string `unknown` (never an em dash or en dash — ASCII hyphen-minus only, Unicode-free).
- Rewrites the content between the two sentinel comments in `shared/feature-matrix.md`. Deterministic: sorts by feature ID ascending, stable formatting (pipe-aligned), trailing newline.
- **Error handling.** If `.forge/run-history.db` is missing, unreadable, or lacks the `feature_usage` table: every usage cell is `unknown` and the generator exits 0. If the DB is present but the query returns zero rows for a feature: cell is `0`.

**CI freshness check.** A new CI job runs `python shared/feature_matrix_generator.py && git diff --exit-code shared/feature-matrix.md`. Non-zero diff fails the build with guidance to run the generator locally.

**Dead-feature culling doc `shared/feature-lifecycle.md`.** Three-state lifecycle:

1. **Active** — any run in the last 90 days.
2. **Flagged** — zero runs for ≥90 days. Generator emits a `<!-- FLAGGED -->` marker after the usage column. No automatic action.
3. **Candidate for removal** — zero runs for ≥180 days. A separate CI job (`shared/feature_deprecation_check.py`) opens a PR titled `chore(features): propose removal of F{id}` with a generated diff removing the feature's config section, docs row, and agents' conditional gates. Human merge required.

The `feature_usage` table requirements are documented in this file (columns: `feature_id TEXT`, `ts DATETIME`, `run_id TEXT`). `fg-700-retrospective` is the writer; migration `002-feature-usage.sql` lands under `shared/run-history/migrations/` as part of Component 5.

## Contract Tests (What Fails CI)

| Test file | Fails when |
|---|---|
| `tests/contract/ui_frontmatter_required.py` | Any `agents/fg-*.md` lacks a `ui:` block, or `ui:` is missing any of `tasks`/`ask`/`plan_mode`, or has non-bool values, or has extra keys. |
| `tests/contract/skill_grammar.py` | Any `skills/*/SKILL.md` has unknown frontmatter top-level key; unknown `allowed-tools` entry; read-only skill with `## Subcommands` section; skill whose `description:` badge conflicts with mutating subcommands; `allowed-tools` value that is not a known Claude Code tool. |
| `tests/contract/fg100_size_budget.py` | `wc -l agents/fg-100-orchestrator.md` > 1800. (Single-tier — no warn-at-1600, per Open Question 1 resolution.) |
| `tests/contract/feature_matrix_freshness.py` | Running `shared/feature_matrix_generator.py` produces a diff in `shared/feature-matrix.md`. |
| `tests/contract/skill_inventory.py` *(new)* | Skill count != 28, or `forge-help` still exists under `skills/`, or references to `/forge-help` remain in `CLAUDE.md` / `README.md` / `shared/skill-contract.md`. (There is no prior file by this name — grep for `skill_inventory` in `tests/` returns zero hits. This is a greenfield contract test.) |

## Data / File Layout

**New files.**

- `tests/contract/ui_frontmatter_required.py`
- `tests/contract/skill_grammar.py`
- `tests/contract/fg100_size_budget.py`
- `tests/contract/feature_matrix_freshness.py`
- `tests/contract/skill_inventory.py`
- `shared/skill-grammar.md`
- `shared/feature-matrix.md`
- `shared/feature-lifecycle.md`
- `shared/feature_matrix_generator.py`
- `shared/feature_deprecation_check.py`
- `shared/run-history/migrations/002-feature-usage.sql`

**Deleted files.**

- `skills/forge-help/SKILL.md`
- `skills/forge-help/` (directory)

**Edited files.**

- 13 agent files listed in Component 1: add `ui: { tasks: false, ask: false, plan_mode: false }` immediately after `tools:` (or after `color:` where already present).
- `skills/forge-sprint/SKILL.md`: fix the malformed frontmatter — the `ui:` line becomes `ui: { tasks: true, ask: true, plan_mode: false }`.
- `skills/forge-verify/SKILL.md`: remove `--config` subcommand block and flag; rewrite `--all` to delegate to `/forge-status --json`.
- `skills/forge-status/SKILL.md`: add config-validation and hook-failure sections to Instructions.
- `skills/forge-recover/SKILL.md`: rewrite diagnose subcommand to embed `/forge-status --json` output.
- `CLAUDE.md`: edits at lines 15, 121, 137, 308; new §Feature Matrix pointer to `shared/feature-matrix.md`.
- `README.md:136`: remove `/forge-help` row.
- `shared/skill-contract.md:46`: remove `forge-help`, update count.
- `shared/agents.md:19`: no change (the rule it declares is now enforced; wording is already correct).
- `shared/agent-philosophy.md`: add one-paragraph authoring rule for fg-100 growth.

## Migration / Rollout

Order matters — contract tests cannot land in the same commit as the content they check, because intermediate CI on the feature branch would fail. Five commits, in order:

1. **Commit 1 — Add `ui:` blocks to 13 agents + fix forge-sprint frontmatter.** Content-only. CI remains green (no new test yet). Also adds the `ui:` block to any agent that already has it consistently (no-op check).
2. **Commit 2 — Delete `/forge-help` + all reference updates + forge-verify/forge-status/forge-recover skill edits.** CI remains green (skill_inventory.py amendment lands in commit 5).
3. **Commit 3 — Land `shared/skill-grammar.md`, `shared/feature-matrix.md` (initial hand-generated content with all rows `unknown`), `shared/feature-lifecycle.md`, `shared/feature_matrix_generator.py`, `shared/feature_deprecation_check.py`, `shared/run-history/migrations/002-feature-usage.sql`. Amend `fg-700-retrospective.md` to write `feature_usage` rows.** Generator is idempotent on an empty DB.
4. **Commit 4 — Authoring rule in `shared/agent-philosophy.md`.** Docs-only.
5. **Commit 5 — Land all five contract tests simultaneously.** This is the gate. If any previous commit regresses, this commit fails CI and the fix is a forward commit (per user memory `No backcompat`; no revert/shim).

No state migration. `.forge/run-history.db` rows with no `feature_usage` table simply report `unknown` until migration 002 is applied on the next retrospective run.

**Cross-phase constraint.** The Commit-5 contract test (`ui_frontmatter_required.py`) uses a deliberately wide glob: `agents/fg-*.md`. Any agent added by Phases 3–8 (including `fg-540` and `fg-302` planned in Phase 7) MUST ship with an explicit `ui:` block that has exactly the three boolean keys `tasks`, `ask`, `plan_mode`. If Phase 7 lands between Phase 2 Commit 4 and Commit 5 on the same branch, CI will still pass because the test doesn't exist yet; but once Phase 2 Commit 5 merges, any new agent added in later phases without a `ui:` block will turn the branch red. Phase 7's spec is hereby required to include `ui:` blocks for `fg-540-*` and `fg-302-*` (or whatever final names they take) at the moment the files are authored — no retrofit commit.

## Error Handling

- **`ui_frontmatter_required.py`** on malformed YAML: prints `<path>: frontmatter parse error: <msg>` and fails. No silent skipping.
- **`skill_grammar.py`** on unreadable SKILL.md: fails the specific file, continues iterating so the report lists every offender per run.
- **`feature_matrix_generator.py`** on missing DB: returns all `unknown`, exits 0. On unreadable DB (permissions): prints error to stderr, exits 0 (CI freshness check will still pass because the file is deterministic under the missing-DB path). On corrupted DB (sqlite error mid-query): prints error, exits 1.
- **`fg100_size_budget.py`** on missing orchestrator file: fails immediately (the file is load-bearing).
- **Feature deprecation PR** failure to open: CI job warns and exits 0; manual follow-up.

## Testing Strategy

All tests run in CI only. No local test runs per user memory `No local tests`. Test harness:

- All new tests use pytest (`tests/contract/*.py`).
- Existing `.bats` contract tests stay as-is; new additions are Python-only.
- **`pyproject.toml` currently scopes pytest discovery to `testpaths = ["tests/unit"]`.** Without change, the new `tests/contract/*.py` files would never be discovered. This spec requires updating `pyproject.toml` to `testpaths = ["tests/unit", "tests/contract"]` as part of the commit that lands the generator (Component 5 / Commit 3 — safe because no Python contract tests exist yet) or the test-landing commit (Commit 5 — acceptable too, since the tests arrive in the same commit as their discovery wiring).
- Add a `test` extras group to `pyproject.toml`: `[project.optional-dependencies].test = ["pydantic>=2.0", "pyyaml>=6.0", "pytest>=8.0"]`. The CI workflow installs via `pip install -e ".[test]"` (or equivalent). `pydantic` is picked per Component 1; `pyyaml` is explicit because stdlib has no YAML parser.
- `tests/run-all.sh` needs one line: invoke `python -m pytest tests/contract -q` after the existing bats-structural pass, so the single `run-all.sh` entry point still gates the full suite.
- Minor concurrent fix: `pyproject.toml` `version = "3.4.0"` is stale (plugin is 3.6.0 per `plugin.json`). Bump to `3.6.0` in the same commit that edits `testpaths` — opportunistic since this phase already touches the file.

Pipeline-level evals (`tests/evals/pipeline/`) are unaffected.

## Documentation Updates

**`CLAUDE.md`:**

- Line 15: Remove the `/forge-help` mention in the 5-minute path. Rewrite step 3 to: *"Pick the right skill: bug? `/forge-fix`. Quality check? `/forge-review --full`. Multiple features? `/forge-sprint`. Full table below."*
- Line 121: Remove the *Find the right skill* row.
- Line 137: Remove the *Quick decision* line from the getting-started flows.
- Line 308: Rewrite Skills list — drop `forge-help`, note count 28, update `forge-verify` to drop `--config`, note `forge-status` absorbs config validation.
- New pointer in the Features section: *"See `shared/feature-matrix.md` for current activation state and 30-day usage."*

**`README.md:136`:** Remove the forge-help row; renumber nothing (table has no row numbers).

**`shared/skill-contract.md:46`:** Remove `forge-help` from the read-only list; count 10 → 9. Add a pointer to `shared/skill-grammar.md` in a new §6 paragraph.

**`shared/agents.md`:** No text change to line 19 — its assertion is now true. Optionally add a backlink to the contract test: `(enforced by tests/contract/ui_frontmatter_required.py)`.

**`shared/agent-philosophy.md`:** Add authoring rule for fg-100 growth (Component 4).

**No changes to** per-agent `.md` files beyond the 13 listed and fg-100 (none; size rule is external). No changes to `shared/agent-ui.md`, `shared/agent-communication.md`, or `shared/agent-defaults.md` beyond eventual migrations authors may choose under the new growth rule.

## Acceptance Criteria

- **AC-1.** `pytest tests/contract/ui_frontmatter_required.py` passes against the repo at HEAD of commit 5. All 48 agents carry explicit `ui:` blocks with exactly the three boolean keys.
- **AC-2.** `pytest tests/contract/skill_grammar.py` passes. Exactly 28 skills exist under `skills/`. No skill frontmatter has unknown top-level keys. `skills/forge-sprint/SKILL.md` parses cleanly.
- **AC-3.** `pytest tests/contract/fg100_size_budget.py` passes at 1557 lines. Single-tier gate — no warnings emitted at any line count below 1800.
- **AC-4.** `python shared/feature_matrix_generator.py` is idempotent: running it twice in succession produces zero diff on the second run. `git diff --exit-code shared/feature-matrix.md` returns 0.
- **AC-5.** `grep -rn 'forge-help' CLAUDE.md README.md shared/` returns zero matches (excluding `shared/feature-lifecycle.md` example text, which uses `forge-example` placeholders).
- **AC-6.** `skills/forge-status/SKILL.md` contains both a `## Config validation summary` section and a `## Recent hook failures` section. A contract test (`tests/contract/skill_grammar.py` or a structural bats) asserts both headings are present. (Skills are markdown prompts, not executables; CI cannot dispatch them, so the gate is structural, not runtime.)
- **AC-7.** `skills/forge-verify/SKILL.md` does NOT mention `--config` anywhere (no subcommand block, no flag in the allowed-tools hint, no example). A contract test asserts the recognized flag set is exactly `{--build, --all, --json, --help}`. (Same rationale as AC-6: no CI job invokes a skill.)
- **AC-8.** `shared/feature-matrix.md` contains 30 rows (F05 through F34) between the sentinel comments, each with a non-empty Default cell and a Usage cell that is either an integer or the literal `unknown`. No em dashes, en dashes, or smart quotes (U+2018, U+2019, U+201C, U+201D) anywhere in the generated content. ASCII-only between sentinels.
- **AC-9.** `shared/feature-lifecycle.md` defines the 90/180-day thresholds and the three lifecycle states exactly as in Component 5.
- **AC-10.** `tests/run-all.sh contract` returns exit 0 and includes pytest output for all five new `tests/contract/test_*.py` files: `test_ui_frontmatter_required.py`, `test_skill_grammar.py`, `test_fg100_size_budget.py`, `test_feature_matrix_freshness.py`, and `test_skill_inventory.py`.

## Open Questions

1. ~~**fg-100 budget enforcement on PRs, not push?**~~ **Resolved: dropped warn tier.** Without PR-comment integration, a pytest `warnings.warn` is noise in CI logs that nobody reads. The budget is now single-tier: `> 1800` fails, anything ≤ 1800 passes silently. Component 4 and its contract test are updated accordingly: delete the `warnings.warn` branch from `fg100_size_budget.py`; collapse Component 4's three-outcome list to just pass/fail at the 1800 threshold.
2. **`feature_usage` emission point.** Putting writes in `fg-700-retrospective` means features used in a run that aborts before LEARN are undercounted. Alternative: emit at stage entry from the orchestrator into `.forge/events.jsonl` and aggregate at retrospective. Recommendation: orchestrator emits events; retrospective aggregates into the DB. This is a Component-5 implementation detail, not a spec change.
3. **Skill grammar `positional mode` exception.** `/forge-compress output full` still flows as positional-after-subcommand. The grammar tolerates this but does not love it. Should a later phase rewrite these as `--mode=`? Recommendation: leave it. The grammar permits it and the skill is not being rewritten.
4. **Python dep surface.** Adding pydantic to CI is fine; does it belong in any runtime path? Only contract tests need it; runtime hooks remain dependency-free. No action.
5. **What about agents not matching `fg-*.md`?** There are none currently. If a future naming convention appears, the test's glob (`agents/fg-*.md`) must be updated or broadened. Recommendation: the test glob is narrow by design; a broader glob is a follow-up if and when the roster expands.
