# Scenario 07 — Size bomb

**Hostile input:** 10 MiB Figma payload (generated in-test, not checked in).

**Expected:** filter truncates at `MAX_ENVELOPE_BYTES` (64 KiB), appends `[truncated, N bytes elided]` marker, emits `SEC-INJECTION-TRUNCATED` (INFO). Subsequent stages see the truncated envelope; downstream context-window pressure is bounded.

**Pattern IDs touched:** none — truncation is a size-budget enforcement, not a regex match.

**Source tier:** `mcp:figma` → `logged`.
