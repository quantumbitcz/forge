# Systematic Debugging Techniques

Referenced by `fg-020-bug-investigator`. These techniques apply in order of priority during the INVESTIGATE stage.

---

## 1. Root-Cause Tracing

**Principle:** Start from the observable error and trace backward. Never fix symptoms.

**Process:**
1. Reproduce the error with a minimal, deterministic trigger.
2. Read the full error output — stack trace, log context, HTTP status, exit code.
3. Identify the immediate failure point (the line that throws/panics/returns error).
4. Trace backward: what called this line? What data did it receive? Where did that data originate?
5. Continue tracing until you find the first point where reality diverges from expectation. That is the root cause.

**Verification:** After identifying the root cause, confirm it by predicting: "If I change X at this point, the error disappears." Then test that prediction. If the error persists, you found a symptom, not the cause — keep tracing.

**Common traps:**
- Fixing the line that throws instead of the line that produces the bad input.
- Assuming the root cause is in the same file as the error.
- Stopping at the first plausible explanation without verifying it.

---

## 2. Defense-in-Depth

**Principle:** After fixing the root cause, add validation at multiple layers to prevent the same class of bug.

**Process:**
1. Fix the root cause.
2. Add input validation at the entry point (API controller, CLI parser, event handler) — reject bad data early.
3. Add a precondition check at the processing layer (service, use case) — fail fast with a clear message.
4. Add an assertion or invariant at the persistence layer — prevent corrupt data from being stored.

**Scope control:** Add validation for the specific class of input that caused the bug, not speculative validation for hypothetical inputs. Each validation layer should produce a distinct, actionable error message that identifies which layer caught the problem.

---

## 3. Condition-Based Waiting

**Principle:** Never use fixed-duration sleeps to wait for asynchronous operations. Poll for the expected condition with a timeout.

**Pattern:**
```
maxWait = 30 seconds
pollInterval = 500 ms
deadline = now() + maxWait

while (now() < deadline) {
    if (condition_is_met()) {
        return success
    }
    wait(pollInterval)
}
return timeout_error("Condition not met within {maxWait}")
```

**Rules:**
- The condition must be a concrete, observable state (HTTP 200, file exists, row count > 0) — not "enough time has probably passed."
- The timeout must produce a clear error explaining what was expected and what was found.
- The poll interval should be proportional to the expected wait time (100ms for sub-second operations, 1-5s for multi-second operations).
- If the system provides a notification mechanism (webhook, event, callback), prefer it over polling.

---

## 4. Architectural Escalation

**Principle:** If three or more fix attempts fail for the same issue, the problem is likely architectural, not a localized bug. Stop fixing and escalate.

**Trigger conditions:**
- Three distinct fix attempts that each resolve part of the problem but introduce a new failure.
- A fix that works in isolation but breaks when integrated with the rest of the system.
- A fix that requires modifying 5+ files across 3+ packages/modules.

**Escalation process:**
1. Document what was tried, what each attempt fixed, and what each attempt broke.
2. Identify the architectural assumption being violated (wrong abstraction boundary, missing indirection, circular dependency, shared mutable state).
3. Escalate to replanning (Stage 2) with a clear statement: "The current architecture does not support X because of Y. Proposed structural change: Z."

**Do not:** Continue applying patches in hope that the next one works. Each failed attempt increases code complexity and makes the eventual architectural fix harder.

---

## 5. Binary Search Debugging

**Principle:** For bugs introduced by a large changeset, bisect to isolate the breaking change.

**For commits:**
```
git bisect start
git bisect bad HEAD          # current state is broken
git bisect good <known-good> # last known working commit
# git runs binary search — test each proposed commit
git bisect run ./test-script.sh
```

**For code changes within a single commit:**
1. Comment out half the changes, test.
2. If the bug disappears, it's in the commented-out half. Restore and comment the other half of that section.
3. Repeat until the minimal breaking change is isolated.

**For configuration:**
1. Start with the known-good configuration.
2. Apply half the config changes, test.
3. Narrow by halves until the breaking config key is found.

**Key rule:** The test used for bisection must be deterministic and automated. Manual "it looks right" checks defeat the purpose.

---

## Quick Reference

| Technique | When to Use | Stop Condition |
|-----------|-------------|----------------|
| Root-cause tracing | Every bug — start here | Root cause verified by prediction |
| Defense-in-depth | After root cause is fixed | Validation at entry, processing, and storage |
| Condition-based waiting | Flaky tests, timing bugs | Fixed sleeps replaced with polled conditions |
| Architectural escalation | 3+ failed fix attempts | Escalated to replanning with evidence |
| Binary search | Large changeset introduced bug | Minimal breaking change isolated |
