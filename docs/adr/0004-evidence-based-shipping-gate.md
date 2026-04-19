# ADR-0004: Evidence-based shipping gate

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

Without a hard gate, PRs occasionally shipped while a flaky test "probably passed"
or a reviewer was "mostly happy." Run logs were not enough evidence because they
could be outdated by subsequent edits. We needed a gate that refuses to open a
PR unless a fresh verification pass just succeeded.

## Decision

The `fg-590-pre-ship-verifier` agent runs a fresh build + test + lint + review
pass immediately before SHIP, writes the result to `.forge/evidence.json` with a
verdict (`SHIP` | `BLOCK`), and the PR builder (`fg-600-pr-builder`) refuses to
proceed unless `verdict: SHIP`. There is no "continue anyway" — fix, retry, or abort.

## Consequences

- **Positive:** No stale-evidence PRs; verdict is machine-checkable; retrospective can correlate PR outcomes to evidence hashes.
- **Negative:** One extra full verification pass per ship — the cost is real but small relative to the pipeline as a whole.
- **Neutral:** Recovery interacts with the gate — if pre-ship fails, the orchestrator returns to earlier stages.

## Alternatives Considered

- **Option A — Reuse last verification run's artifacts:** Rejected because edits between VERIFY and SHIP invalidate them.
- **Option B — Block on reviewer verdict alone:** Rejected because reviewers can approve and then subsequent stages introduce new failures.

## References

- `agents/fg-590-pre-ship-verifier.md`
- `shared/verification-evidence.md`
- `shared/stage-contract.md`
