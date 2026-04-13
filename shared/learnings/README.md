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

PREEMPT items follow a confidence decay lifecycle managed by the retrospective:
- Active items: HIGH, MEDIUM, or LOW confidence — loaded during PREFLIGHT
- Archived items: moved to bottom of forge-log.md — NOT loaded during PREFLIGHT

**Confidence decay formula:**

| Current level | Condition | Action |
|---|---|---|
| HIGH | 10 consecutive unused runs | Demote to MEDIUM |
| MEDIUM | 10 consecutive unused runs | Demote to LOW |
| LOW | 10 consecutive unused runs | Archive (stop loading at PREFLIGHT) |
| Any | 1 false positive confirmed | Count as 3 unused runs toward demotion |
| Any | Framework/library major version supersedes the pattern | Archive immediately |
| LOW | Hit count = 0 AND age > 20 runs | Archive |

**Confidence promotion:**

| Current level | Condition | Action |
|---|---|---|
| LOW | 2+ hits across different runs | Promote to MEDIUM |
| MEDIUM | 4+ hits AND 0 false positives | Promote to HIGH |
| HIGH | 3+ applications AND stable across 5+ runs | Candidate for permanent convention rule |

**Tracking fields per PREEMPT item:**
- `runs_since_last_hit`: integer, resets to 0 on any hit (only incremented when item's domain is active in a run)
- `false_positives`: integer, incremented by retrospective when agent reports PREEMPT_SKIPPED with reason
- `last_hit`: ISO 8601 date of last use

This supersedes the simple "Pruning" rules previously defined. The confidence decay model provides gradual deprecation instead of abrupt removal.

## Auto-Discovered PREEMPT Items (v1.20+)

Starting in v1.20, the retrospective (fg-700) autonomously discovers codebase patterns across runs and stores them as PREEMPT items with `source: auto-discovered`. These are distinct from user-defined or retrospective-suggested items.

Key properties:
- **Initial confidence:** MEDIUM (not HIGH — human hasn't confirmed)
- **Promotion:** After 3 successful applications → promoted to HIGH
- **Decay:** 2x faster than normal items (`decay_multiplier: 2`)
- **Labeling:** Clearly marked with `source: auto-discovered` in `forge-log.md`
- **User control:** Can be promoted to HIGH (`source: user-confirmed`) or dismissed entirely

See `shared/learnings/memory-discovery.md` for the full discovery contract.

## Privacy guarantees

Before a learning is promoted from per-project to cross-project:
1. All file paths are stripped
2. All domain entity names are replaced with generic placeholders
3. All configuration values are generalized
4. The result is reviewed by `fg-700-retrospective` for remaining project-specific content

No project-specific data ever enters the plugin repository.
