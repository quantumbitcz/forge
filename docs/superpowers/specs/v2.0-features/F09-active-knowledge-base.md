# F09: Active Knowledge Base with Learned Rules

## Status
DRAFT — 2026-04-13

## Problem Statement

Forge's learnings system is passive — knowledge is captured only during the LEARN stage by `fg-700-retrospective`, after the pipeline has completed. Agents discover patterns, coding conventions, and root cause insights during execution but have no mechanism to persist them mid-run for reuse in the same or immediately subsequent runs.

Cursor's BugBot has generated 44,000+ learned rules from live code review feedback. Each time a reviewer flags an issue and the developer fixes it, the fix pattern is generalized into a rule that prevents the same issue in future reviews. Windsurf makes an explicit distinction between rules (static coding standards) and memories (dynamic project-specific discoveries), applying both during code generation.

The gap in Forge: reviewers emit findings (SEC-*, ARCH-*, QUAL-*) that are scored and fixed, but the fix pattern is not generalized into a reusable rule. Bug investigator discovers root causes that reveal systemic patterns, but these are only captured as one-off PREEMPT items by the retrospective — not as structured, searchable rules with application tracking. The existing PREEMPT lifecycle (`shared/learnings/README.md`) and memory discovery (`shared/learnings/memory-discovery.md`) provide the foundation, but knowledge flows in only one direction: run end (retrospective) into forge-log.md.

## Proposed Solution

Extend Forge's knowledge system with (1) active knowledge contribution — agents can write knowledge items during execution, not just at retrospective, (2) a BugBot-style rule learning pipeline that converts review findings + applied fixes into generalized reusable rules, (3) an explicit rules-vs-memories distinction following the Windsurf model, and (4) a `.forge/knowledge/` directory storing structured knowledge with lifecycle tracking.

## Detailed Design

### Architecture

```
During Execution:
  +--------------------+     +--------------------+     +--------------------+
  | Reviewers          |     | Implementer        |     | Bug Investigator   |
  | (fg-410 thru 420)  |     | (fg-300)           |     | (fg-020)           |
  +--------------------+     +--------------------+     +--------------------+
          |                          |                          |
     CANDIDATE_RULE           PATTERN_DISCOVERY          ROOT_CAUSE_PATTERN
          |                          |                          |
          v                          v                          v
  +---------------------------------------------------------------+
  | Knowledge Collector (stage notes → .forge/knowledge/inbox/)   |
  +---------------------------------------------------------------+
                              |
At LEARN Stage:               v
  +------------------------------------------------------------+
  | fg-700-retrospective                                       |
  | 1. Read inbox/ items                                       |
  | 2. Validate against run evidence                           |
  | 3. Generalize (strip project-specifics)                    |
  | 4. Check for duplicates in rules.json                      |
  | 5. Promote VALIDATED items to rules.json / patterns.json   |
  | 6. Update existing rule hit counts                         |
  +------------------------------------------------------------+
                              |
At PREFLIGHT (next run):      v
  +------------------------------------------------------------+
  | Orchestrator loads ACTIVE rules as PREEMPT context         |
  | Quality gate receives rules for pre-emptive checking       |
  +------------------------------------------------------------+
```

### Knowledge Item Types

#### CANDIDATE_RULE

Emitted by reviewer agents when they identify a pattern that should become a convention:

```json
{
  "type": "CANDIDATE_RULE",
  "source_agent": "fg-411-security-reviewer",
  "finding_category": "SEC-AUTH-001",
  "finding_severity": "CRITICAL",
  "description": "JWT tokens must include exp claim with max 24h TTL",
  "pattern_to_detect": "jwt.sign|jwt.encode without exp parameter",
  "recommended_fix": "Always include exp claim: jwt.sign(payload, secret, { expiresIn: '24h' })",
  "applicable_contexts": ["auth", "api"],
  "evidence": {
    "file": "src/auth/token-service.ts",
    "line": 42,
    "finding_id": "SEC-AUTH-001-abc123"
  },
  "created_at": "2026-04-13T10:15:00Z",
  "run_id": "feat-user-auth"
}
```

#### PATTERN_DISCOVERY

Emitted by the implementer when it discovers a recurring codebase pattern:

```json
{
  "type": "PATTERN_DISCOVERY",
  "source_agent": "fg-300-implementer",
  "description": "All repository classes use Result<T, DomainError> return type",
  "pattern": "class *Repository.*fun .*: Result<",
  "domain": "persistence",
  "evidence_files": [
    "src/domain/user/UserRepository.kt",
    "src/domain/order/OrderRepository.kt",
    "src/domain/product/ProductRepository.kt"
  ],
  "confidence": "MEDIUM",
  "created_at": "2026-04-13T10:20:00Z",
  "run_id": "feat-plan-comments"
}
```

#### ROOT_CAUSE_PATTERN

Emitted by the bug investigator when root cause analysis reveals a systemic issue:

```json
{
  "type": "ROOT_CAUSE_PATTERN",
  "source_agent": "fg-020-bug-investigator",
  "description": "Lazy-loaded collections accessed outside transaction boundary cause LazyInitializationException",
  "root_cause_category": "persistence",
  "detection_pattern": "EAGER fetch or explicit JOIN FETCH required for collection properties accessed after findById",
  "prevention_rule": "When adding collection properties to JPA entities, default to FetchType.LAZY but ensure all service methods that access the collection are @Transactional",
  "evidence": {
    "bug_description": "NPE when accessing plan.comments in REST controller",
    "root_cause_file": "src/domain/plan/Plan.kt",
    "root_cause_line": 28
  },
  "created_at": "2026-04-13T10:25:00Z",
  "run_id": "fix-plan-comments-npe"
}
```

### Rule Lifecycle

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

### BugBot-Style Rule Learning Pipeline

When a review finding is emitted AND subsequently fixed by the implementer, the fix creates a (finding, fix) pair that can be generalized:

1. **Capture:** Quality gate records each finding that was sent to implementer for fixing. After implementer completes, quality gate records the diff (changed lines) that addressed the finding.
2. **Pair formation:** A (finding, fix) pair is formed:
   ```json
   {
     "finding": {
       "category": "SEC-AUTH-001",
       "severity": "CRITICAL",
       "description": "JWT token created without expiration",
       "file": "src/auth/token-service.ts",
       "line": 42
     },
     "fix": {
       "file": "src/auth/token-service.ts",
       "diff_summary": "Added expiresIn parameter to jwt.sign call",
       "lines_changed": [42, 43]
     }
   }
   ```
3. **Generalization:** At LEARN, the retrospective generalizes the pair:
   - Strip file paths (replace with pattern: `**/auth/*` or `**/*Service*`)
   - Strip domain-specific names (replace `UserToken` with `{entity}Token`)
   - Extract the pattern: "When calling jwt.sign, always include expiresIn"
   - Extract the detection: regex or AST pattern that catches the pre-fix state
4. **Deduplication:** Compare against existing rules by `(category, generalized_description)` similarity (>80% fuzzy match = duplicate). If duplicate: increment hit count on existing rule.
5. **Output:** A CANDIDATE_RULE item in the inbox, or an updated hit count on an existing rule.

### Rules vs Memories Distinction

Following the Windsurf model, Forge distinguishes two knowledge types:

| Dimension | Rules | Memories |
|---|---|---|
| Nature | Coding standards, conventions, constraints | Decisions, discoveries, project context |
| Source | Review findings, convention violations, security patterns | Retrospective observations, user corrections, domain insights |
| Scope | Cross-project (generalizable) | Project-specific |
| Storage | `.forge/knowledge/rules.json` + convention stack | `.claude/forge-log.md` (PREEMPT items) |
| Lifecycle | CANDIDATE → VALIDATED → ACTIVE → ARCHIVED | Standard PREEMPT lifecycle |
| Application | L1/L2 check engine (if regex), reviewer pre-context (always) | Agent pre-context at PREFLIGHT |
| Examples | "Never use `any` type in TypeScript public APIs", "All API responses must include `traceId`" | "This project uses hexagonal architecture", "The billing module has known N+1 issues" |

**Promotion path:** A memory that recurs across 5+ projects and is stripped of project-specific context can be promoted to a rule. The retrospective flags candidates; plugin maintainers review before adding to `shared/learnings/`.

### Storage Format

#### Directory Structure

```
.forge/knowledge/
+-- inbox/                          # Pending items from current run
|   +-- candidate-{timestamp}-{agent}.json
+-- rules.json                      # Validated and active rules
+-- patterns.json                   # Discovered codebase patterns
+-- root-causes.json                # Root cause patterns from bugfixes
+-- metrics.json                    # Application tracking and effectiveness
```

#### rules.json Schema

```json
{
  "schema_version": "1.0.0",
  "rules": [
    {
      "id": "rule-sec-jwt-exp-001",
      "state": "ACTIVE",
      "category": "SEC-AUTH",
      "description": "JWT tokens must include exp claim with max TTL",
      "detection_pattern": "jwt\\.sign\\(.*\\)(?!.*expiresIn|exp)",
      "detection_type": "regex",
      "recommended_fix": "Add expiresIn parameter to jwt.sign call",
      "applicable_contexts": ["auth", "api"],
      "applicable_languages": ["typescript", "javascript"],
      "source_agent": "fg-411-security-reviewer",
      "severity_default": "CRITICAL",
      "confidence": "HIGH",
      "created_at": "2026-04-10T10:00:00Z",
      "last_applied": "2026-04-13T10:15:00Z",
      "application_count": 7,
      "false_positive_count": 0,
      "effectiveness_score": 1.0,
      "promoted_from": "candidate-20260410-fg411.json",
      "source": "learned-rule"
    }
  ]
}
```

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique identifier: `rule-{category_slug}-{NNN}` |
| `state` | string | Lifecycle state: `CANDIDATE`, `VALIDATED`, `ACTIVE`, `ARCHIVED`, `REJECTED` |
| `category` | string | Finding category this rule relates to (from `category-registry.json`) |
| `description` | string | Human-readable description of the rule |
| `detection_pattern` | string | Regex or natural-language pattern to detect the issue |
| `detection_type` | string | `regex` (can be integrated into L1 check engine) or `semantic` (requires agent review) |
| `recommended_fix` | string | Concrete action to resolve |
| `applicable_contexts` | string[] | Domain areas where the rule applies (from `domain-detection.md`) |
| `applicable_languages` | string[] | Languages this rule applies to (empty = all) |
| `source_agent` | string | Agent that originally created the rule |
| `severity_default` | string | Default severity when the rule triggers |
| `confidence` | string | `LOW`, `MEDIUM`, `HIGH` — tracks rule reliability |
| `created_at` | string | ISO 8601 creation timestamp |
| `last_applied` | string | ISO 8601 timestamp of last successful application |
| `application_count` | integer | Times this rule has been applied |
| `false_positive_count` | integer | Times this rule triggered but was irrelevant |
| `effectiveness_score` | float | `application_count / (application_count + false_positive_count)` |
| `promoted_from` | string | Filename of the inbox item that created this rule |
| `source` | string | `learned-rule` (from review finding+fix), `manual` (user-authored), `auto-discovered` (from memory discovery) |

#### patterns.json Schema

```json
{
  "schema_version": "1.0.0",
  "patterns": [
    {
      "id": "pattern-persistence-result-001",
      "state": "ACTIVE",
      "domain": "persistence",
      "description": "Repository classes use Result<T, DomainError> return type",
      "pattern": "class *Repository.*fun .*: Result<",
      "evidence_file_count": 5,
      "confidence": "HIGH",
      "application_count": 3,
      "false_positive_count": 0,
      "created_at": "2026-04-08T10:00:00Z",
      "last_applied": "2026-04-13T10:20:00Z",
      "source": "pattern-discovery"
    }
  ]
}
```

#### root-causes.json Schema

```json
{
  "schema_version": "1.0.0",
  "root_causes": [
    {
      "id": "rc-persistence-lazy-001",
      "state": "ACTIVE",
      "category": "persistence",
      "description": "Lazy-loaded collections accessed outside transaction boundary",
      "detection_hint": "Collection property access after repository findById without @Transactional",
      "prevention_rule": "Ensure @Transactional on service methods that access lazy collections, or use JOIN FETCH",
      "confidence": "HIGH",
      "occurrence_count": 3,
      "last_occurred": "2026-04-13T10:25:00Z",
      "created_at": "2026-04-05T10:00:00Z",
      "source": "root-cause-pattern"
    }
  ]
}
```

#### metrics.json Schema

```json
{
  "schema_version": "1.0.0",
  "total_rules": 15,
  "active_rules": 10,
  "total_applications": 42,
  "total_false_positives": 3,
  "overall_effectiveness": 0.93,
  "top_rules_by_application": ["rule-sec-jwt-exp-001", "rule-arch-boundary-002"],
  "rules_promoted_to_convention": ["rule-conv-naming-003"],
  "last_updated": "2026-04-13T10:30:00Z"
}
```

### Agent-Level Contribution Hooks

Each contributing agent writes to `.forge/knowledge/inbox/` during its execution:

| Agent | Contribution Type | Trigger |
|---|---|---|
| `fg-411-security-reviewer` | `CANDIDATE_RULE` | When a security finding reveals a general pattern (not project-specific) |
| `fg-412-architecture-reviewer` | `CANDIDATE_RULE` | When an architectural violation represents a convention worth enforcing |
| `fg-410-code-reviewer` | `CANDIDATE_RULE` | When a code quality finding reveals a recurring anti-pattern |
| `fg-413-frontend-reviewer` | `CANDIDATE_RULE` | When a frontend finding reveals a reusable design/perf rule |
| `fg-416-backend-performance-reviewer` | `CANDIDATE_RULE` | When a performance finding reveals a general optimization pattern |
| `fg-300-implementer` | `PATTERN_DISCOVERY` | When it observes consistent patterns across 3+ files during implementation |
| `fg-020-bug-investigator` | `ROOT_CAUSE_PATTERN` | When root cause analysis reveals a systemic issue pattern |
| `fg-400-quality-gate` | (finding, fix) pair | When a finding is fixed by the implementer, records the pair for rule learning |

**Contribution constraints:**
- Maximum 3 inbox items per agent per run (prevents noise)
- Inbox items must include `evidence` (file path, line, finding ID) — unsubstantiated items are rejected
- Tier 4 agents (reviewers) can write to inbox but cannot write to rules.json directly (only retrospective promotes)

### PREEMPT Integration

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

At PREFLIGHT, the orchestrator loads:
1. Standard PREEMPT items from `.claude/forge-log.md` (existing)
2. Active rules from `.forge/knowledge/rules.json` (new — converted to PREEMPT format)
3. Active patterns from `.forge/knowledge/patterns.json` (new — converted to PREEMPT format)
4. Active root causes from `.forge/knowledge/root-causes.json` (new — converted to PREEMPT format)

Deduplication: if a learned rule overlaps with an existing PREEMPT item (>80% description similarity), the higher-confidence item wins.

### Check Engine Integration

Rules with `detection_type: "regex"` can be automatically promoted to L1 check engine patterns:

1. When a rule reaches ACTIVE state with HIGH confidence and `detection_type: "regex"`:
   - The retrospective writes an entry to `.forge/knowledge/learned-rules-override.json`
   - This file follows the same format as `rules-override.json`
   - The check engine loads it in addition to the standard `rules-override.json`
2. The learned rule becomes an L1 check — sub-second detection on every `Edit`/`Write`
3. If the rule produces false positives in L1 (detected by retrospective from `PREEMPT_SKIPPED` reports), it is demoted back to agent-level review only

### Configuration

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

### Data Flow

#### During Execution

1. Agent detects a knowledge-worthy pattern
2. Agent writes a JSON file to `.forge/knowledge/inbox/candidate-{timestamp}-{agent}.json`
3. Quality gate tracks (finding, fix) pairs for rule learning
4. Orchestrator does NOT process inbox during the run — items accumulate

#### At LEARN Stage

1. Retrospective reads all files from `.forge/knowledge/inbox/`
2. For each CANDIDATE_RULE:
   a. Verify evidence (file exists, finding was indeed emitted)
   b. Check for duplicate in `rules.json` (>80% description match)
   c. If duplicate: increment `application_count` on existing rule
   d. If new and valid: create VALIDATED entry in `rules.json`
   e. If invalid: create REJECTED entry (logged but not loaded)
3. For each PATTERN_DISCOVERY:
   a. Verify evidence (referenced files exist and match pattern)
   b. Check for duplicate in `patterns.json`
   c. If new: add to `patterns.json` with `confidence: MEDIUM`
4. For each ROOT_CAUSE_PATTERN:
   a. Verify evidence (bug description matches, root cause file relevant)
   b. Check for duplicate in `root-causes.json`
   c. If new: add to `root-causes.json` with `confidence: MEDIUM`
5. For (finding, fix) pairs from quality gate:
   a. Generalize the pair (strip file paths, domain names)
   b. If generalization succeeds: create CANDIDATE_RULE from the pair
   c. Process as step 2 above
6. Update `metrics.json`
7. Clear `.forge/knowledge/inbox/`
8. Promote VALIDATED rules with 2+ applications to ACTIVE
9. Archive ACTIVE rules with effectiveness_score < 0.5

#### At PREFLIGHT (Next Run)

1. Load ACTIVE rules from `.forge/knowledge/rules.json`
2. Convert to PREEMPT format, inject into pipeline context
3. Load ACTIVE patterns and root causes similarly
4. For rules with `auto_promote_to_check_engine: true` and `detection_type: "regex"` and `confidence: "HIGH"`: verify `learned-rules-override.json` is current
5. Record loaded knowledge count in stage notes

### Error Handling

| Failure Mode | Behavior |
|---|---|
| Inbox write failure during execution | Log INFO, agent continues without contributing knowledge. Pipeline never blocks on knowledge writes. |
| rules.json corrupted | Delete and rebuild from inbox history and forge-log.md PREEMPT items. Log WARNING. |
| Retrospective fails to process inbox | Inbox items persist until next successful LEARN stage. Items in inbox older than 5 runs without processing are auto-archived with WARNING. |
| Too many rules (exceeds `max_rules`) | Evict lowest-effectiveness rules (by `effectiveness_score`, then by `last_applied`). |
| False positive rate exceeds threshold | Rule with `false_positive_count > 3 * application_count` is archived. Effectiveness alert in metrics. |
| Duplicate detection failure | Worst case: two similar rules coexist. Retrospective periodically scans for near-duplicates and merges. |
| `.forge/knowledge/` directory missing | Auto-created at PREFLIGHT when `knowledge.enabled: true`. |

## Performance Characteristics

| Operation | Expected Latency | Token Cost |
|---|---|---|
| Agent writes inbox item | <10ms | ~200 tokens (JSON serialization in agent output) |
| Retrospective processes inbox (10 items) | 1-3s | ~2,000 tokens (validation + generalization) |
| PREFLIGHT loads rules (100 rules) | <100ms | ~5,000 tokens (PREEMPT injection into context) |
| Rule deduplication check | <50ms per rule | 0 tokens (string similarity) |
| Learned-rules-override.json load | <10ms | 0 tokens (JSON parse) |

**Token budget impact:**
- Active contribution adds ~200 tokens per contributing agent per run (inbox writes)
- PREEMPT injection of learned rules adds ~50 tokens per active rule (proportional to rule count)
- At 100 active rules: ~5,000 additional context tokens at PREFLIGHT — within the convention stack soft cap of 12 files/component

## Testing Approach

### Unit Tests (`tests/unit/knowledge.bats`)

1. **Inbox write:** Verify agents can write inbox items in correct format
2. **Rule validation:** Verify retrospective validates evidence before promotion
3. **Deduplication:** Verify >80% description similarity triggers merge
4. **Lifecycle transitions:** CANDIDATE → VALIDATED → ACTIVE → ARCHIVED flow
5. **Effectiveness scoring:** Verify `application_count / (application_count + false_positive_count)` calculation
6. **Eviction:** Verify oldest/lowest-effectiveness rules are evicted when `max_rules` is exceeded
7. **Check engine promotion:** Verify regex rules with HIGH confidence generate `learned-rules-override.json`

### Integration Tests (`tests/integration/knowledge.bats`)

1. **Full cycle:** Run pipeline, verify inbox items are created during REVIEW, processed at LEARN, loaded at next PREFLIGHT
2. **Rule learning:** Emit a finding, fix it, verify (finding, fix) pair generates a CANDIDATE_RULE
3. **PREEMPT integration:** Create an ACTIVE rule, run pipeline, verify rule appears in PREEMPT context

### Scenario Tests

1. **Cross-run validation:** Rule created in run 1, applied in run 2, confirmed in run 3 → promoted to ACTIVE with HIGH confidence
2. **False positive handling:** Rule triggers in context where it is irrelevant, retrospective marks false positive, effectiveness decreases
3. **Check engine integration:** Regex rule reaches HIGH confidence → appears in L1 check engine → detects issue on next Edit

## Acceptance Criteria

1. Reviewer agents, implementer, and bug investigator can write structured knowledge items to `.forge/knowledge/inbox/` during execution
2. Retrospective processes inbox items: validates evidence, deduplicates, and promotes valid items to `rules.json`, `patterns.json`, or `root-causes.json`
3. Quality gate captures (finding, fix) pairs and the retrospective generalizes them into CANDIDATE_RULE items
4. Rules follow the lifecycle: CANDIDATE → VALIDATED → ACTIVE → ARCHIVED, with clear promotion and decay criteria
5. Active rules are loaded as PREEMPT items at PREFLIGHT and contribute to agent pre-context
6. Rules with `detection_type: "regex"` and HIGH confidence are automatically promoted to L1 check engine patterns via `learned-rules-override.json`
7. Maximum 3 inbox items per agent per run (configurable)
8. Maximum 100 active rules (configurable) with eviction of lowest-effectiveness rules
9. `metrics.json` tracks total rules, applications, false positives, and effectiveness
10. Knowledge base survives `/forge-reset`. Only `/forge-reset --hard` or manual deletion removes it.
11. `validate-plugin.sh` passes with the new knowledge infrastructure added

## Migration Path

1. **v2.0.0:** Create `.forge/knowledge/` directory structure. Add `knowledge:` section to `forge-config-template.md` for all frameworks.
2. **v2.0.0:** Update `fg-700-retrospective.md` to process inbox items. Add knowledge contribution guidelines to relevant agent `.md` files (fg-410 through fg-420, fg-300, fg-020, fg-400).
3. **v2.0.0:** Update `fg-100-orchestrator.md` to load rules at PREFLIGHT and inject into PREEMPT context.
4. **v2.0.0:** Add `learned-rules-override.json` support to `shared/checks/engine.sh` (load alongside existing `rules-override.json`).
5. **v2.0.0:** Add `.forge/knowledge/` to the "Survives /forge-reset" file list in `state-schema.md`.
6. **v2.0.0:** Update `shared/learnings/README.md` to document the rules-vs-memories distinction.
7. **No breaking changes:** Existing PREEMPT items and learnings are unaffected. The knowledge base is additive. Projects without knowledge items function identically to v1.x.

## Dependencies

**Depends on:**
- Existing: PREEMPT lifecycle (`shared/learnings/README.md`), memory discovery (`shared/learnings/memory-discovery.md`), quality gate finding/fix tracking, retrospective agent, check engine (`shared/checks/engine.sh`)
- Existing: `shared/checks/category-registry.json` (for rule category validation)

**Depended on by:**
- F06 (Confidence Scoring): active learned rules contribute to the familiarity dimension of confidence scoring
- F10 (Enhanced Security): learned SEC-* rules feed into enhanced security detection
