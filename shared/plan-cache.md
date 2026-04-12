# Plan Cache

Caches PLAN stage outputs in `.forge/plan-cache/` for reuse when similar requirements arise. Before dispatching the planner, the orchestrator checks if a cached plan can serve as a starting point.

## Directory Structure

    .forge/plan-cache/
    +-- index.json
    +-- plan-2026-04-10-add-comments.json
    +-- plan-2026-04-08-auth-middleware.json

## Cache Entry Schema

Each `plan-{date}-{slug}.json`:

```json
{
  "schema_version": "1.0.0",
  "requirement": "Add plan comment feature with threading",
  "requirement_keywords": ["plan", "comment", "threading", "feature"],
  "domain_area": "plan",
  "plan_hash": "sha256:abc123",
  "stories_count": 4,
  "final_score": 94,
  "created_at": "2026-04-10T10:00:00Z",
  "source_sha": "def456",
  "plan_content": "... full plan markdown ..."
}
```

| Field | Type | Description |
|-------|------|-------------|
| `requirement` | string | Original requirement text |
| `requirement_keywords` | string[] | Extracted keywords (nouns, verbs, domain terms — lowercase, deduplicated) |
| `domain_area` | string | Detected domain from `shared/domain-detection.md` |
| `plan_hash` | string | SHA256 of `plan_content` |
| `stories_count` | integer | Number of stories in the plan |
| `final_score` | integer | Quality score the plan achieved (0 if run didn't complete) |
| `created_at` | string | ISO 8601 creation timestamp |
| `source_sha` | string | Git commit SHA when plan was created |
| `plan_content` | string | Full plan markdown content |

## Index Schema

`index.json`:

```json
{
  "schema_version": "1.0.0",
  "entries": [
    {
      "file": "plan-2026-04-10-add-comments.json",
      "requirement_keywords": ["plan", "comment", "threading"],
      "domain_area": "plan",
      "final_score": 94,
      "created_at": "2026-04-10T10:00:00Z"
    }
  ]
}
```

## Similarity Algorithm

1. Extract keywords from the new requirement: split on whitespace/punctuation, lowercase, remove stop words (the, a, an, is, are, to, for, in, on, of, with, and, or, by, from, this, that), deduplicate
2. For each entry in `index.json`:
   a. Compute Jaccard similarity: `|A ∩ B| / |A ∪ B|` where A = new keywords, B = cached keywords
   b. If `domain_area` matches: bonus +0.1 to similarity score
3. If highest similarity >= 0.6: offer cached plan as starting point
4. If multiple plans >= 0.6: use the one with highest `final_score`

**Known limitation:** Jaccard is brittle for short texts with varied wording. Acceptable for v1 — cache is an optimization, not a requirement. Future: embedding-based similarity.

## Orchestrator Integration

At PLAN stage, before dispatching `fg-200-planner`:
1. Check if `.forge/plan-cache/index.json` exists
2. If exists: run similarity algorithm against current requirement
3. If match found (>= 0.6): include cached plan in planner dispatch prompt:

       A similar requirement was previously planned. The cached plan is provided as a
       starting point — adapt it to the current requirement, do not copy it verbatim.

       Cached plan (from: {created_at}, score: {final_score}):
       {plan_content}

4. If no match: normal plan dispatch (no cached context)
5. Record cache status in `stage_2_notes`: "Plan cache: hit (similarity 0.73, domain: plan) / miss"

After PLAN completes successfully AND the run reaches SHIP:
1. Save current plan to `.forge/plan-cache/plan-{date}-{slug}.json`
2. Update `index.json`
3. Run eviction (see below)

Plans from runs that did not reach SHIP are NOT cached (the plan may be flawed).

## Eviction Rules

| Rule | Action |
|------|--------|
| Entries > 20 | Remove oldest by `created_at` (LRU) |
| Entry older than 30 days | Remove |
| `final_score` < `pass_threshold` | Remove (plan quality was insufficient) |

Eviction runs after each new plan is cached.

## Configuration

In `forge-config.md`:

    plan_cache:
      enabled: true
      similarity_threshold: 0.6
      max_entries: 20
      max_age_days: 30

## /forge-reset Behavior

`/forge-reset` preserves `.forge/plan-cache/` (same as explore cache). Only `/forge-reset --hard` or manual deletion removes it.
