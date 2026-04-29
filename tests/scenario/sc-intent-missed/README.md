# sc-intent-missed

Asserts that `fg-590-pre-ship-verifier` BLOCKs SHIP when an `INTENT-MISSED`
CRITICAL finding is open in the run state, even though the convergence score
(85) clears the minimum (80) and all other gates (build, tests, lint, review
counts) pass. Maps to AC-703 (open INTENT-MISSED CRITICAL blocks SHIP) and
AC-716 (verified-pct threshold gate). The fixture supplies a synthetic
`intent_verification_results`/`findings` pair; `test_run.py` re-implements the
fg-590 Step 6 verdict logic from the agent prompt and confirms the verdict is
`BLOCK` with an `intent-missed` block reason.
