# Shared Learnings Architecture

The adaptive learning system operates across two dimensions — per-project and cross-project — so that insights compound over time.

## Storage locations

| Scope | Location | Lifecycle |
|-------|----------|-----------|
| Per-project | `.claude/forge-log.md` (consuming repo) | Grows with each pipeline run; never leaves the project |
| Cross-project | `shared/learnings/{module}.md` (this plugin repo) | One file per framework, language, testing framework, and crosscutting layer. Curated by retrospective agent; ships with the plugin |

## Learning classification

Every learning produced by `fg-700-retrospective` is classified into one of two categories:

### PROJECT-SPECIFIC
- References project file paths, domain entities, or local configuration
- Examples: "The `OrderService` port must validate currency before delegating", "`/api/v2/users` endpoint needs pagination"
- Stored only in `.claude/forge-log.md`
- Never promoted to shared learnings

### MODULE-GENERIC
- Describes framework patterns, library quirks, or toolchain gotchas
- Examples: "R2DBC update adapters must fetch-then-set to preserve audit columns", "Tailwind text-* classes break typography scale"
- Candidates for promotion to `shared/learnings/{module}.md`
- Must be stripped of project-specific identifiers before promotion

## Classification heuristic

A learning is PROJECT-SPECIFIC if it matches any of:
- Contains absolute or project-relative file paths
- References domain entity names not found in framework/library docs
- Depends on project-specific configuration values

Everything else is MODULE-GENERIC.

## Merge strategy at PREFLIGHT

During the PREFLIGHT stage, the orchestrator:

1. **Loads** per-project learnings from `.claude/forge-log.md`
2. **Loads** cross-project learnings from `shared/learnings/{module}.md` (matching the active module)
3. **Deduplicates** by comparing `Pattern` fields (fuzzy match, >80% similarity = duplicate)
4. **Filters** to items whose `Domain` matches the current story's affected areas
5. **Injects** matching PREEMPT items into the pipeline context for downstream agents

## PREEMPT item format

Each cross-project learning follows this structure:

```markdown
### {MODULE_PREFIX}-PREEMPT-{NNN}: {short title}
- **Domain:** {area — e.g., persistence, build, styling, routing}
- **Pattern:** {what to do or avoid}
- **Confidence:** {LOW | MEDIUM | HIGH}
- **Hit count:** {integer — times this was relevant in a run}
```

## Confidence levels

| Level | Meaning | Promotion criteria |
|-------|---------|--------------------|
| LOW | Single occurrence, not yet validated | Observed once |
| MEDIUM | Confirmed across 2-3 runs | Validated in multiple contexts |
| HIGH | Stable pattern, consistently relevant | 4+ hits, 0 false positives |

## Pruning

> **Superseded by PREEMPT Lifecycle below.** The confidence decay model provides gradual deprecation instead of abrupt removal. These rules are retained for historical context.

Learnings are removed from shared files when:
- `Hit count` remains 0 over 10 consecutive runs across any project
- The underlying framework/library version makes the learning obsolete
- A higher-confidence learning supersedes it

### Agent Effectiveness

Agent performance is tracked per `agent-effectiveness-template.md` (operational guide) and `agent-effectiveness-schema.json` (data format). The retrospective updates effectiveness data after each run and checks auto-tuning triggers.

### PREEMPT Lifecycle

Every PREEMPT item has a confidence in `[0, 1]` that decays on an Ebbinghaus
exponential curve with per-type half-lives. See `shared/learnings/decay.md` for
the canonical contract, formula, thresholds, reinforcement/penalty rules, and
tuning warnings.

~~**Legacy (superseded 2026-04-19):** counter-based decay — HIGH → MEDIUM
after 10 unused runs, 1 false positive counted as 3 unused. Replaced by the
Ebbinghaus exponential curve.~~

## Auto-Discovered PREEMPT Items (v1.20+)

Starting in v1.20, the retrospective (fg-700) autonomously discovers codebase patterns across runs and stores them as PREEMPT items with `source: auto-discovered`. These are distinct from user-defined or retrospective-suggested items.

Key properties:
- **Initial confidence:** MEDIUM (not HIGH — human hasn't confirmed)
- **Promotion:** After 3 successful applications → promoted to HIGH
- **Decay:** 14-day half-life (`type: auto-discovered`), roughly 2× faster than the 30-day cross-project half-life. See `shared/learnings/decay.md`.
- **Labeling:** Clearly marked with `source: auto-discovered` in `forge-log.md`
- **User control:** Can be promoted to HIGH (`source: user-confirmed`) or dismissed entirely

See `shared/learnings/memory-discovery.md` for the full discovery contract.

## Active Knowledge Base (v2.0+)

Starting in v2.0, Forge introduces an active knowledge base that extends the passive PREEMPT system with structured, lifecycle-managed knowledge items. The full contract is defined in `shared/knowledge-base.md`.

### Relationship to PREEMPT learnings

The existing PREEMPT system (per-project in `forge-log.md`, cross-project in `shared/learnings/`) remains unchanged. The active knowledge base is an additive layer:

| Dimension | PREEMPT Learnings | Active Knowledge Items |
|---|---|---|
| Storage | `.claude/forge-log.md` + `shared/learnings/*.md` | `.forge/knowledge/` (rules.json, patterns.json, root-causes.json) |
| When written | LEARN stage only (retrospective) | During execution (agents) + LEARN stage (retrospective validates) |
| Granularity | Free-text markdown items | Structured JSON with schemas (`shared/schemas/knowledge-rule-schema.json`, `shared/schemas/knowledge-pattern-schema.json`) |
| Lifecycle | Confidence decay (HIGH/MEDIUM/LOW/ARCHIVED) | Explicit state machine (CANDIDATE/VALIDATED/ACTIVE/ARCHIVED/REJECTED) |
| Scope | Per-module cross-project wisdom | Per-project active rules and patterns |
| Check engine | Not directly integrated | Regex rules auto-promoted to L1 via `shared/checks/learned-rules-override.json` |

### The `.forge/knowledge/` directory

```
.forge/knowledge/
├── inbox/                          # Pending items from current run
│   └── candidate-{timestamp}-{agent}.json
├── rules.json                      # Validated and active rules (schema: shared/schemas/knowledge-rule-schema.json)
├── patterns.json                   # Discovered codebase patterns (schema: shared/schemas/knowledge-pattern-schema.json)
├── root-causes.json                # Root cause patterns from bugfixes
└── metrics.json                    # Application tracking and effectiveness
```

The knowledge directory survives `/forge-recover reset`. Only manual `rm -rf .forge/knowledge/` or `/forge-recover reset --hard` removes it.

### Key distinction: learnings vs knowledge items

- **Learnings** are per-module cross-project wisdom. They describe framework patterns, library quirks, and toolchain gotchas. They ship with the plugin in `shared/learnings/` and grow in `forge-log.md` per project.
- **Knowledge items** are per-project active rules. They describe coding standards, conventions, and root cause patterns specific to how the project is built. They live in `.forge/knowledge/` and are managed through a structured lifecycle with effectiveness tracking.

A knowledge item with `application_count >= 3` and HIGH confidence may be flagged for promotion to a cross-project learning (requires `knowledge.cross_project_promotion: true` and manual plugin maintainer review).

### Three knowledge item types

1. **CANDIDATE_RULE** — emitted by reviewers when a finding reveals a generalizable pattern. Validated by retrospective, promoted through lifecycle.
2. **PATTERN_DISCOVERY** — emitted by implementer when it observes consistent codebase patterns across 3+ files.
3. **ROOT_CAUSE_PATTERN** — emitted by bug investigator when root cause analysis reveals a systemic issue.

### Integration with PREEMPT

At PREFLIGHT, ACTIVE knowledge items are converted to PREEMPT format with `source: learned-rule` and injected into the pipeline context alongside standard PREEMPT items. Deduplication uses >80% description similarity; the higher-confidence item wins.

## Privacy guarantees

Before a learning is promoted from per-project to cross-project:
1. All file paths are stripped
2. All domain entity names are replaced with generic placeholders
3. All configuration values are generalized
4. The result is reviewed by `fg-700-retrospective` for remaining project-specific content

No project-specific data ever enters the plugin repository.
