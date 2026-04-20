# Scenario 10 — Disabled-config regression

**Hostile config:** project's `forge-config.md` sets `security.untrusted_envelope.enabled: false`.

**Expected:** PREFLIGHT halts with `SEC-INJECTION-DISABLED` (CRITICAL) before any stage transition. This scenario tests the PREFLIGHT constraint, not the filter itself.

**Status:** SKIPPED until Task 20 lands `shared/preflight-injection-check.sh`. Once that script exists, this test will fail-open by design (any project that disables the envelope cannot proceed).

**Source tier:** N/A (config-level, not data-level).
