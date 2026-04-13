# Autonomous Memory Discovery

The memory discovery system enables the pipeline to automatically identify recurring structural patterns, naming conventions, and configuration quirks across multiple runs — without requiring explicit user input. Discovered patterns are surfaced as PREEMPT items for downstream agents to apply proactively.

## Discovery Categories

| Category | Description | Example |
|---|---|---|
| Naming patterns | Consistent naming conventions across files, variables, classes, or modules | Services always suffixed with `Service`, repositories with `Repository`; test files use `.spec.ts` not `.test.ts` |
| Architecture decisions | Structural choices that repeat across components | Hexagonal architecture with `ports/` and `adapters/` directories; all API responses wrapped in `ApiResponse<T>` |
| Test patterns | Recurring testing conventions beyond framework defaults | Every integration test uses `@Testcontainers`; fixtures follow `{entity}-fixture.json` naming |
| Configuration quirks | Non-obvious configuration choices that affect correctness | `spring.jpa.open-in-view=false` required for lazy-loading safety; `strictNullChecks` always enabled in `tsconfig.json` |
| Dependency patterns | Consistent library selection and version pinning strategies | Always use `kotlinx-datetime` over `java.time` in shared modules; `zod` preferred over `yup` for validation |
| Error patterns | Recurring error handling conventions | All domain exceptions extend `DomainException` base class; HTTP errors always include `errorCode` and `traceId` fields |

## Discovery Flow

The discovery process spans multiple pipeline stages and accumulates evidence across runs:

1. **EXPLORE** — notes structural patterns in stage notes (directory layout, file naming, module organization)
2. **REVIEW** — notes coding conventions, style patterns, and architectural consistency in findings
3. **LEARN** (retrospective) — compares patterns observed in current run with patterns from previous runs stored in `.claude/forge-log.md`
4. **Candidate threshold** — a pattern observed in 2+ runs becomes a **candidate**
5. **Evidence confirmation** — candidate with evidence from 3+ files (matching the pattern) is promoted to a PREEMPT item with `source: auto-discovered` and `confidence: MEDIUM`

### Stage responsibilities

- `fg-100-orchestrator`: passes relevant stage notes between stages
- `fg-700-retrospective`: reads stage notes from EXPLORE and REVIEW, compares with previous run patterns, generates discovery candidates
- `fg-710-post-run`: persists confirmed discoveries to `.claude/forge-log.md`

## PREEMPT Item Format

Discovered patterns are stored as PREEMPT items with the following fields:

```markdown
### auto-{repo}-{pattern}-{NNN}: {short title}
- **Source:** auto-discovered
- **Confidence:** MEDIUM
- **Evidence:**
  - files_matching: [{list of files confirming the pattern}]
  - files_violating: [{list of files breaking the pattern, if any}]
  - pattern: "{regex or description of the structural pattern}"
- **Decay multiplier:** 2
- **Discovered run:** {run_id}
- **Domain:** {area — e.g., naming, architecture, testing, configuration}
- **Pattern:** {what to do or avoid}
- **Hit count:** 0
```

### Field reference

| Field | Value | Description |
|---|---|---|
| `id` | `auto-{repo}-{pattern}-{NNN}` | Unique identifier. `repo` = short repo name, `pattern` = category slug, `NNN` = sequential |
| `source` | `auto-discovered` | Distinguishes from manually authored PREEMPT items |
| `confidence` | `MEDIUM` (initial) | Starting confidence for all discoveries |
| `evidence.files_matching` | list of file paths | Files that conform to the discovered pattern (min 3) |
| `evidence.files_violating` | list of file paths | Files that break the pattern (may be empty) |
| `evidence.pattern` | string | Regex or natural-language description of the pattern |
| `decay_multiplier` | `2` | Auto-discovered items decay 2x faster than manually authored ones |
| `discovered_run` | run ID string | The pipeline run that first confirmed the pattern |

## Promotion and Decay

### Promotion

| Current confidence | Condition | Action |
|---|---|---|
| MEDIUM | Applied successfully in 3 consecutive runs | Promote to HIGH |
| HIGH | 5+ applications AND stable across 10+ runs | Candidate for permanent convention rule |

Users can manually promote any discovery to HIGH via forge-log.md annotation or dismiss it entirely.

### Decay

Auto-discovered items use `decay_multiplier: 2`, meaning they decay twice as fast as standard PREEMPT items:

| Current confidence | Standard decay | Auto-discovered decay (2x) |
|---|---|---|
| HIGH → MEDIUM | 10 unused runs | 5 unused runs |
| MEDIUM → LOW | 10 unused runs | 5 unused runs |
| LOW → ARCHIVED | 10 unused runs | 5 unused runs |

False positive confirmed by retrospective: counts as `3 × decay_multiplier = 6` unused runs toward demotion (standard is 3).

## Configuration

All settings are defined in `forge-config.md` or `forge.local.md` under the `memory_discovery` section:

```yaml
memory_discovery:
  enabled: true                   # Enable/disable autonomous discovery
  max_discoveries_per_run: 5      # Maximum new discoveries per pipeline run
  min_evidence_files: 3           # Minimum files required to confirm a pattern
  auto_promote_after_runs: 3      # Successful applications before MEDIUM → HIGH
```

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `enabled` | boolean | `true` | — | Master toggle for the discovery system |
| `max_discoveries_per_run` | integer | `5` | 1-20 | Cap on new PREEMPT items created per run |
| `min_evidence_files` | integer | `3` | 2-10 | Minimum matching files to confirm a candidate |
| `auto_promote_after_runs` | integer | `3` | 2-10 | Consecutive successful applications before promotion |

## Constraints

1. **Maximum 5 discoveries per run** — prevents noise from overwhelming downstream agents
2. **Minimum 3 evidence files** — ensures patterns are genuine, not coincidental
3. **Clearly labeled in forge-log.md** — all auto-discovered items are prefixed with `auto-` in their ID and marked with `source: auto-discovered` for easy identification
4. **User override** — users can promote any discovery to HIGH confidence or dismiss it by editing forge-log.md
5. **No project-specific data in shared learnings** — discovered patterns follow the same privacy guarantees as standard learnings (see `shared/learnings/README.md`)
6. **Idempotent** — re-running the same pipeline on the same codebase does not create duplicate discoveries

## Integration with Retrospective

The `fg-700-retrospective` agent drives the discovery process:

1. **Read stage notes** — collects structural observations from EXPLORE and convention observations from REVIEW
2. **Load previous patterns** — reads existing auto-discovered items from `.claude/forge-log.md`
3. **Compare across runs** — identifies patterns that recur across the current and previous runs
4. **Generate candidates** — patterns observed in 2+ runs with sufficient evidence become candidates
5. **Confirm or discard** — candidates meeting `min_evidence_files` threshold are written as PREEMPT items; others are logged but not persisted
6. **Update existing** — increments hit counts and adjusts confidence for previously discovered patterns that were applied in this run
