---
name: transient-retry
description: Exponential backoff retry strategy for transient failures (network timeouts, rate limits, temporary server errors).
---

# Transient Retry Strategy

Handles temporary failures that are likely to succeed on retry: network timeouts, rate limits (429), server errors (502/503/504), connection resets, and MCP timeouts.

---

## 1. Backoff Configuration

Use exponential backoff with jitter:

```
delay = min(base_delay * 2^retry_count + random(0, 1.0), max_delay)
```

### Base Delays by Error Type

| Error Type | Base Delay | Rationale |
|------------|------------|-----------|
| API rate limit (429) | 2s | APIs typically reset quickly |
| Network timeout / connection reset | 5s | Network issues need slightly longer |
| MCP tool timeout | 10s | MCP servers may need time to recover |
| Server error (502/503/504) | 5s | Server may be restarting |

### Limits

- **Max delay cap:** 60 seconds (never wait longer than this per retry)
- **Max retries:** 3
- **Jitter range:** 0 to 1.0 seconds (uniform random)

---

## 2. Retry Sequence

For each retry attempt (1 through max_retries):

1. Calculate delay using the formula above.
2. Log: `"Transient failure retry {attempt}/{max_retries} — waiting {delay}s before retry. Error: {stderr_tail_summary}"`
3. Wait for the calculated delay.
4. Re-execute the exact same action that failed.
5. If success: return `RECOVERED`.
6. If same transient error: continue to next attempt.
7. If different error type: re-classify through the recovery engine (it may now be a different category).

---

## 3. Escalation After Max Retries

If all 3 retries are exhausted:

### 3.1 Try Alternative Tool

If the failed action has a known alternative:
- `curl` failed → try `wget`
- `gh api` failed → try `curl` with GitHub API directly
- MCP tool failed → try equivalent Bash command

If an alternative exists, attempt it once. If it succeeds: return `RECOVERED`.

### 3.2 Determine Degraded Mode

If no alternative or alternative also fails, assess whether the failure blocks the pipeline:

| Failed Action | Degraded Mode | Blocks Pipeline? |
|---------------|---------------|------------------|
| context7 docs fetch | Skip docs prefetch, use conventions file | No |
| GitHub API (non-ship stage) | Skip GitHub-dependent checks | No |
| npm/gradle registry | Cannot install deps | Yes |
| MCP tool (optional check) | Skip that check, note in findings | No |
| MCP tool (required action) | Cannot proceed | Yes |

- If non-blocking: return `DEGRADED` with capability note.
- If blocking: return `ESCALATE` with diagnosis.

---

## 4. Rate Limit Specific Handling

When the error is a 429 rate limit:

1. Check for `Retry-After` header value in stderr/stdout. If present, use that as the delay (capped at 60s).
2. If no `Retry-After`, use the standard exponential backoff.
3. After recovery, suggest to the orchestrator to serialize subsequent API calls (reduce parallelism) to avoid hitting the limit again.

---

## 5. Output

Return to recovery engine:

```json
{
  "result": "RECOVERED | DEGRADED | ESCALATE",
  "details": "Description of what happened and what was done",
  "retry_count": 2,
  "total_delay_seconds": 14.7,
  "alternative_used": null,
  "degraded_capability": null
}
```
