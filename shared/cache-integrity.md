# Cache Integrity Verification

Integrity verification for cached pipeline artifacts using SHA256 checksums. Implements OWASP ASI06 (Memory Poisoning / Data Leakage) mitigation by detecting tampered or corrupted cache entries before the pipeline consumes them.

## Overview

Cached artifacts (explore cache, plan cache, knowledge base, code graph) are written during pipeline execution and read in subsequent runs. Without integrity verification, a malicious or corrupted cache entry could poison the pipeline's understanding of the codebase, leading to incorrect plans and implementations.

Cache integrity verification computes SHA256 checksums at write time and verifies them at read time. Tampered entries are rejected and the corresponding cache is invalidated, triggering re-exploration or re-planning.

## Integrity Store

All checksums are stored in `.forge/integrity.json`:

```json
{
  "schema_version": "1.0.0",
  "checksums": {
    "explore-cache.json": {
      "sha256": "a1b2c3d4e5f6...",
      "computed_at": "2026-04-13T09:00:00Z",
      "file_size_bytes": 45678
    },
    "plan-cache/index.json": {
      "sha256": "f6e5d4c3b2a1...",
      "computed_at": "2026-04-13T09:30:00Z",
      "file_size_bytes": 1234
    },
    "knowledge/rules.json": {
      "sha256": "6f5e4d3c2b1a...",
      "computed_at": "2026-04-13T10:30:00Z",
      "file_size_bytes": 5678
    },
    "code-graph.db": {
      "sha256": "b1c2d3e4f5a6...",
      "computed_at": "2026-04-13T08:00:00Z",
      "file_size_bytes": 5242880
    }
  },
  "last_verified": "2026-04-13T10:00:00Z",
  "verification_count": 15,
  "tamper_detections": 0
}
```

File paths in `checksums` are relative to `.forge/`.

## Protected Files

| File | Write Point | Read Point | On Tamper |
|---|---|---|---|
| `.forge/explore-cache.json` | EXPLORE stage completion | PREFLIGHT | Full re-explore (invalidate cache) |
| `.forge/plan-cache/index.json` | SHIP stage (plan caching) | PLAN stage | Rebuild index from plan files |
| `.forge/plan-cache/plan-*.json` | SHIP stage | PLAN stage | Delete tampered plan entry |
| `.forge/knowledge/rules.json` | LEARN stage | PREFLIGHT | Rebuild from inbox history |
| `.forge/knowledge/patterns.json` | LEARN stage | PREFLIGHT | Rebuild from inbox history |
| `.forge/knowledge/root-causes.json` | LEARN stage | PREFLIGHT | Rebuild from inbox history |
| `.forge/code-graph.db` | PREFLIGHT | PLAN, IMPLEMENT, REVIEW | Full graph rebuild |

## Verification Algorithm

### At Write Time

1. Compute SHA256 of the written file: `sha256sum "$file" | cut -d' ' -f1`
2. Record file size: `stat -f%z "$file"` (macOS) or `stat -c%s "$file"` (Linux)
3. Store checksum, timestamp, and file size in `.forge/integrity.json` via atomic JSON update (same pattern as `forge-state-write.sh`)

### At Read Time

1. Read stored checksum from `.forge/integrity.json` for the requested file
2. Compute current SHA256 of the file on disk
3. Compare:
   - **Match:** proceed with cached data
   - **Mismatch:** TAMPER DETECTED -- reject cache, log WARNING, execute tamper response per file type (see Protected Files table)
4. Log verification event to `.forge/security-audit.jsonl`

### Size Verification

In addition to SHA256, file size is tracked. If file size changes by more than 50% without a corresponding pipeline write (no `integrity.json` update), this is flagged as suspicious even before hash comparison. This provides faster detection for large files like `code-graph.db`.

## Finding Format

Tamper detection emits a WARNING finding:

```
SEC-CACHE-TAMPER | WARNING | Cache integrity check failed for {file} (expected SHA256: {expected}, actual: {actual}) | Cache invalidated; {tamper_response}
```

The finding is logged to `.forge/security-audit.jsonl` as a `CACHE_INTEGRITY_FAIL` event.

## Configuration

```yaml
security:
  cache_integrity:
    enabled: true
    verify_on_read: true
    protected_files:
      - "explore-cache.json"
      - "plan-cache/**"
      - "knowledge/**"
      - "code-graph.db"
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `true` | Master toggle for cache integrity verification |
| `verify_on_read` | boolean | `true` | Verify checksums every time a protected file is read |
| `protected_files` | array | (see above) | Glob patterns for files under `.forge/` to protect |

## Error Handling

| Failure Mode | Behavior |
|---|---|
| `integrity.json` missing | First run -- compute and store baseline checksums for all protected files. Log INFO: "Integrity baseline computed." |
| `integrity.json` corrupted (invalid JSON) | Recompute all checksums from current files. Log WARNING: "Integrity store corrupted -- recomputed baseline." |
| Protected file missing on disk | Remove entry from `integrity.json`. Log INFO: "Protected file {path} not found -- entry removed." |
| SHA256 computation fails (file locked) | Retry once after 100ms. If still fails, skip integrity check for that file with WARNING. |
| `integrity.json` has entry for unknown file | Ignore stale entries. They are cleaned up on next write cycle. |
