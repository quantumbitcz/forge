# Domain Detection

## Why This Matters

Every downstream learning subsystem — PREEMPT decay, auto-tuning, bug hotspot tracking — keys on `state.json.domain_area`. If domain detection is wrong or missing, PREEMPT items decay against the wrong domain, auto-tuning adjusts the wrong weights, and bug hotspots accumulate under a meaningless label. The drift is silent: no error, no warning, just a learning system that gradually becomes less useful.

Making domain detection a first-class operation with a formal algorithm, validation rules, and logging requirements prevents this drift.

## Detection Algorithm

The planner (`fg-200-planner`) executes the following algorithm at Stage 2 before producing the plan output. The orchestrator validates the result.

### Step 1: Extract Signals

Scan the files touched by the requirement (from exploration results) and the requirement text itself. Map file paths and keywords to domain signals:

| Path / Keyword Pattern | Domain Signal |
|---|---|
| `*/auth/*`, `*/login/*`, `*/oauth/*`, `*/session/*` | auth |
| `*/billing/*`, `*/payment/*`, `*/invoice/*`, `*/subscription/*` | billing |
| `*/user/*`, `*/profile/*`, `*/account/*` | user |
| `*/schedule/*`, `*/calendar/*`, `*/booking/*`, `*/appointment/*` | scheduling |
| `*/notification/*`, `*/email/*`, `*/sms/*`, `*/chat/*`, `*/message/*` | communication |
| `*/inventory/*`, `*/stock/*`, `*/warehouse/*`, `*/product/*` | inventory |
| `*/workflow/*`, `*/pipeline/*`, `*/approval/*`, `*/state-machine/*` | workflow |
| `*/cart/*`, `*/order/*`, `*/checkout/*`, `*/catalog/*` | commerce |
| `*/search/*`, `*/index/*`, `*/query/*` | search |
| `*/analytics/*`, `*/metrics/*`, `*/dashboard/*`, `*/report/*` | analytics |
| `*/config/*`, `*/settings/*`, `*/preferences/*` | config |
| `*/api/*`, `*/gateway/*`, `*/endpoint/*`, `*/route/*` | api |
| `*/infra/*`, `*/deploy/*`, `*/ci/*`, `*/docker/*`, `*/k8s/*` | infra |

### Step 2: Vote

Count signals per domain. The domain with the most signals wins. On a tie, prefer the domain that appears in the requirement text. If still tied, prefer the first alphabetically.

### Step 3: Validate

The detected domain must be:
- Lowercase
- A single word (no spaces, hyphens, or underscores)
- One of the known domains listed below, OR `general` as fallback

If no signals are found or the result does not match a known domain, fall back to `general`.

### Step 4: Log

The planner must log domain detection in its stage notes with:
- **Signals**: list of `(pattern, domain, count)` tuples found
- **Confidence**: `high` (>= 5 signals for winning domain), `medium` (2-4 signals), `low` (1 signal or fallback)
- **Fallback**: whether `general` was used and why (no signals / ambiguous / unknown domain)

## Known Domains

The following are the recognized domain values for `state.json.domain_area`:

`auth`, `billing`, `user`, `scheduling`, `communication`, `inventory`, `workflow`, `commerce`, `search`, `analytics`, `config`, `api`, `infra`, `general`

`general` is the fallback domain used when detection produces no clear result.

## Validation Rules

1. `domain_area` must be non-empty after Stage 2 completes.
2. The value must be lowercase and a single word.
3. If the planner fails to set `domain_area`, the orchestrator defaults to `general` and emits a WARNING.
4. `domain_area` is immutable after Stage 2 — no later stage may change it.

## Impact on Learning System

- **PREEMPT decay**: Items decay per-domain. Wrong domain = items decay against unrelated changes, inflating false-positive counts.
- **Auto-tuning**: Retrospective adjusts scoring weights per domain. Wrong domain = weight adjustments applied to the wrong category.
- **Bug hotspots**: Hotspot frequency is tracked per domain. Wrong domain = hotspot signals scattered across irrelevant domains, reducing pattern detection accuracy.
