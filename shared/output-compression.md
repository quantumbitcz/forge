# Output Compression

Per-stage output verbosity system that constrains agent output for inter-agent communication. Agents generate terse output natively via system prompt injection. Not post-processing.

## Verbosity Levels

| Level | Name | Token Range | Savings (prose-only) | Session Savings (est.) | Use When |
|-------|------|-------------|----------------------|------------------------|----------|
| 0 | `verbose` | 800-2000 | 0% | 0% | User-facing reports, escalation messages |
| 1 | `standard` | 800-2000 | ~20% | ~2-4% | Planning, documentation, retrospective |
| 2 | `terse` | 400-1200 | ~45% | ~4-7% | Implementation, verification, review findings |
| 3 | `minimal` | 100-600 | ~65% | ~6-10% | Inner-loop lint/test, mutation analysis, scaffolding |

### Level 0 (verbose)

Normal LLM output. No constraints. Used for user-facing content, PR descriptions, escalation messages.

### Level 1 (standard)

Drop pleasantries and preamble. Keep full sentences.

```
Drop: pleasantries (sure/certainly/I'd be happy to), restated context
      (as you mentioned/based on the requirement), transition phrases
      (moving on to/now let's look at).
Keep: full sentences, technical detail, code blocks, error messages.
```

### Level 2 (terse)

Drop articles, filler, hedging. Pattern: `[subject] [action] [reason]. [next step].`

```
OUTPUT COMPRESSION — TERSE MODE

Drop: articles (a/an/the), filler (just/really/basically/simply),
pleasantries (sure/certainly/I'd be happy to), hedging (perhaps/might/
you could consider), restated context (as you mentioned/based on the
requirement), transition phrases (moving on to/now let's look at).

Keep: technical terms exact, code blocks unchanged, error messages
verbatim, file paths, line numbers, finding categories, severity levels.

Pattern: [subject] [action] [reason]. [next step].

Examples:
  BEFORE: "I've analyzed the authentication middleware and I believe there
           might be a potential issue with how the session tokens are being
           validated. The problem appears to be that..."
  AFTER:  "Auth middleware: session token validation skips expiry check.
           Fix: add `isExpired()` guard before `verify()`."

  BEFORE: "Looking at the test results, it seems like 3 tests are failing.
           Let me investigate each one to understand the root cause..."
  AFTER:  "3 tests failing. Investigating root causes."
```

### Level 3 (minimal)

Structured data only. No prose sentences.

```
OUTPUT COMPRESSION — MINIMAL MODE

Output ONLY structured data. No prose sentences.
Findings: pipe-delimited format per output-format.md
Test results: pass/fail counts, failing test names
Lint results: file:line: issue
Code: code blocks only, no explanation unless ambiguous

Example stage notes (VERIFY):
  Tests: 42 passed, 3 failed, 2 skipped (12.3s)
  Failing: UserServiceTest#testExpiry, AuthTest#testRefresh, CacheTest#testEvict
  Lint: 0 issues
  Build: OK (4.2s)
```

> **Single source of truth:** This table is authoritative. The YAML template in the Configuration section below MUST mirror these values. If they diverge, this table wins.

## Per-Stage Default Assignments

| Stage | Default Level | Rationale |
|-------|--------------|-----------|
| PREFLIGHT | `standard` (1) | Setup output read by humans in dry-run |
| EXPLORING | `standard` (1) | Analysis cached in explore-cache, needs clarity |
| PLANNING | `standard` (1) | Plans reviewed by users at MEDIUM confidence |
| VALIDATING | `terse` (2) | Validation output consumed only by orchestrator |
| IMPLEMENTING | `terse` (2) | Code focus, minimal prose between edits |
| VERIFYING | `minimal` (3) | Test results, lint output — structured data |
| REVIEWING | `terse` (2) | Findings in pipe-delimited format already |
| DOCUMENTING | `standard` (1) | Documentation output must be readable |
| SHIPPING | `standard` (1) | PR descriptions are user-facing artifacts |
| LEARNING | `standard` (1) | Retrospective reports read by humans |

## Auto-Clarity Safety Valve

Compression automatically suspends (reverts to verbose, level 0) for these triggers:

1. **Security warnings** — `SEC-*` CRITICAL findings get full prose explanation
2. **Irreversible action confirmations** — destructive operations described clearly
3. **User-facing output** — `AskUserQuestion` content, PR descriptions (fg-600), and user-visible reports are never compressed
4. **Escalation messages** — convergence failures, budget exhaustion, abort recommendations
5. **Coordinator structured output** — `FORGE_STRUCTURED_OUTPUT` JSON blocks are never omitted or compressed. Coordinators (fg-400, fg-500, fg-700) are capped at level 2 (terse) maximum — never level 3 (minimal), to preserve the Markdown + JSON contract from `agent-communication.md` §10.
6. **Error diagnostics** — when an agent is explaining a build failure, test failure, or runtime error to the user (not inter-agent error reporting), revert to verbose for the diagnostic block. Detection: output contains error stack trace or `BUILD_FAILURE`/`TEST_FAILURE`/`LINT_FAILURE` classification AND is destined for user consumption (not stage notes).

Detection: agents check the output type. If emitting a finding with `SEC-*` CRITICAL, using `AskUserQuestion`, writing a user-visible report, producing a PR description, or explaining an error diagnostic to the user, switch to `verbose` (level 0) for that block. Resume compression after.

## Relationship to Output Token Budget

The existing 2,000-token output cap per agent (from `agent-defaults.md`) remains the **absolute ceiling** at all verbosity levels. Compression levels do NOT change the budget — they change how efficiently agents use it:

- Level 0 (verbose): 2,000 tokens, normal usage
- Level 1 (standard): 2,000 tokens, ~20% more content fits
- Level 2 (terse): 2,000 tokens, ~45% more content fits
- Level 3 (minimal): 2,000 tokens, ~65% more content fits (structured data is inherently compact)

Agents that produce less output finish under budget, saving tokens. The budget is not reduced at higher compression levels.

## Enforcement via Retrospective Detection

Compression is advisory (system prompt injection), not mechanically enforced. The retrospective (fg-700) detects non-compliance:

1. **Detection**: Compare each agent's output token count against the stage's expected range:
   - `standard` stage: expect 800-2000 tokens
   - `terse` stage: expect 400-1200 tokens
   - `minimal` stage: expect 100-600 tokens
   - Agent exceeding the range by >50%: flagged as `COMPRESSION_DRIFT`
2. **Action**: Log as INFO in retrospective report. If the same agent drifts in 3+ consecutive runs, suggest upgrading its tier (more capable model follows instructions better) or adjusting the stage level.
3. **Metric**: Track `output_tokens_per_agent` (raw, factual) in `state.json.tokens`.

## Mode Overlay Interaction

Pipeline modes (bugfix, migration, bootstrap, etc.) inherit the default per-stage compression levels. Modes MAY override specific stages in their `shared/modes/*.md` overlay:

```yaml
output_compression:
  verifying: terse    # Override minimal→terse for bugfix (need more context)
```

Resolution order: mode overlay > per-stage config > default_level.

If a mode overlay does not specify compression overrides, the defaults from `output_compression.per_stage` apply.

## PREFLIGHT Validation

| Parameter | Valid Values | Default |
|-----------|-------------|---------|
| `output_compression.enabled` | `true`, `false` | `true` |
| `output_compression.default_level` | `verbose`, `standard`, `terse`, `minimal` | `terse` |
| `output_compression.per_stage.*` | `verbose`, `standard`, `terse`, `minimal` | (see per-stage table) |
| `output_compression.per_stage` keys | must match the 10 stage names | — |
| `output_compression.auto_clarity` | `true`, `false` | `true` |

## Configuration

```yaml
# Output Compression (v2.0+)
output_compression:
  enabled: true
  default_level: terse                # verbose | standard | terse | minimal
  per_stage:
    preflight: standard
    exploring: standard
    planning: standard
    validating: terse
    implementing: terse
    verifying: minimal
    reviewing: terse
    documenting: standard
    shipping: standard
    learning: standard
  auto_clarity: true                  # Revert to verbose for safety-critical content
```

## Orchestrator Dispatch

The orchestrator includes `output_verbosity` in every agent dispatch:

```
Agent(
  subagent_type: "forge:fg-410-code-reviewer",
  model: "sonnet",
  prompt: "... [output_verbosity: terse] ..."
)
```

When `output_compression.enabled: false`, all agents use verbose (level 0). Zero behavioral change.

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Agent ignores compression level | No enforcement (advisory). Retrospective can flag verbose agents. |
| Auto-clarity triggers excessively | Log frequency. If >50% of output is auto-clarity, suggest lowering stage verbosity. |
| Compression causes ambiguity | User reports confusion → feedback-capture tags as `style-preference` → retrospective adjusts level. |
| `output_compression.enabled: false` | All agents use verbose (level 0). Zero behavioral change. |

## Research Backing

arXiv:2604.00025 (March 2026) "Brevity Constraints Reverse Performance Hierarchies in Language Models" validates this system's design:

1. **Brevity improves accuracy:** Brevity constraints improve LLM accuracy by up to 26 percentage points. Terse and minimal levels are not just token-efficient -- they produce more accurate technical output.

2. **Minimal prompt sufficiency:** A 6-line compression prompt matches the effectiveness of elaborate multi-page instruction sets. Forge's per-level rule blocks (5-10 lines each) are in the effective range.

3. **Realistic savings expectations:** Real-world total session savings are 4-10%, not the 45-65% figures cited for prose-only compression. The per-stage savings estimates in the Verbosity Levels table represent prose-only reduction. Actual session savings depend on the ratio of prose to code/structured output.

4. **Safety exceptions are critical:** The paper confirms that compressing security warnings, irreversible action confirmations, and user-facing content degrades decision quality. Forge's auto-clarity safety valve (see above) is aligned with this finding.

## Token Tracking (state.json)

Two fields added to `state.json.tokens`:

- `compression_level_distribution`: `{ "verbose": N, "standard": N, "terse": N, "minimal": N }` — count of agent dispatches per level
- `output_tokens_per_agent`: `{ "fg-410": N, "fg-411": N, ... }` — raw output token count per agent

## Related

- **Input compression** (`input-compression.md`): Compresses files loaded as system prompt context (agent `.md`, convention stacks). Independent from output compression. Applied offline via `/forge-compress`.
- **Caveman mode** (`skills/forge-compress output/SKILL.md`): User-configurable terseness for Forge's own user-facing messages.
