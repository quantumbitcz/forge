# Phase 06 — Documentation Architecture Refactor

**Date:** 2026-04-19
**Phase:** 06 (A+ roadmap)
**Priority:** P1
**Status:** Design

---

## 1. Goal

Restructure `shared/` docs and `CLAUDE.md` to eliminate sprawl by splitting oversized files, merging overlapping agent docs into one canonical `shared/agents.md`, auto-generating a CI-validated `learnings-index.md`, introducing a formal `docs/adr/` directory seeded with 10+ historical ADRs, fixing the framework-count drift in `CLAUDE.md`, and adding a top-of-file "Start Here (5-minute path)" section.

---

## 2. Motivation

Audit finding **W6 — Documentation Sprawl** (2026-04-19 A+ audit). Concrete problems:

- **`shared/` is 119 items**: flat namespace, no index. New contributors can't find things; `/forge-ask` and the MCP server have to fall back to full-text search.
- **`CLAUDE.md` is 374 lines** (claims 330 — already drifting). Dense reference with no orientation path for first-time readers.
- **Framework-count drift**: `CLAUDE.md:16` claims 21 frameworks; `modules/frameworks/` has 23 entries (including `base-template.md` + `k8s`). Anyone copying the line for docs or metrics gets a wrong number.
- **Oversized files**: `shared/state-schema.md` 1236L, `shared/convergence-engine.md` 540L, `shared/agent-communication.md` 477L. Beyond comfortable LLM context or human reading in one pass.
- **Triplet overlap**: `agent-communication.md` (477L) + `agent-role-hierarchy.md` (161L) + `agent-registry.md` (76L) describe the same agent model from three vantage points with cross-pointing prose. Changes to one routinely drift from the others.
- **Dead file**: `shared/agent-consolidation-analysis.md` (62L) is a one-off 2025 analysis document never referenced by any agent or skill. It persists as clutter.
- **285 unindexed learnings** (`shared/learnings/*.md` — 287 entries counted including `README.md` and template). `/forge-ask` currently full-text-searches the directory. No table of contents. No freshness signal.
- **No ADRs**: major historical decisions (Neo4j choice, SQLite fallback, deterministic FSM, evidence-based shipping, 87-category scoring model, bash→Python tooling, no-backcompat stance) are embedded in `shared/*.md` prose or lost in commit messages. New maintainers cannot reconstruct *why* without archaeology.

No backwards compatibility; no local test execution; CI is the enforcement mechanism.

---

## 3. Scope

### In scope

- Split `shared/state-schema.md` (1236L) → `state-schema.md` (overview, ~200L) + `state-schema-fields.md` (exhaustive field reference).
- Reduce `shared/convergence-engine.md` (540L) → `convergence-engine.md` (algorithm only, target ~300L). The sibling `shared/convergence-examples.md` already exists (271L); finish migrating worked examples out of `convergence-engine.md`.
- Merge `shared/agent-communication.md` + `shared/agent-role-hierarchy.md` + `shared/agent-registry.md` into a single `shared/agents.md` with stable anchor subsections.
- Delete `shared/agent-consolidation-analysis.md` (unreferenced).
- Create `docs/adr/` seeded with ≥10 ADRs capturing historical decisions.
- Generate `shared/learnings-index.md` via a Python script (`scripts/gen-learnings-index.py`) that parses frontmatter and emits a Markdown table; CI validates freshness.
- Add a **"Start Here (5-minute path)"** section at the top of `CLAUDE.md` (≤30 lines, 3 bullets).
- Fix framework-count drift in `CLAUDE.md:16` to reflect the actual 23 (with an explicit note that `base-template.md` is scaffolding-only).

### Out of scope

- Rewriting or reorganizing the 285 individual learning files (content, not structure).
- Changing the module composition algorithm or any runtime agent behavior.
- Migrating to a docs-site generator (considered and rejected — see §4 Alternatives).
- Changing `forge-config.md` / `forge.local.md` schemas.

---

## 4. Architecture

### 4.1 Target `shared/` structure (post-refactor)

```
shared/
├── README.md                          # NEW: index of shared/ with 1-line descriptions (grouped)
├── agents.md                          # NEW (merged): agent model, UI tiers, dispatch graph, registry
│   # Sections: #model  #ui-tiers  #dispatch  #registry  #communication  #conflict-resolution
├── agent-colors.md                    # unchanged
├── agent-defaults.md                  # unchanged
├── agent-philosophy.md                # unchanged
├── agent-ui.md                        # unchanged
├── state-schema.md                    # REWRITTEN (~200L): directory layout, lifecycle table, top-level schema
├── state-schema-fields.md             # NEW (~1000L): field-by-field reference, extracted from old state-schema.md
├── convergence-engine.md              # TRIMMED (~300L): algorithm, counters, transitions
├── convergence-examples.md            # existing (271L): worked examples (fill gaps left by trim)
├── learnings-index.md                 # NEW (generated): auto-built from learnings/*.md frontmatter
├── learnings/                         # unchanged content
│   ├── README.md
│   ├── _template.md
│   └── ...                            # 285 learning files (unchanged)
├── ... (all other existing files unchanged)
```

**Deleted:**
- `shared/agent-communication.md` (content merged into `agents.md`)
- `shared/agent-role-hierarchy.md` (content merged into `agents.md`)
- `shared/agent-registry.md` (content merged into `agents.md`)
- `shared/agent-consolidation-analysis.md` (dead file)

**Net item change**: `shared/` drops from 119 → ~113 top-level items (after merging 3 files into 1 and deleting 1 dead), offset by `+2` new files (`README.md`, `learnings-index.md`, `state-schema-fields.md`). End state ≈ **114 items**. Success criterion <90 is achieved by the merge plus grouping the `shared/README.md` index into "clusters" so navigation cost is logarithmic, not linear. (A further sub-directory move — e.g. `shared/agents/` — is deferred to a later phase to keep this change single-PR.)

> **Note on success target.** The original W6 target of "119 → <90 items" cannot be met purely by file merges within the scope of this phase. We document the achievable count (~114 items) and a navigability metric (`shared/README.md` groups into ≤12 clusters, each cluster ≤12 items) as the operational proxy for "less sprawl". If strict <90 is required, we add `shared/agents/` and `shared/state/` sub-directories in Phase 06b.

### 4.2 `learnings-index.md` generation

**Input:** every file matching `shared/learnings/*.md` except `README.md` and `_template.md`. Each learning file has YAML frontmatter:

```yaml
---
title: Spring Boot 3 migration pitfalls
module: spring
tags: [migration, bootcamp]
confidence: HIGH
added: 2025-11-04
last_seen: 2026-04-02
occurrences: 7
---
```

**Output:** `shared/learnings-index.md` — generated Markdown:

```markdown
<!-- GENERATED by scripts/gen-learnings-index.py — DO NOT EDIT BY HAND -->
<!-- Source: shared/learnings/*.md frontmatter -->
<!-- Last generated: 2026-04-19T12:00:00Z (commit SHA: <sha>) -->

# Learnings Index

285 entries across 34 modules. Sorted by module, then last_seen descending.

## spring (14)

| File | Title | Confidence | Last Seen | Occurrences |
|------|-------|------------|-----------|-------------|
| [spring-boot-3-pitfalls.md](learnings/spring-boot-3-pitfalls.md) | Spring Boot 3 migration pitfalls | HIGH | 2026-04-02 | 7 |
| ...

## react (22)
...
```

**Script:** `scripts/gen-learnings-index.py` (Python 3.10+, relies on the dependency introduced in Phase 02). Uses `ruamel.yaml` for frontmatter parsing, `pathlib` for traversal. Deterministic output (stable sort, UTC timestamp excluded from content hash for idempotency — see CI section). Idempotent: running the script twice produces byte-identical output except for the `Last generated` header timestamp (which is excluded from the freshness hash).

**CI freshness contract:**
1. CI step runs `python scripts/gen-learnings-index.py --check`.
2. `--check` mode regenerates in-memory, strips the timestamp header line, hashes the body, compares against hash of committed `shared/learnings-index.md` (timestamp line stripped). Mismatch → job fails with diff.
3. Normal regeneration (no flag) writes the file with a fresh timestamp for local developer workflow.

**Config:** new top-level key `docs.learnings_index.auto_update` (default `true`) in `forge-config.md` — when `true`, the `forge-retrospective` agent (fg-700) will also regenerate the index if it added a new learning this run (non-CI path).

### 4.3 `docs/adr/` organization

```
docs/
├── adr/
│   ├── README.md              # Index + template link + status legend
│   ├── _template.md           # ADR template (see §4.4)
│   ├── 0001-neo4j-as-primary-graph-backend.md
│   ├── 0002-sqlite-tree-sitter-fallback.md
│   ├── 0003-deterministic-fsm-state-transitions.md
│   ├── 0004-evidence-based-shipping-gate.md
│   ├── 0005-composition-precedence-ordering.md
│   ├── 0006-87-category-scoring-model.md
│   ├── 0007-bash-to-python-tooling-migration.md
│   ├── 0008-no-backwards-compatibility-stance.md
│   ├── 0009-mcp-server-as-read-only-interface.md
│   ├── 0010-worktree-isolation-for-parallel-runs.md
│   └── 0011-output-compression-levels.md         # optional 11th
```

- **Numbering:** zero-padded 4-digit sequential (`0001` … `9999`). Gaps forbidden. Superseded ADRs are never renumbered.
- **Status values:** `Proposed` | `Accepted` | `Superseded by ADR-NNNN` | `Deprecated`. Recorded in the `Status:` field of each ADR.
- **Lifecycle:** new ADR opened as `Proposed`; moves to `Accepted` when merged to `master`. To reverse a decision, open a new ADR that *supersedes* the old one (do not edit history).
- **Filename rule:** `NNNN-kebab-case-title.md`. Title in the file matches (for grep-friendliness).
- **Index:** `docs/adr/README.md` is hand-maintained (one-line table) until volume warrants auto-generation.

### 4.4 ADR template (exact content)

```markdown
# ADR-NNNN: <short decision title>

- **Status:** Proposed | Accepted | Superseded by ADR-NNNN | Deprecated
- **Date:** YYYY-MM-DD
- **Deciders:** <names or GitHub handles>
- **Supersedes:** ADR-NNNN (if any)
- **Superseded by:** ADR-NNNN (if any)

## Context

What is the issue motivating this decision? What forces are in play (technical,
organizational, political)? What constraints shape the space? Write this so a
reader six months from now who has no other context can follow the argument.

## Decision

The choice made. One or two short paragraphs. State it as a present-tense
assertion ("We use X"), not a proposal ("We should use X").

## Consequences

- **Positive:** what gets better
- **Negative:** what gets worse / what this costs
- **Neutral:** what changes without clear sign

## Alternatives Considered

- **Option A — <name>:** <1-2 sentences on why not>
- **Option B — <name>:** <1-2 sentences on why not>

## References

- Related ADRs
- Related `shared/*.md` docs
- Links to PRs, issues, upstream docs
```

### 4.5 "Start Here" section (CLAUDE.md top)

Inserted between the existing H1 and the `## What this is` section. ≤30 lines.

```markdown
## Start Here (5-minute path)

New to forge? Three steps:

1. **Install:** `ln -s $(pwd) /path/to/your-project/.claude/plugins/forge`,
   then in that project run `/forge-init`. See `shared/mcp-provisioning.md` for
   MCP auto-setup.
2. **First run:** `/forge-run --dry-run "add a health endpoint"`. Dry-run only
   exercises PREFLIGHT → VALIDATE; no worktree, no commits. Confirm the plan
   looks right, then drop `--dry-run`.
3. **Pick the right skill:** unsure what to run? `/forge-help`. Bug? `/forge-fix`.
   Quality check? `/forge-review --full`. Multiple features? `/forge-sprint`.
   Full skill table is in §Skill selection guide below.

Already familiar? Skip to §Architecture.
```

### 4.6 Alternatives considered

**Alternative A — Don't split; use table-of-contents anchors only.**
Keep `state-schema.md` at 1236L, `convergence-engine.md` at 540L, `agent-communication.md` at 477L, and add a ToC at the top of each with deep anchors.
*Rejected because:* the files are already beyond the context window an agent can cite comfortably when loading them via `shared/` references, and the dense mixing of reference material with narrative ("here's how X works" interleaved with "here are the fields of Y") makes surgical edits risky. An anchor adds a navigation shortcut but does not reduce the tax every reader pays to skim. Splitting is a one-time cost for permanent savings.

**Alternative B — Migrate to a Sphinx/MkDocs site generator.**
Convert `shared/` into `.rst` or structured `.md`, build an HTML site, serve via GitHub Pages.
*Rejected because:* (1) forge is a doc-only Claude Code plugin — adding a build step contradicts the "no build" principle stated in `CLAUDE.md:38`; (2) every agent currently loads `shared/*.md` as raw content at dispatch time — a generator would either be ignored by agents (wasted effort) or require a second rendering path; (3) introduces a new language/tooling dependency (Python Sphinx or Node MkDocs) beyond what Phase 02 already provisions; (4) 285 learnings + 23 framework convention docs + 42 agents is not enough volume to justify an HTML frontend. Markdown-native tooling (`grep`, `rg`, the forthcoming MCP server) already serves the search need. Revisit if volume triples.

---

## 5. Components

### 5.1 File moves, splits, deletes (exhaustive)

**Split:**

| Source | Target(s) | Notes |
|--------|-----------|-------|
| `shared/state-schema.md` (1236L) | `shared/state-schema.md` (~200L, rewritten) + `shared/state-schema-fields.md` (~1000L, extracted) | Split point: field reference tables move to `-fields.md`; directory layout, lifecycle table, top-level schema stay in `state-schema.md`. Top-level file gains a "Field reference: see `state-schema-fields.md`" pointer. |
| `shared/convergence-engine.md` (540L) | `shared/convergence-engine.md` (~300L, trimmed) + `shared/convergence-examples.md` (existing, 271L — add remaining examples) | `convergence-examples.md` already exists from a prior partial split. Finish the job: move *all* worked examples, leave only algorithm + counter definitions in `convergence-engine.md`. Add a "Examples: see `convergence-examples.md`" pointer at top. |

**Merge (3 → 1):**

| Sources | Target | Section mapping |
|---------|--------|-----------------|
| `shared/agent-communication.md` (477L) | `shared/agents.md` | `#communication`, `#conflict-resolution` |
| `shared/agent-role-hierarchy.md` (161L) | `shared/agents.md` | `#ui-tiers`, `#dispatch` |
| `shared/agent-registry.md` (76L) | `shared/agents.md` | `#registry` |
| — | `shared/agents.md` (NEW, ~600-700L target) | Plus a new `#model` intro (~50L) framing the three merged areas |

**Delete:**

| File | Reason |
|------|--------|
| `shared/agent-communication.md` | merged into `agents.md` |
| `shared/agent-role-hierarchy.md` | merged into `agents.md` |
| `shared/agent-registry.md` | merged into `agents.md` |
| `shared/agent-consolidation-analysis.md` (62L) | unreferenced; stale one-off analysis from 2025 |

**Create:**

| File | Purpose |
|------|---------|
| `shared/README.md` | Index of `shared/` with 1-line descriptions, grouped into clusters (Agents, State & Contracts, Scoring & Quality, Recovery, Knowledge & Learning, Integrations, Tooling, Features) |
| `shared/agents.md` | Merged agent doc |
| `shared/state-schema-fields.md` | Extracted field reference |
| `shared/learnings-index.md` | Auto-generated by `scripts/gen-learnings-index.py` |
| `scripts/gen-learnings-index.py` | Python generator script |
| `docs/adr/README.md` | ADR index |
| `docs/adr/_template.md` | ADR template (§4.4) |
| `docs/adr/0001-neo4j-as-primary-graph-backend.md` | seed ADR |
| `docs/adr/0002-sqlite-tree-sitter-fallback.md` | seed ADR |
| `docs/adr/0003-deterministic-fsm-state-transitions.md` | seed ADR |
| `docs/adr/0004-evidence-based-shipping-gate.md` | seed ADR |
| `docs/adr/0005-composition-precedence-ordering.md` | seed ADR |
| `docs/adr/0006-87-category-scoring-model.md` | seed ADR |
| `docs/adr/0007-bash-to-python-tooling-migration.md` | seed ADR |
| `docs/adr/0008-no-backwards-compatibility-stance.md` | seed ADR |
| `docs/adr/0009-mcp-server-as-read-only-interface.md` | seed ADR |
| `docs/adr/0010-worktree-isolation-for-parallel-runs.md` | seed ADR |
| `docs/adr/0011-output-compression-levels.md` | seed ADR (optional 11th) |
| `.github/workflows/docs-integrity.yml` | CI: learnings-index freshness + ADR format + link-check |

**Edit:**

| File | Change |
|------|--------|
| `CLAUDE.md` (374L) | (a) insert `## Start Here (5-minute path)` block (§4.5) near top; (b) fix line 16: "`frameworks/` (21)" → "`frameworks/` (23; 21 production + `base-template` scaffolding + `k8s` ops)"; (c) update Key-entry-points table row "Agents" to point to `shared/agents.md`; (d) update references to the three merged docs elsewhere in `CLAUDE.md` to `shared/agents.md`. |
| Any `shared/*.md` or `agents/*.md` that cross-references `agent-communication.md`, `agent-role-hierarchy.md`, or `agent-registry.md` | Update link target to `shared/agents.md#<anchor>`. Sweep via `rg` at implementation time. |

### 5.2 `scripts/gen-learnings-index.py` — contract

- **Invocation:** `python scripts/gen-learnings-index.py [--check] [--output PATH]`.
- **Exit codes:** 0 success (or check-mode match); 1 check-mode mismatch; 2 parse error (malformed frontmatter).
- **Dependencies:** `ruamel.yaml` (pinned in `requirements.txt` from Phase 02).
- **Stable output:** Entries sorted by `(module asc, last_seen desc, filename asc)`. The `Last generated` header line is excluded from the hash comparison in `--check` mode.
- **Error on bad frontmatter:** exits 2 with filename + field name, does not emit partial output.

### 5.3 CI workflow: `.github/workflows/docs-integrity.yml`

Runs on every PR touching `shared/learnings/**`, `docs/adr/**`, `shared/**.md`, `CLAUDE.md`, or `scripts/gen-learnings-index.py`.

Steps:

1. **Setup Python** (3.10+), install from `requirements.txt`.
2. **Learnings-index freshness:** `python scripts/gen-learnings-index.py --check`. Fails the job if `shared/learnings-index.md` is stale.
3. **ADR format check:** a Python validator (inline in the workflow, <40 lines) asserts every file in `docs/adr/` matching `NNNN-*.md` has the required sections (`## Context`, `## Decision`, `## Consequences`, `## Alternatives Considered`, `## References`) and a valid `Status:` value.
4. **Link-check:** run `lychee` (pinned GitHub Action) across `CLAUDE.md`, `shared/**.md`, and `docs/**.md`. Internal anchor and relative-path failures are errors; external URLs are warnings only (network flakiness).
5. **Framework-count guard:** grep for `` `frameworks/` `` in `CLAUDE.md`, assert the parenthesized number matches `ls modules/frameworks/ | wc -l`. Fails if drift recurs.

No local test execution is required — all enforcement lives in CI per the phase constraints.

---

## 6. Data / State / Config

- **No state changes.** Pipeline `state.json` schema is untouched.
- **New config key:** `docs.learnings_index.auto_update: true` in `forge-config.md` (root-level `docs:` section, new). When `true`, the retrospective agent regenerates `shared/learnings-index.md` after adding a new learning. Setting it `false` disables the auto-regen (CI still enforces freshness).
- **No migration step** — consumers of the three merged agent docs are internal to the plugin; a single sweep in this PR updates every reference.

---

## 7. Compatibility

**Breaking changes (by design, no back-compat):**

- `shared/agent-communication.md`, `shared/agent-role-hierarchy.md`, `shared/agent-registry.md`, `shared/agent-consolidation-analysis.md` are deleted. Any external consumer linking to these paths (e.g. a fork's CLAUDE.md copy, a blog post, a user's bookmark) breaks. Mitigation: prominent note in the PR description and in `docs/adr/0009-*.md` (or a dedicated ADR if appropriate).
- Anchor links of the form `agent-communication.md#section-name` must be rewritten to `agents.md#<new-anchor>`. A full-repo sweep at implementation time (`rg -l 'agent-communication\.md|agent-role-hierarchy\.md|agent-registry\.md' CLAUDE.md shared/ agents/ skills/ docs/`) captures the internal surface; external surfaces are the user's problem.
- `shared/state-schema.md` shrinks dramatically. Any reference like `state-schema.md#<field>` where `<field>` now lives in `state-schema-fields.md` breaks. Sweep applies.
- `docs/adr/` is a net-new directory; no compatibility concern.

**Non-breaking:**

- All `agents/*.md` files are untouched.
- All skill entry points (`/forge-*`) behave identically.
- `forge-config.md` additions use default values that preserve current behavior.

---

## 8. Testing Strategy

All verification is CI-based — no local test runs.

**CI steps (from §5.3):**

1. **Learnings-index freshness check** (`--check` mode of the generator). Fails if `shared/learnings-index.md` is stale relative to `shared/learnings/*.md`.
2. **ADR format validator** — asserts every `docs/adr/NNNN-*.md` has the required sections and a valid `Status:` value; asserts numbering is dense starting at 0001 with no gaps.
3. **Link-check** (`lychee`) across `CLAUDE.md`, `shared/**.md`, `docs/**.md`. Internal/relative link failures fail the build; external-URL failures warn.
4. **Framework-count guard** — greps `CLAUDE.md` for the frameworks line and compares against `modules/frameworks/` directory contents.
5. **Structural validator** (`tests/validate-plugin.sh`) — existing test, should continue passing; any reference to a deleted file would fail its grep-based checks.
6. **Anchor existence check** — a new inline script in the workflow walks every `[text](path#anchor)` link in `CLAUDE.md` and `shared/**.md` and asserts the target anchor exists in the target file (prevents dead anchors after the merge).

**Out of CI (manual acceptance):** eyeball read of `shared/agents.md` and the ADR seed set on PR review.

---

## 9. Rollout

**Single PR.** No phased rollout, no feature flag. The changes are text-only, covered by CI, and the "no backwards compatibility" stance makes a big-bang merge correct.

Ordering inside the PR (for reviewer sanity):

1. Create `scripts/gen-learnings-index.py` + `docs/adr/_template.md` + `docs/adr/README.md` + seed ADRs 0001–0010 (11 optional).
2. Run the generator, commit `shared/learnings-index.md`.
3. Add `shared/README.md` (index).
4. Split `state-schema.md` → `state-schema.md` + `state-schema-fields.md`.
5. Trim `convergence-engine.md`; top up `convergence-examples.md`.
6. Merge the three agent docs into `shared/agents.md`; delete the three originals and `agent-consolidation-analysis.md`.
7. Sweep cross-references repo-wide.
8. Edit `CLAUDE.md`: Start Here block, framework-count fix, references updated.
9. Add `.github/workflows/docs-integrity.yml`.
10. Add `docs.learnings_index.auto_update` to `forge-config.md` template.

Reviewer runs CI; merge when green.

---

## 10. Risks / Open Questions

**Risks:**

1. **Anchor sweep misses a reference.** A downstream agent or skill links to `agent-communication.md#coordination` and it silently 404s. *Mitigation:* the new anchor-existence CI check (§8 step 6) catches all internal links on PR; external links are accepted as cost of no-back-compat.
2. **`shared/agents.md` becomes oversized (approaching the same 600-700L threshold we want to avoid).** *Mitigation:* it's still below our 600L target after merging because the three sources have overlap that is deduplicated in the merge. If it lands >600L, split into `agents.md` (model + UI tiers + dispatch) and `agent-communication.md` (communication + conflict resolution) — not the original three-way split.
3. **Generator script drifts from frontmatter reality.** One learning file has malformed YAML; CI fails; PR blocked on an unrelated file. *Mitigation:* generator exits 2 with filename + field, so the fix is one-line; `_template.md` shows the canonical shape; a pre-PR sweep fixes stragglers once.
4. **Lychee false positives on external URLs.** Flaky networks block PRs. *Mitigation:* external-URL failures are warnings only (§8 step 3); internal-only is the hard gate.
5. **Success target <90 items.** Our refactor lands ~114; the stated target is <90. *Mitigation:* documented openly in §4.1 with a navigability proxy (≤12 clusters × ≤12 items) and an explicit Phase 06b carry-over if the strict count matters.

**Open questions:**

1. Does `docs.learnings_index.auto_update` belong in `forge-config.md` (per-project) or only as a plugin default? Proposed: forge-config with default `true`; rationale is that a project *could* want to freeze its snapshot without the retro agent re-running it.
2. Should we adopt the **Diataxis** taxonomy (Tutorials / How-tos / Reference / Explanation) when writing `shared/README.md`? Proposed: yes for the grouping headers, but not as filename prefixes (too invasive for this phase).
3. Should ADR-0008 ("no backwards compatibility") be marked `Accepted` given the phase constraints explicitly restate it, or is that a proposal needing explicit sign-off? Proposed: `Accepted`, 2026-04-19, citing the A+ roadmap constraints.

---

## 11. Success Criteria

All measurable, all CI-checkable:

- [ ] `shared/` top-level item count drops from 119 to ≤115 (realistic target; <90 deferred to Phase 06b).
- [ ] `shared/README.md` exists and groups items into ≤12 clusters, each ≤12 items.
- [ ] **No file in `shared/` or `CLAUDE.md` exceeds 600 lines** (`find shared CLAUDE.md -name '*.md' -exec wc -l {} \; | awk '$1 > 600'` returns empty in CI).
- [ ] `CLAUDE.md` contains a `## Start Here (5-minute path)` section within the first 50 lines, ≤30 lines long, with exactly 3 numbered steps (install, first run, skill picker).
- [ ] `CLAUDE.md` framework-count line matches `ls modules/frameworks/ | wc -l` (CI framework-count guard green).
- [ ] `docs/adr/` contains ≥10 ADRs (0001 through 0010+), each passing the ADR format validator.
- [ ] `shared/learnings-index.md` exists and passes `gen-learnings-index.py --check` in CI.
- [ ] `shared/agents.md` exists; `agent-communication.md`, `agent-role-hierarchy.md`, `agent-registry.md`, `agent-consolidation-analysis.md` do not exist.
- [ ] Lychee internal-link check green on `CLAUDE.md`, `shared/**.md`, `docs/**.md`.
- [ ] Anchor-existence check green.
- [ ] `tests/validate-plugin.sh` remains green.

---

## 12. References

- **ADR practice:** Michael Nygard, *Documenting Architecture Decisions* — https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions (canonical origin of the Context/Decision/Consequences structure).
- **ADR tooling + lightweight template:** https://adr.github.io/ and https://github.com/joelparkerhenderson/architecture-decision-record.
- **Diataxis docs framework:** Daniele Procida — https://diataxis.fr/ (informs the grouping of `shared/README.md` into reference / how-to / explanation clusters, not adopted wholesale).
- **`lychee` link checker:** https://github.com/lycheeverse/lychee-action.
- **Google engineering practices on doc freshness:** https://google.github.io/eng-practices/ (CI-enforced staleness checks).
- **Related forge specs:** `docs/superpowers/specs/2026-04-19-01-evaluation-harness-design.md` (Phase 01); Phase 02 introduces the Python dependency this spec reuses.
- **Internal docs touched:**
  - `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/state-schema.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/convergence-engine.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/convergence-examples.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/agent-communication.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/agent-role-hierarchy.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/agent-registry.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/agent-consolidation-analysis.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/learnings/`
  - `/Users/denissajnar/IdeaProjects/forge/modules/frameworks/`
