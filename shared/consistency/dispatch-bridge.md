# Self-Consistency Dispatch Bridge — Minimum-Viable Contract

**Status:** Active stub (forge 3.1.0). Complements `shared/consistency/voting.md`.

**Problem addressed:** The helper `hooks/_py/consistency.py` exposes
`vote(..., sampler=<callable>)` but ships no default sampler. The three
callers (`agents/fg-010-shaper.md`, `agents/fg-210-validator.md`,
`agents/fg-710-post-run.md`) are subagents invoked by the Claude Code host —
not Python processes. This document defines how those Markdown-driven agents
reach the Python helper and how a fresh fast-tier subagent per sample is
produced.

The production sampler implementation (ADR-11-BRIDGE) lands in a follow-up
task; this document is the normative contract that implementation
must satisfy. Until the production sampler lands, agents follow the fallback
path in §4 ("Python unavailable") and voting silently degrades to
single-sample classification — no pipeline failure.

---

## 1. Invocation shape (agent → Python)

The calling agent shells out to a single CLI entry point:

```
hooks/_py/consistency_cli.py vote --input <path-to-stdin-json>
```

**Why a file path, not stdin heredoc:** prompts for `validator_verdict`
routinely exceed 100 KB (seven-perspective findings + plan text). Shell
heredoc limits and quoting hazards make `--input <file>` the only safe
contract. The agent writes the payload to `.forge/tmp/consistency-<uuid>.json`,
invokes the CLI, reads the single-line JSON result from stdout, then deletes
the tmp file.

### 1.1 Request payload (JSON, UTF-8)

```json
{
  "decision_point": "shaper_intent",
  "labels": ["bugfix", "migration", "bootstrap", "multi-feature",
             "vague", "testing", "documentation", "refactor",
             "performance", "single-feature"],
  "prompt": "<full prompt text>",
  "state_mode": "standard",
  "n": 3,
  "tier": "fast",
  "cache_enabled": true,
  "min_consensus_confidence": 0.5,
  "cache_path": ".forge/consistency-cache.jsonl"
}
```

All fields are required except `cache_path` (defaults to
`.forge/consistency-cache.jsonl`).

### 1.2 Response payload (JSON, UTF-8, single line to stdout)

Success:

```json
{"ok": true, "result": {"label": "bugfix", "confidence": 0.87,
  "samples": [["bugfix", 0.9], ["bugfix", 0.85], ["bugfix", 0.86]],
  "cache_hit": false, "low_consensus": false}}
```

Failure:

```json
{"ok": false, "error": "ConsistencyError",
 "message": "only 1/3 samples survived (need >= 2)"}
```

Exit codes:
- `0` — success, payload on stdout.
- `2` — `ConsistencyError` (too few samples, schema failures). Caller treats
  as `low_consensus: true` per `voting.md` §5.
- `3` — `ValueError` / schema violation in request. Bug in the agent prompt;
  caller logs INFO and falls through to legacy path.
- `1` — any other exception (Python crash, FS error, missing dependency).
  Caller treats as "Python unavailable" per §4.

stderr is reserved for diagnostics; agents MUST NOT parse it.

---

## 2. Sampler construction

`consistency_cli.py` constructs the sampler internally. Callers never
reference the sampler callable directly — they only see the CLI contract.

**Sampler contract** (Python-internal; matches the `Sampler` type in
`hooks/_py/consistency.py`):

```python
async def sampler(prompt: str, labels: list[str],
                  tier: str, seed: int) -> dict:
    # returns {"label": str, "confidence": float}
```

Each sample dispatches one **fresh** fast-tier subagent via the Claude Code
`Agent` tool (or equivalent host-side primitive). "Fresh" = no inherited
conversation context, no inherited `state.json`, no cross-sample
contamination. `seed` is the sample index (0..n-1); implementations may pass
it to the model as a nonce in a system-prompt comment to discourage
deterministic cache reuse on the model backend.

The per-sample subagent prompt MUST enforce the response schema:

```
Return ONLY a single JSON object: {"label": <one of the labels>,
"confidence": <float in [0.0, 1.0]>}. No prose. No markdown fences.
```

Schema validation lives in `_valid()` in `consistency.py` — the CLI does not
need to duplicate it.

---

## 3. Error handling matrix

| Error class | CLI exit | Agent behaviour |
|---|---|---|
| Sampler succeeds on >= ceil(N/2) samples with low mean confidence | 0, `low_consensus: true` in payload | Apply per-caller fallback in `voting.md` §5 |
| Sampler returns fewer than ceil(N/2) valid samples (`ConsistencyError`) | 2 | Same as `low_consensus: true` — apply §5 fallback |
| Single sampler call raises (network, timeout) | 0 with degraded sample count — only if >= ceil(N/2) survive; else exit 2 | Handled by CLI/helper, transparent to agent |
| Request payload invalid (missing field, wrong type) | 3 | Log INFO `CONSISTENCY-REQUEST-INVALID`, skip voting, use legacy path |
| CLI binary missing, Python import error, fatal crash | 1 (or shell exec failure) | See §4 — Python unavailable fallback |
| Tmp-file write fails | n/a (agent-side) | Log INFO, skip voting, use legacy path |

The agent MUST NOT retry on any of these. A retry would breach the
single-dispatch contract stated in `voting.md` §1 ("The caller does NOT
re-invoke dispatch").

---

## 4. Python-unavailable fallback

If the CLI cannot be executed at all (exit code != 0/2/3, missing binary,
`hooks/_py/` absent on the host), the agent:

1. Emits ONE stage-notes INFO line `CONSISTENCY-UNAVAILABLE: <reason>`.
2. Sets `state.consistency_votes.<decision_point>.low_consensus` += 1 to
   preserve the observability signal (treats unavailability as a
   low-consensus event for metric purposes).
3. Falls through to the legacy single-sample classification path described
   in each caller's §"fallback" block (`fg-010`: existing shaping dialogue;
   `fg-210`: legacy single-sample verdict; `fg-710`: ambiguous →
   `implementation`).
4. Does NOT escalate, does NOT fail PREFLIGHT, does NOT block the pipeline.

This matches the forge-wide principle: every optional integration
(MCP servers, Linear, Neo4j, SQLite graph) degrades to a legacy path and
logs a single INFO. Voting is the same.

The fallback is ALSO the current default until the production sampler in
`consistency_cli.py` lands — see `voting.md` §1.1. PREFLIGHT MUST NOT refuse
to start because the CLI is missing.

---

## 5. State accounting

The agent — NOT the CLI — is responsible for state increments. After each
call:

| CLI outcome | State increments (all on `consistency_votes.<decision_point>`) |
|---|---|
| `ok: true`, `cache_hit: false`, `low_consensus: false` | `invocations` += 1 |
| `ok: true`, `cache_hit: true` | `invocations` += 1, `cache_hits` += 1, plus run-level `consistency_cache_hits` += 1 |
| `ok: true`, `low_consensus: true` | `invocations` += 1, `low_consensus` += 1 |
| `ok: false` (exit 2) | `invocations` += 1, `low_consensus` += 1 |
| exit 3 | no increments (the dispatch never happened) |
| exit 1 / unavailable | `low_consensus` += 1 only (see §4.2); `invocations` NOT incremented |

Exception: `validator_verdict.invocations` is NOT incremented when the
deterministic rule pass in `fg-210-validator.md` §5.1 returns a hard verdict
(SKIP path). See `voting.md` §6.

---

## 6. Open items deferred to the production sampler

1. Exact `Agent` tool invocation shape for a "fresh fast-tier subagent". The
   current Claude Code SDK surface for spawning an isolated subagent from a
   Python process is under discussion (see plan-review I2).
2. Per-sample timeout (proposed: 10 s per sample, 30 s total for N=3).
3. Observability hook-up (OTel span per sample, see `shared/observability.md`).
4. Concurrency limit if a future N=9 config lands (cap parallelism at 5).

Until these land, the CLI presence is the only blocker between "voting
enabled in config" and "voting actually runs". Config toggles
(`consistency.enabled`, `consistency.decisions`) remain the user-facing
switch.
