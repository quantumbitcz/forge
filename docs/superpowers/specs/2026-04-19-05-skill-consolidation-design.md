# Phase 05 — Skill Consolidation 35 → 28

**Date:** 2026-04-19
**Priority:** P1
**Status:** Design
**Owner:** forge plugin (quantumbitcz)

---

## 1. Goal

Reduce the forge plugin skill surface from 35 top-level skills to 28 by collapsing three overlapping clusters into git-style subcommand skills, while simplifying the `/forge-help` decision tree to match.

---

## 2. Motivation

The A+ audit **finding W5 (decision paralysis)** flagged that users stall when choosing between `/forge-review`, `/forge-codebase-health`, and `/forge-deep-health` — the distinction is a mode flag, not a separate concept. The graph cluster (`/forge-graph-{init,status,query,rebuild,debug}`) exposes five top-level skills for one subsystem; this is the inverse of the `git remote (add|rm|list)` idiom that users already understand. And `/forge-verify` vs `/forge-config-validate` are two tiny pre-flight checks that a user has to pick between before they know what either does.

Anthropic's Claude Code skill authoring guidance (https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) explicitly favors **fewer, composable surfaces** with progressive disclosure inside the SKILL.md body over many narrow top-level skills. Subcommand dispatch satisfies both concerns: the top-level skill count shrinks, but every capability remains reachable through a predictable `/<skill> <subcommand> [--flags]` pattern that mirrors `git`, `kubectl`, `docker`, and `gh`.

The audit also re-affirms skills we must **not** merge:
- `fg-205-planning-critic` stays separate from `fg-210-validator` — adversarial planning and GO/REVISE/NO-GO validation are distinct value centers.
- `/forge-playbooks` (read) and `/forge-playbook-refine` (write) already have clean role separation.

---

## 3. Scope

### In

Three consolidations:

1. **Review cluster** — `/forge-review` + `/forge-codebase-health` + `/forge-deep-health` → `/forge-review --scope=changed|all [--fix] [--dry-run]`.
2. **Graph cluster** — `/forge-graph-{init,status,query,rebuild,debug}` → `/forge-graph <init|status|query|rebuild|debug>`.
3. **Verify cluster** — `/forge-verify` + `/forge-config-validate` → `/forge-verify [--build|--config|--all]`.

Also in scope:
- Delete the old skill directories (`skills/forge-codebase-health/`, `skills/forge-deep-health/`, `skills/forge-graph-{status,query,rebuild,debug}/`, `skills/forge-config-validate/`).
- Update the unified skill bodies with subcommand dispatch sections.
- Update the `/forge-help` decision tree and the `CLAUDE.md` §Skills (currently lists 35).
- Add `shared/skill-subcommand-pattern.md` documenting the standard arg-parsing pattern.
- Update `/forge-help --json` envelope: `total_skills: 28` and restructure cluster entries.
- Update structural test lists (`tests/lib/module-lists.bash` or equivalent) to expect 28 skills with the new names.

### Out

- Merging `fg-205-planning-critic` into `fg-210-validator` (audit establishes this separation has value).
- Merging `/forge-playbooks` with `/forge-playbook-refine` (distinct read/write roles).
- Any change to agent count, pipeline stages, or subagent contracts.
- Backwards-compatible aliases or stub redirects (see §7).
- Any change to `.forge/` state schema, `forge-config.md`, or scoring — these clusters are pure user-facing surfaces.

---

## 4. Architecture

### 4.1 Subcommand dispatch inside a single SKILL.md

Each unified skill follows one consistent pattern, documented once in `shared/skill-subcommand-pattern.md` and referenced from every consolidated SKILL.md:

```
## Subcommand dispatch

1. Read `$ARGUMENTS`.
2. Split into tokens: `SUB="$1"; shift; REST="$*"`.
3. If `$SUB` is empty OR `$SUB` matches `-*` (a flag, not a subcommand):
     → treat as the default subcommand (skill-specific; see table below).
4. If `$SUB == --help` OR `$SUB == help`:
     → print usage block and exit 0.
5. If `$SUB` is in the subcommand allow-list: dispatch to the matching
   "### Subcommand: <name>" section with `$REST` as its arguments.
6. Otherwise: print
     Unknown subcommand '<SUB>'. Valid: <list>. Try /<skill> --help.
   and exit 2 (invalid arguments).
```

**Default subcommand per skill:**

| Skill | Default subcommand | Rationale |
|---|---|---|
| `/forge-review` | `changed` (i.e. `--scope=changed`, `--fix` on) | Matches the old `/forge-review` default and preserves "quick feedback on what I just wrote" muscle memory. |
| `/forge-graph` | none — argument is required | There is no single "do the right thing" for the graph; requiring an explicit subcommand prevents accidental `rebuild`. |
| `/forge-verify` | `build` (commands build+lint+test) | Matches the old `/forge-verify` default. `--config` and `--all` must be explicit. |

The skill body holds ONE `## Subcommand dispatch` section at the top, followed by one `### Subcommand: <name>` section per subcommand. Each subcommand section owns its own Prerequisites, Instructions, Error Handling, and Exit codes — the material that previously lived in the separate SKILL.md files is reorganized under these headings, not rewritten. The existing hard content (agent dispatch logic for review, Neo4j state machine for graph, YAML validation for verify) is preserved verbatim in its respective subcommand section.

### 4.2 Arg parsing

A single shell helper, documented in `shared/skill-subcommand-pattern.md`, handles arg parsing uniformly:

```bash
parse_args() {
  SUB=""
  FLAGS=()
  POSITIONAL=()
  for tok in "$@"; do
    case "$tok" in
      --help|-h) echo "__HELP__"; return 0 ;;
      --*) FLAGS+=("$tok") ;;
      *)   if [ -z "$SUB" ]; then SUB="$tok"; else POSITIONAL+=("$tok"); fi ;;
    esac
  done
}
```

This helper is inlined (not sourced) into each consolidated SKILL.md so skills remain self-contained — the Claude Code skill runtime reads one `.md` and expects to find all logic there. `shared/skill-subcommand-pattern.md` is pure documentation / contract; it is not loaded at runtime.

Flag semantics (per-skill):

- `/forge-review --scope=changed|all` — required explicit value. `--fix` is a boolean; default ON for `changed`, default OFF for `all` (preserves the read-only contract the old `/forge-codebase-health` gave and the fix contract `/forge-deep-health` gave). `--dry-run` previews without writing, consistent with the current review skill.
- `/forge-graph <sub>` — subcommand is positional; flags `--dry-run`, `--help` pass through; `query` additionally accepts a positional Cypher string.
- `/forge-verify --build|--config|--all` — mutually exclusive; `--all` runs both. Default (no flag) = `--build`.

### 4.3 /forge-help listing

`/forge-help` gets a new ASCII decision tree that is at most **3 branches deep** (success criterion §11):

```
What do you want to do?

├── Build something
│   ├── New feature ................. /forge-run
│   ├── Fix a bug ................... /forge-fix
│   ├── Refine a vague idea ......... /forge-shape
│   └── Scaffold a new project ...... /forge-bootstrap
│
├── Check quality
│   ├── Just my recent changes ...... /forge-review             (default: --scope=changed --fix)
│   ├── The whole codebase (read) ... /forge-review --scope=all
│   ├── The whole codebase (fix) .... /forge-review --scope=all --fix
│   ├── Build + lint + test ......... /forge-verify             (default: --build)
│   ├── Config is correct ........... /forge-verify --config
│   └── Security scan ............... /forge-security-audit
│
├── Work with the knowledge graph
│   └── /forge-graph <init|status|query|rebuild|debug>
│
├── Ship / deploy / commit
│   ├── Deploy ...................... /forge-deploy
│   └── Conventional commit ......... /forge-commit
│
├── Pipeline control
│   ├── Status ...................... /forge-status
│   ├── Abort ....................... /forge-abort
│   ├── Recover ..................... /forge-recover <diagnose|repair|reset|resume|rollback>
│   └── Profile a run ............... /forge-profile
│
├── Know the codebase / history
│   ├── Ask a question .............. /forge-ask
│   ├── Run history ................. /forge-history
│   └── Insights .................... /forge-insights
│
└── Configure / automate / compress
    ├── Edit config ................. /forge-config
    ├── Automations ................. /forge-automation
    ├── Playbooks (list) ............ /forge-playbooks
    ├── Playbooks (refine) .......... /forge-playbook-refine
    ├── Compress .................... /forge-compress <agents|output|status|help>
    ├── Docs generate ............... /forge-docs-generate
    └── Migration ................... /forge-migration

New to forge? → /forge-tour
First setup?  → /forge-init
```

Depth check: the deepest path is `root → category → item`, which is 3. Every subcommand is one step inside its skill, not a fourth tree branch.

### 4.4 Alternatives considered

**A. Keep all 35 skills separate.** Status quo. Rejected because W5 decision paralysis is real user feedback (see §2), and five graph skills for one subsystem is architecturally wrong — they share state, prereqs, and conceptual surface.

**B. Consolidate via aliases only (keep old skills as 1-line redirects).** Every old skill becomes a stub that re-invokes the new one with the right subcommand. Rejected because:
- It does not actually reduce the surface — `/forge-help` still has to list 35 entries or consciously hide 7, and users who scroll through `skills/` see 35 directories.
- Stubs become a maintenance tax (every time a subcommand gains a flag, the stubs have to track it or lie).
- The user requirement is explicit: "No backwards compatibility. No stubs or aliases."

**C. Chosen: native subcommand dispatch inside one SKILL.md per cluster, hard-delete old skills.** Minimal maintenance overhead; matches git/kubectl idiom; makes `/forge-help` genuinely simpler; enforced by structural tests that count exactly 28 skill directories.

---

## 5. Components

### 5.1 Cluster 1 — Review (`/forge-review`)

**New unified `skills/forge-review/SKILL.md`:**

- Frontmatter:
  - `name: forge-review`
  - `description: "[writes unless --scope=all without --fix] Quality review for changed files or the whole codebase. Use when reviewing staged work before commit, auditing the codebase against conventions, or iteratively fixing all quality issues. Subcommands via flags: --scope=changed|all, --fix, --dry-run."`
  - `allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent']`
- Subcommand dispatch section at the top (per §4.1).
- Three behavioral modes mapped from the old skills:
  - `--scope=changed --fix` (default) = today's `/forge-review` (review + fix loop on changed files; quick=3 agents, `--full` optional).
  - `--scope=all` (no `--fix`) = today's `/forge-codebase-health` (read-only check engine scan over the whole tree, report saved to `.forge/health-report.md`).
  - `--scope=all --fix` = today's `/forge-deep-health` (iterative review-fix-commit loop, max 5 iterations, respects `max_iterations` / `pass_threshold` from `forge-config.md`).
- Body preserves the existing review-fix-verify loop, the `.forge/caveman-mode` terse-mode branch, the agent dispatch table, the commands config honoring, and the "Do NOT create PRs, tickets, or state files" rule — these are moved verbatim under the relevant subcommand section. Content from `forge-deep-health/SKILL.md` §7 (per-iteration commit) lives under `### Subcommand: changed --fix` (commit OFF, still no commits per old behavior) and `### Subcommand: all --fix` (commit ON, one per iteration).
- Respects existing `forge-config.md` review section: `max_iterations`, `pass_threshold`, `autonomous`, `convergence.oscillation_tolerance`, `quality_gate.*`. No new config keys.

**Files deleted:**
- `skills/forge-codebase-health/SKILL.md` and its directory.
- `skills/forge-deep-health/SKILL.md` and its directory.

**Count change:** 3 skills → 1 skill (−2).

### 5.2 Cluster 2 — Graph (`/forge-graph`)

**New unified `skills/forge-graph/SKILL.md`:**

- Frontmatter:
  - `name: forge-graph`
  - `description: "[writes for init/rebuild, read-only for status/query/debug] Manage the Neo4j knowledge graph. Subcommands: init (launch + build), status (health + coverage), query <cypher>, rebuild (regenerate project graph), debug (diagnose anomalies). Requires Docker."`
  - `allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent']`
- Subcommand dispatch required (no default — §4.1).
- Five `### Subcommand:` sections (`init`, `status`, `query`, `rebuild`, `debug`), each preserving the existing body of the corresponding old SKILL.md: container-name resolution, idempotency checks, seed import, `.forge/graph/.last-build-sha` logic, Cypher pass-through, health polling.
- The shared "Prerequisites" material (forge.local.md exists, `graph.enabled: true`, Docker available) is factored once at the top of the SKILL body and referenced by each subcommand section.

**Files deleted:**
- `skills/forge-graph-init/SKILL.md` becomes `skills/forge-graph/SKILL.md` (rename the directory).
- `skills/forge-graph-status/SKILL.md` and its directory.
- `skills/forge-graph-query/SKILL.md` and its directory.
- `skills/forge-graph-rebuild/SKILL.md` and its directory.
- `skills/forge-graph-debug/SKILL.md` and its directory.

**Count change:** 5 skills → 1 skill (−4).

### 5.3 Cluster 3 — Verify (`/forge-verify`)

**New unified `skills/forge-verify/SKILL.md`:**

- Frontmatter:
  - `name: forge-verify`
  - `description: "[read-only] Pre-pipeline checks. --build runs configured build+lint+test. --config validates forge.local.md and forge-config.md against PREFLIGHT constraints. --all does both. Defaults to --build."`
  - `allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']`
- Subcommand dispatch section with default = `build`.
- Two `### Subcommand:` sections:
  - `build` — today's `/forge-verify` body verbatim (commands.build / commands.lint / commands.test sequential, stop on first fail, UNKNOWN verdict if nothing configured).
  - `config` — today's `/forge-config-validate` body verbatim (required-field table, value-range checks, file reference checks, command executability, cross-reference checks, delegation to `shared/validate-config.sh`).
  - `all` — invokes `config` first (fail-fast — a broken config means build results are meaningless), then `build`; combined report.

**Files deleted:**
- `skills/forge-config-validate/SKILL.md` and its directory.

**Count change:** 2 skills → 1 skill (−1).

### 5.4 New shared doc

**`shared/skill-subcommand-pattern.md`** (new, ~80 lines):
- Documents the exact arg-parsing helper from §4.2.
- Lists the contract: one `## Subcommand dispatch` section, one `### Subcommand: <name>` section per subcommand, default-subcommand convention, `--help` and `help` both valid, unknown subcommand → exit 2.
- Lists the three skills that follow the pattern today and notes that new multi-mode skills should adopt it (do not invent ad-hoc schemes).

### 5.5 /forge-help update

**`skills/forge-help/SKILL.md`:**
- Replace the three tier tables with the ASCII decision tree from §4.3.
- Update the "Similar Skills" table: remove now-merged pairs (`forge-review` vs `forge-codebase-health`, `forge-codebase-health` vs `forge-deep-health`) and replace with subcommand hints.
- Update `--json` output: `total_skills: 28`; the `advanced.knowledge_graph` list collapses to a single `forge-graph` entry with a `subcommands: [...]` array. Same for `forge-review` and `forge-verify`.

### 5.6 CLAUDE.md §Skills update

At `CLAUDE.md` line 274 (`## Skills (35 total), hooks, kanban, git`):
- Rename header to `## Skills (28 total), hooks, kanban, git`.
- Rewrite the `**Skills:**` paragraph to reflect the 28 skills, describing `/forge-review` with its `--scope` flag, `/forge-graph` with its five subcommands, and `/forge-verify` with `--build|--config|--all`.
- Remove the individual entries for `forge-codebase-health`, `forge-deep-health`, `forge-graph-status`, `forge-graph-query`, `forge-graph-rebuild`, `forge-graph-debug`, `forge-config-validate`.
- Update the Skill Selection Guide table earlier in CLAUDE.md (`/forge-review` row, the three Quality rows, the graph rows, the verify row) so the Skill column reflects the new subcommand form.

---

## 6. Data / State / Config

**No state schema changes.** The review skill still writes `.forge/health-report.md` (from `--scope=all`) and `.forge/forge-deep-health-report.md` (from `--scope=all --fix`); these paths are preserved for tooling that grep them. The graph skill still writes `.forge/graph/.last-build-sha` and updates `.forge/state.json.integrations.neo4j.available`. The verify skill remains read-only.

**No config schema changes.** `forge-config.md` keys consumed by the old skills (`max_iterations`, `pass_threshold`, `autonomous`, `convergence.oscillation_tolerance`, `quality_gate.*`, `graph.enabled`, `graph.neo4j_*`) are consumed verbatim by the new unified skills. The `/forge-review --fix` subcommand specifically continues to honor the existing review section of `forge-config.md`.

**No new config keys required for this phase.** The subcommand pattern is pure UX; there is nothing to toggle.

---

## 7. Compatibility

**HARD BREAKING — no backwards compatibility.** Per the user's explicit requirement:

- Old skill names (`/forge-codebase-health`, `/forge-deep-health`, `/forge-graph-status`, `/forge-graph-query`, `/forge-graph-rebuild`, `/forge-graph-debug`, `/forge-config-validate`) are removed. Claude Code skill discovery reads `skills/*/SKILL.md`; deleted directories mean the skills no longer exist.
- No stub files, no alias redirects, no tombstone SKILL.md entries.
- Users invoking a removed skill get the Claude Code runtime's standard "skill not found" error. To help the transition, we **add a single migration table to the top of `/forge-help`** (not stubs in each old directory) listing old → new mappings:

```
| Removed                 | Use instead                              |
|-------------------------|------------------------------------------|
| /forge-codebase-health  | /forge-review --scope=all                |
| /forge-deep-health      | /forge-review --scope=all --fix          |
| /forge-graph-status     | /forge-graph status                      |
| /forge-graph-query      | /forge-graph query <cypher>              |
| /forge-graph-rebuild    | /forge-graph rebuild                     |
| /forge-graph-debug      | /forge-graph debug                       |
| /forge-config-validate  | /forge-verify --config                   |
```

This table lives at the bottom of `/forge-help` under a `## Migration (Phase 05)` heading, slated for removal in the release after the next minor bump.

- All cross-references in `agents/*.md`, `shared/**/*.md`, `modules/**/*.md`, `hooks/**`, `tests/**`, and `CLAUDE.md` that mention a removed skill must be updated to the new form. A repo-wide grep is part of the plan's implementation.
- `/forge-help --json` bumps its implicit schema (the `total_skills` integer changes, and cluster entries gain a `subcommands` array). Downstream consumers of `--json` (the MCP server, `/forge-insights`) should be scanned; if any pin on the 35-skill count or on the old cluster shape, they need parallel updates in the same PR.

---

## 8. Testing Strategy

**CI-only — no local test execution.** Tests are added to the existing `tests/` harness and run on every PR via the standard CI workflow.

1. **Structural — skill count and names.** Extend `tests/structural/skills-exist.bats` (or add a new file) to assert:
   - Exactly 28 directories exist under `skills/`.
   - The 28 directory names are the expected post-consolidation list (check-in the list as a fixture, not computed).
   - None of the seven removed names exist as directories.
   - Each of the three consolidated skills (`forge-review`, `forge-graph`, `forge-verify`) contains a `## Subcommand dispatch` section.

2. **Structural — subcommand coverage.** For each consolidated skill:
   - `forge-review`: assert `### Subcommand: changed`, `### Subcommand: all` (or the flag-based equivalent headings) exist.
   - `forge-graph`: assert five `### Subcommand:` sections (`init`, `status`, `query`, `rebuild`, `debug`).
   - `forge-verify`: assert three `### Subcommand:` sections (`build`, `config`, `all`).

3. **Contract — `--help` exits 0.** For each consolidated skill, the `--help` path must be discoverable (section present in SKILL.md) and documented to exit 0. A lightweight test scans for `**--help**: print usage and exit 0` in the Flags section.

4. **Contract — `--dry-run` noted.** `forge-review` and `forge-graph` (which write) must both declare `--dry-run`. A structural test greps for the flag entry.

5. **Integration — `/forge-help` tree depth.** Parse the new `/forge-help` body; assert the decision tree's maximum nesting level is `<= 3`.

6. **Cross-reference — no dangling references.** Add a grep test that fails if any `.md` or `.bash` or `.json` file in the repo references `/forge-codebase-health`, `/forge-deep-health`, `/forge-graph-status`, `/forge-graph-query`, `/forge-graph-rebuild`, `/forge-graph-debug`, or `/forge-config-validate` *except* inside the `## Migration (Phase 05)` section of `/forge-help`.

7. **`tests/lib/module-lists.bash` update.** Bump/rename any `EXPECTED_SKILL_*` or `MIN_SKILLS` constants to `28` and update the expected-names array. This is the single place the count is asserted; downstream structural tests read from it.

All tests run under `./tests/run-all.sh structural` and `./tests/run-all.sh unit` on CI. **No local execution** — per project policy, verification happens in CI after push.

---

## 9. Rollout

**Single PR, simultaneous add-new + delete-old.** No staged rollout, no feature flag, no deprecation window. Because there is no backwards-compatibility requirement, a single atomic PR is cleaner than a multi-step migration.

PR contents:
1. New `shared/skill-subcommand-pattern.md`.
2. Rewritten `skills/forge-review/SKILL.md` with subcommand dispatch and all three behavioral modes.
3. Renamed `skills/forge-graph-init/` → `skills/forge-graph/` with merged SKILL.md.
4. Deleted directories: `skills/forge-codebase-health/`, `skills/forge-deep-health/`, `skills/forge-graph-status/`, `skills/forge-graph-query/`, `skills/forge-graph-rebuild/`, `skills/forge-graph-debug/`, `skills/forge-config-validate/`.
5. Rewritten `skills/forge-verify/SKILL.md` with subcommand dispatch.
6. Updated `skills/forge-help/SKILL.md` (new tree, new `--json`, migration table).
7. Updated `CLAUDE.md` §Skills header and listings, plus the Skill Selection Guide table.
8. Cross-reference sweep across `agents/`, `shared/`, `modules/`, `hooks/`, `tests/` to rewrite old skill names.
9. Updated `tests/lib/module-lists.bash` and any structural tests expecting the old count.
10. `plugin.json` stays at v3.x.0 with a minor bump (new feature — consolidation changes user-facing surface).
11. Release notes entry under "Breaking changes" listing the seven removed skill names and the mapping.

Rollback plan: single `git revert` on the merge commit restores the old structure. Because the change is orthogonal to pipeline state and config schema, there is nothing to migrate back.

---

## 10. Risks / Open Questions

**Risks:**

1. **Downstream consumers of `/forge-help --json`.** The MCP server (F30), `/forge-insights`, and anything else that reads the `--json` envelope will break if they pin on the 35 count or the old cluster shape. Mitigation: grep for `"total_skills"` and `forge-codebase-health` etc. across the repo; update in the same PR.
2. **User muscle memory for `/forge-deep-health`.** Long-time users type it reflexively; the unified form `/forge-review --scope=all --fix` is longer. Mitigation: the migration table in `/forge-help` and a one-line callout in the release notes. Consider adding an AUTO-COMPLETE hint if/when we add shell completions.
3. **Graph skill defaulting.** Requiring an explicit subcommand for `/forge-graph` means a bare `/forge-graph` prints help and exits 2 instead of "doing something". This is intentional (safer than rebuilding by default) but a departure from the review/verify skills' convenience default.
4. **Documentation churn.** Seven skill names are removed. Every reference across `agents/`, `shared/`, `modules/`, test fixtures, and release notes needs updating in lockstep or the structural cross-reference test will fail CI. This is mechanical but large — estimate 40–80 references.
5. **`--scope=all --fix` (the old deep-health) is destructive.** It commits per iteration. Today, this danger is somewhat obscured because the user has to deliberately pick `/forge-deep-health`. In the unified form, `all --fix` is one extra flag from the default. Mitigation: the skill must preserve the existing `autonomous: true` gate and the `--dry-run` short-circuit, and its `allowed-tools` still includes `Write/Edit/Bash`.

**Open questions:**

- Should `/forge-review --scope=all --fix` require a confirmation prompt when `autonomous: false`, matching the implicit "I typed the destructive skill name" confirmation that `/forge-deep-health` currently gets from simply existing? Proposed answer: **yes**, add a single `AskUserQuestion` gate before the first commit, unless `--yes` is passed or `autonomous: true` is set in config. This preserves the safety posture without adding a new config key.
- Should the `--help` output of each consolidated skill include an embedded migration hint for users who type the old name? Proposed: **no** — the old names no longer resolve at all, so they never reach the new skill's `--help`. The migration table in `/forge-help` is the single source.

---

## 11. Success Criteria

The phase is complete when ALL of these hold on `master` after merge:

1. **Skill count = 28.** `ls skills/ | wc -l` returns exactly 28.
2. **`/forge-help` tree ≤ 3 branches deep.** The ASCII tree has no path with more than three nested components (root → category → item).
3. **Every removed skill has a migration line** in `/forge-help`'s `## Migration (Phase 05)` table, and every row resolves to a valid new command.
4. **Zero dangling references.** The cross-reference CI test passes: no repo file (outside the migration table) mentions any removed skill name.
5. **Every consolidated skill has a `## Subcommand dispatch` section** matching `shared/skill-subcommand-pattern.md`.
6. **CI green.** `./tests/run-all.sh structural` and `./tests/run-all.sh unit` pass; all new/updated bats tests pass.
7. **`CLAUDE.md` §Skills header reads `(28 total)`** and the body lists 28 skills.
8. **`/forge-help --json` returns `total_skills: 28`.**
9. **No state/config schema change.** `.forge/` consumers (MCP server, insights, ask) keep working with no pipeline rerun.

---

## 12. References

- **Audit finding W5 — decision paralysis** (internal audit document, Phase 05 roadmap entry).
- **Anthropic Claude Code skill authoring best practices:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices — favors fewer, composable surfaces with progressive disclosure inside SKILL.md bodies.
- **`shared/skill-contract.md`** (existing) — standard skill contract, exit code table, flag conventions. Unchanged by this phase; the new `shared/skill-subcommand-pattern.md` complements it.
- **`CLAUDE.md` §Skills** (line 274) — existing 35-skill listing; updated by this phase.
- **Precedent idioms:** git subcommands (`git remote add`, `git stash pop`), kubectl verbs (`kubectl get pods`), gh (`gh pr create`) — all use the single-top-level-command + subcommand pattern this phase adopts.

---

**Arithmetic check** (§3 scope, cross-referenced in §11):
- Review cluster: 3 → 1 = **−2**
- Graph cluster: 5 → 1 = **−4**
- Verify cluster: 2 → 1 = **−1**
- Net: 35 − 2 − 4 − 1 = **28.** ✓
