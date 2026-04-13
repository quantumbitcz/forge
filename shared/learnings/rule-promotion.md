# Rule Promotion Algorithm

Describes how recurring review findings are promoted from observations to automated L1 check engine rules.

## Pipeline

```
fg-700 (retrospective, LEARNING stage)
  → identifies recurring findings (3+ occurrences across runs)
  → writes candidates to .forge/learned-candidates.json

fg-100 (orchestrator, PREFLIGHT of next run)
  → reads learned-candidates.json
  → validates candidates: has pattern, severity, category, language
  → promotes to shared/checks/learned-rules-override.json
  → logs promotion in forge-log.md
```

## Candidate Schema

```json
{
  "candidates": [
    {
      "id": "LEARNED-001",
      "pattern": "console\\.log\\(",
      "replacement": "Use logger.debug() instead of console.log()",
      "severity": "WARNING",
      "category": "QUAL-LOGGING",
      "language": "typescript",
      "occurrences": 5,
      "runs_seen": 3,
      "first_seen": "2026-04-01",
      "last_seen": "2026-04-13",
      "confidence": "MEDIUM",
      "source": "fg-410-code-reviewer",
      "status": "candidate"
    }
  ]
}
```

### Status Values

| Status | Meaning |
|--------|---------|
| `candidate` | Observed but below promotion threshold |
| `ready_for_promotion` | Threshold met, awaiting PREFLIGHT promotion |
| `promoted` | Active in learned-rules-override.json |
| `demoted` | Removed after 5 inactive runs (decay) |

## Promotion Rules

1. **Threshold:** >=3 occurrences across >=2 pipeline runs (`runs_seen >= 2`)
2. **Confidence gate:** Only MEDIUM or HIGH confidence findings eligible
3. **No duplicates:** Check against existing L1 patterns and `rules-override.json` before promoting
4. **Language match:** Candidate must specify language; promoted to language-specific pattern file format
5. **Validation:** Promoted rule must have valid regex pattern (test with `grep -P` before promoting)

## Decay Rules

1. After each pipeline run, increment `inactive_runs` counter for promoted rules that produced 0 matches
2. If `inactive_runs >= 5`: demote rule (remove from `learned-rules-override.json`, update status in candidates)
3. Log demotion in `forge-log.md`: "Demoted LEARNED-NNN: 5 consecutive inactive runs"
4. Demoted rules can be re-promoted if they re-appear in future reviews

## Promoted Rule Format

Promoted rules are written to `shared/checks/learned-rules-override.json` in the same format as `rules-override.json`:

```json
{
  "rules": [
    {
      "id": "LEARNED-001",
      "pattern": "console\\.log\\(",
      "severity": "WARNING",
      "category": "QUAL-LOGGING",
      "message": "Use logger.debug() instead of console.log()",
      "language": "typescript",
      "promoted_from": "LEARNED-001",
      "promoted_at": "2026-04-13T10:30:00Z"
    }
  ]
}
```

## Files

| File | Purpose |
|------|---------|
| `.forge/learned-candidates.json` | Candidate tracking (per-project, survives /forge-reset) |
| `shared/checks/learned-rules-override.json` | Promoted rules loaded by engine (plugin-level) |
| `.forge/forge-log.md` | Promotion/demotion audit trail |
