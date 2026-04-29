# Cross-Project Learnings

Cross-project learnings enable knowledge transfer between projects using the same tech stack.

## Storage

Location: `~/.claude/forge-learnings/`

```
~/.claude/forge-learnings/
├── spring.md        # Spring-specific learnings
├── react.md         # React-specific learnings
├── typescript.md    # Language-specific learnings
├── general.md       # Framework-agnostic learnings
└── _index.json      # Metadata: last update timestamps, entry counts
```

## Write Path (fg-700-retrospective)

1. After writing per-project learnings to `shared/learnings/{framework}.md`
2. Also append validated HIGH-confidence learnings to `~/.claude/forge-learnings/{framework}.md`
3. Deduplicate: if a learning with the same core pattern already exists, update rather than append
4. Tag each learning with project name and date for provenance

## Read Path (fg-100-orchestrator at PREFLIGHT)

1. Detect project's framework(s) from `forge.local.md`
2. If `~/.claude/forge-learnings/{framework}.md` exists, load it
3. Also load `~/.claude/forge-learnings/general.md` if it exists
4. Inject as additional PREEMPT items with `source: cross-project` and initial confidence `MEDIUM`
5. Cross-project items promote to HIGH after 2 successful applications (applied + pipeline reached REVIEWING without false positive flag)

## Configuration

`cross_project_learnings.enabled: true` (default) in `forge-config.md`. Set to `false` to disable.

## Privacy

Cross-project files contain generic patterns, not project-specific code or secrets. Example: "Spring @Transactional should be on use case implementations, not repository methods" — no file paths, no business logic.

## Error Handling

If `~/.claude/forge-learnings/` is not writable (read-only home dir, network mount), skip silently at PREFLIGHT. Log as INFO: "Cross-project learnings unavailable, skipping."

---

## Selector Interaction (Phase 4)

The learnings selector (`hooks/_py/learnings_selector.py`) ranks every
candidate — including those loaded from `~/.claude/forge-learnings/` — by:

```
score = confidence_now * domain_match_score * recency_bonus * cross_project_penalty
```

`cross_project_penalty` drops cross-project items to **0.85** of their
score **only when** the active project has more than
`SPARSE_THRESHOLD` (default 10; see `hooks/_py/memory_decay.py`) local
candidates for the relevant framework/component. Sparse projects —
fewer than 10 locally sourced learnings — therefore benefit fully from
cross-project priors; dense projects down-weight them in favour of
local evidence.

Tune `SPARSE_THRESHOLD` by editing `hooks/_py/memory_decay.py` (constant
module-level). Do not duplicate the constant elsewhere — the selector and
any tests import it from that single source.
