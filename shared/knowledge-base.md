# Active Knowledge Base

The active knowledge base extends Forge's learning system from passive retrospective capture to active mid-run contribution. Agents discover patterns, conventions, and root causes during execution and persist them as structured knowledge items for reuse in the same or subsequent runs.

## Motivation

Forge's existing PREEMPT system captures learnings only at the LEARN stage after pipeline completion. The active knowledge base closes three gaps:

1. **BugBot-style rule learning** — when a reviewer flags an issue and the implementer fixes it, the (finding, fix) pair is generalized into a reusable rule that prevents the same issue in future runs.
2. **Active contribution** — agents can write knowledge items during execution, not just at retrospective.
3. **Rules vs Memories** — an explicit distinction (following the Windsurf model) between coding standards (rules) and project context (memories).

## Knowledge Item Types

### CANDIDATE_RULE

Emitted by reviewer agents when they identify a generalizable pattern that should become a convention. Contains the detection pattern, recommended fix, applicable contexts, and evidence linking to the specific finding.

Source agents: `fg-410-code-reviewer`, `fg-411-security-reviewer`, `fg-412-architecture-reviewer`, `fg-413-frontend-reviewer`, `fg-416-backend-performance-reviewer`.

### PATTERN_DISCOVERY

Emitted by the implementer when it observes consistent codebase patterns across 3+ files during implementation. Captures the structural regularity (naming, architecture, configuration) with file evidence.

Source agent: `fg-300-implementer`.

### ROOT_CAUSE_PATTERN

Emitted by the bug investigator when root cause analysis reveals a systemic issue that is likely to recur. Contains detection hints and prevention rules.

Source agent: `fg-020-bug-investigator`.

## Rule Lifecycle

```
CANDIDATE  ──(validation)──>  VALIDATED  ──(2+ runs, no false positives)──>  ACTIVE  ──(decay)──>  ARCHIVED
    |                             |                                             |
    |                             |                                             |
    +──(duplicate/invalid)──>  REJECTED    ACTIVE ──(3 false positives)──>  ARCHIVED
```

| State | Description | Loaded at PREFLIGHT | Scored |
|---|---|---|---|
| `CANDIDATE` | Created by agent during execution. In inbox, awaiting validation. | No | No |
| `VALIDATED` | Confirmed by retrospective (evidence checks out, not a duplicate). | Yes (as LOW-confidence PREEMPT) | No |
| `ACTIVE` | Applied in 2+ runs without false positives. | Yes (as MEDIUM or HIGH-confidence PREEMPT) | Yes (via PREEMPT) |
| `ARCHIVED` | Decayed due to non-use, superseded, or excessive false positives. | No | No |
| `REJECTED` | Retrospective determined the candidate was invalid or duplicate. | No | No |

### Promotion criteria

- CANDIDATE to VALIDATED: evidence verified by retrospective, not a duplicate (>80% description similarity = duplicate).
- VALIDATED to ACTIVE: applied in 2+ runs without false positives.
- ACTIVE to HIGH confidence: 3+ applications and stable effectiveness score.
- ACTIVE to ARCHIVED: `effectiveness_score < 0.5` or `false_positive_count > 3 * application_count`.
- Any to ARCHIVED: 10 unused runs (standard PREEMPT decay; learned rules follow standard decay rates).

### Effectiveness scoring

```
effectiveness_score = application_count / (application_count + false_positive_count)
```

A minimum of 3 applications is required before the effectiveness score is considered meaningful for promotion or archival decisions. Below that threshold, rules remain at their current lifecycle state regardless of score.

## BugBot-Style Rule Learning

When a review finding is emitted AND subsequently fixed by the implementer, the quality gate records a (finding, fix) pair:

1. **Capture:** Quality gate records each finding sent to implementer. After implementer completes, quality gate records the diff that addressed the finding.
2. **Pair formation:** A structured `{ finding, fix }` object is written to stage notes.
3. **Generalization:** At LEARN, the retrospective generalizes the pair — strip file paths (replace with glob patterns), strip domain-specific names (replace with `{entity}` placeholders), extract the detection pattern and prevention rule.
4. **Deduplication:** Compare against existing rules by `(category, generalized_description)` with >80% fuzzy match = duplicate. Duplicates increment hit count on existing rule.
5. **Output:** A CANDIDATE_RULE item in the inbox, or an updated hit count on an existing rule.

## Rules vs Memories

Following the Windsurf model, Forge distinguishes two knowledge types:

| Dimension | Rules | Memories |
|---|---|---|
| Nature | Coding standards, conventions, constraints | Decisions, discoveries, project context |
| Source | Review findings, convention violations, security patterns | Retrospective observations, user corrections, domain insights |
| Scope | Cross-project (generalizable) | Project-specific |
| Storage | `.forge/knowledge/rules.json` + convention stack | `.claude/forge-log.md` (PREEMPT items) |
| Lifecycle | CANDIDATE > VALIDATED > ACTIVE > ARCHIVED | Standard PREEMPT lifecycle |
| Application | L1/L2 check engine (if regex), reviewer pre-context (always) | Agent pre-context at PREFLIGHT |
| Examples | "Never use `any` type in TypeScript public APIs", "All API responses must include `traceId`" | "This project uses hexagonal architecture", "The billing module has known N+1 issues" |

**Promotion path:** A memory that recurs across 5+ projects and is stripped of project-specific context can be promoted to a rule. The retrospective flags candidates; plugin maintainers review before adding to `shared/learnings/`.

## Storage

### Directory structure

```
.forge/knowledge/
├── inbox/                          # Pending items from current run
│   └── candidate-{timestamp}-{agent}.json
├── rules.json                      # Validated and active rules
├── patterns.json                   # Discovered codebase patterns
├── root-causes.json                # Root cause patterns from bugfixes
└── metrics.json                    # Application tracking and effectiveness
```

All files survive `/forge-reset`. Only manual `rm -rf .forge/knowledge/` or `/forge-reset --hard` removes them.

### Schema references

- Rules: `shared/schemas/knowledge-rule-schema.json`
- Patterns: `shared/schemas/knowledge-pattern-schema.json`
- Root causes: defined inline in `root-causes.json` (see spec F09 for full schema)
- Metrics: defined inline in `metrics.json` (see spec F09 for full schema)

### rules.json

Array of rule objects with fields: `id`, `state`, `category`, `description`, `detection_pattern`, `detection_type` (`regex` or `semantic`), `recommended_fix`, `applicable_contexts`, `applicable_languages`, `source_agent`, `severity_default`, `confidence`, `created_at`, `last_applied`, `application_count`, `false_positive_count`, `effectiveness_score`, `promoted_from`, `source`.

The `source` field distinguishes origin: `learned-rule` (from review finding+fix pair), `manual` (user-authored), `auto-discovered` (promoted from memory discovery).

### patterns.json

Array of pattern objects with fields: `id`, `state`, `domain`, `description`, `pattern`, `evidence_file_count`, `confidence`, `application_count`, `false_positive_count`, `created_at`, `last_applied`, `source`.

### root-causes.json

Array of root cause objects with fields: `id`, `state`, `category`, `description`, `detection_hint`, `prevention_rule`, `confidence`, `occurrence_count`, `last_occurred`, `created_at`, `source`.

### metrics.json

Aggregate tracking: `total_rules`, `active_rules`, `total_applications`, `total_false_positives`, `overall_effectiveness`, `top_rules_by_application`, `rules_promoted_to_convention`, `last_updated`.

## PREEMPT Integration

Active rules feed into the existing PREEMPT system with `source: learned-rule`:

```markdown
### rule-sec-jwt-exp-001: JWT tokens must include expiration
- **Source:** learned-rule
- **Confidence:** HIGH
- **Domain:** auth, api
- **Pattern:** Always include exp claim with max 24h TTL when creating JWT tokens
- **Hit count:** 7
- **Detection:** regex: jwt\.sign\(.*\)(?!.*expiresIn|exp)
```

At PREFLIGHT, the orchestrator loads (in order):
1. Standard PREEMPT items from `.claude/forge-log.md` (existing)
2. Active rules from `.forge/knowledge/rules.json` (converted to PREEMPT format)
3. Active patterns from `.forge/knowledge/patterns.json` (converted to PREEMPT format)
4. Active root causes from `.forge/knowledge/root-causes.json` (converted to PREEMPT format)

Deduplication: if a learned rule overlaps with an existing PREEMPT item (>80% description similarity), the higher-confidence item wins.

## Check Engine Integration

Rules with `detection_type: "regex"` can be automatically promoted to L1 check engine patterns:

1. When a rule reaches ACTIVE state with HIGH confidence and `detection_type: "regex"`, the retrospective writes an entry to `shared/checks/learned-rules-override.json`.
2. This file follows the same format as framework `rules-override.json` files, with `source: "learned-rule"` on each entry.
3. The check engine loads it alongside the standard `rules-override.json`.
4. The learned rule becomes an L1 check — sub-second detection on every `Edit`/`Write`.
5. If the rule produces false positives in L1 (detected via `PREEMPT_SKIPPED` reports), it is demoted back to agent-level review only.

## Agent Contribution Hooks

Each contributing agent writes to `.forge/knowledge/inbox/` during its execution:

| Agent | Contribution Type | Trigger |
|---|---|---|
| `fg-411-security-reviewer` | `CANDIDATE_RULE` | Security finding reveals a general pattern |
| `fg-412-architecture-reviewer` | `CANDIDATE_RULE` | Architectural violation represents a convention worth enforcing |
| `fg-410-code-reviewer` | `CANDIDATE_RULE` | Code quality finding reveals a recurring anti-pattern |
| `fg-413-frontend-reviewer` | `CANDIDATE_RULE` | Frontend finding reveals a reusable design/perf rule |
| `fg-416-backend-performance-reviewer` | `CANDIDATE_RULE` | Performance finding reveals a general optimization pattern |
| `fg-300-implementer` | `PATTERN_DISCOVERY` | Observes consistent patterns across 3+ files during implementation |
| `fg-020-bug-investigator` | `ROOT_CAUSE_PATTERN` | Root cause analysis reveals a systemic issue pattern |
| `fg-400-quality-gate` | (finding, fix) pair | Finding is fixed by implementer; records pair for rule learning |

### Contribution constraints

- Maximum 3 inbox items per agent per run (configurable via `knowledge.max_inbox_per_agent`, default 3, range 1-10).
- Inbox items must include `evidence` (file path, line, finding ID). Unsubstantiated items are rejected by the retrospective.
- Tier 4 agents (reviewers) can write to inbox but cannot write to `rules.json` directly. Only `fg-700-retrospective` promotes items.

### Inbox item format

Agents write JSON files to `.forge/knowledge/inbox/candidate-{timestamp}-{agent}.json`. The filename convention ensures uniqueness and traceability. Each file contains a single knowledge item with its `type`, `source_agent`, `description`, `evidence`, and type-specific fields.

## Privacy

Before any knowledge item is promoted from CANDIDATE to VALIDATED:
1. All absolute file paths are stripped (replaced with glob patterns).
2. All domain entity names are replaced with generic placeholders.
3. All configuration values are generalized.
4. The retrospective reviews for remaining project-specific content.

Cross-project promotion (`knowledge.cross_project_promotion`) is disabled by default. When enabled, rules flagged for promotion require manual plugin maintainer review before entering `shared/learnings/`.

## Configuration

In `forge-config.md`:

```yaml
knowledge:
  enabled: true
  active_contribution: true
  rule_learning: true
  max_inbox_per_agent: 3
  max_rules: 100
  auto_promote_to_check_engine: true
  cross_project_promotion: false
```

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `enabled` | boolean | `true` | -- | Master toggle for the knowledge base |
| `active_contribution` | boolean | `true` | -- | Allow agents to write knowledge items during execution |
| `rule_learning` | boolean | `true` | -- | Enable BugBot-style (finding, fix) pair learning |
| `max_inbox_per_agent` | integer | `3` | 1-10 | Maximum inbox items per agent per run |
| `max_rules` | integer | `100` | 20-500 | Maximum active rules before eviction |
| `auto_promote_to_check_engine` | boolean | `true` | -- | Automatically add HIGH-confidence regex rules to L1 check engine |
| `cross_project_promotion` | boolean | `false` | -- | Allow rules to be promoted to `shared/learnings/` (requires manual review) |

## Error Handling

| Failure Mode | Behavior |
|---|---|
| Inbox write failure during execution | Log INFO, agent continues. Pipeline never blocks on knowledge writes. |
| `rules.json` corrupted | Delete and rebuild from inbox history and `forge-log.md` PREEMPT items. Log WARNING. |
| Retrospective fails to process inbox | Items persist until next successful LEARN stage. Items older than 5 runs auto-archived with WARNING. |
| Too many rules (exceeds `max_rules`) | Evict lowest-effectiveness rules (by `effectiveness_score`, then by `last_applied`). |
| False positive rate exceeds threshold | Rule with `false_positive_count > 3 * application_count` archived. |
| `.forge/knowledge/` missing | Auto-created at PREFLIGHT when `knowledge.enabled: true`. |

## Data Flow Summary

### During execution

1. Agent detects a knowledge-worthy pattern.
2. Agent writes JSON to `.forge/knowledge/inbox/candidate-{timestamp}-{agent}.json`.
3. Quality gate tracks (finding, fix) pairs for rule learning.
4. Orchestrator does NOT process inbox during the run — items accumulate.

### At LEARN stage

1. Retrospective reads all files from `.forge/knowledge/inbox/`.
2. Validates evidence, deduplicates, promotes valid items.
3. Processes (finding, fix) pairs from quality gate into CANDIDATE_RULE items.
4. Updates `metrics.json`.
5. Clears `.forge/knowledge/inbox/`.
6. Promotes VALIDATED rules with 2+ applications to ACTIVE.
7. Archives ACTIVE rules with `effectiveness_score < 0.5` (only when `application_count >= 3`).

### At PREFLIGHT (next run)

1. Loads ACTIVE and VALIDATED rules from `.forge/knowledge/rules.json`.
2. Converts to PREEMPT format, injects into pipeline context.
3. Loads ACTIVE patterns and root causes similarly.
4. Verifies `learned-rules-override.json` is current for eligible regex rules.
5. Records loaded knowledge count in stage notes.
