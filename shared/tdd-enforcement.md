# TDD Enforcement Rules

Referenced by `fg-300-implementer`. These rules are non-negotiable during the IMPLEMENT stage.

---

## The TDD Cycle

1. **RED** — Write a test that describes the desired behavior. Run it. Watch it fail. The failure message must clearly indicate what is missing. If the test passes immediately, it is not testing new behavior.
2. **GREEN** — Write the minimum production code to make the failing test pass. No more. Resist the urge to generalize, optimize, or handle edge cases not yet covered by a test.
3. **REFACTOR** — Clean up both test and production code. Remove duplication, improve names, extract methods. All tests must still pass after refactoring. No new behavior in this step.

Then repeat. Each cycle should take minutes, not hours.

---

## Iron Law

**No production code without a failing test first.**

This means:
- Before writing any function, class, or method, a test must exist that calls it and fails.
- Before fixing a bug, a test must exist that reproduces the bug and fails.
- Before adding a feature, a test must exist that exercises the feature and fails.

---

## Verification Requirement

The implementer must observe the test fail before writing production code. "I know it would fail" is not sufficient. The failure output serves two purposes:
1. Confirms the test is actually running and exercising the right code path.
2. Establishes the baseline — the failure message becomes the definition of "not done."

If the test passes on first run, either the behavior already exists (no code needed) or the test is wrong.

---

## Red Flags: Rationalizations to Reject

| Rationalization | Why It's Wrong |
|----------------|----------------|
| "This is too simple to need a test" | Simple code has a way of becoming complex. The test costs 30 seconds now and catches regressions forever. |
| "I'll write the test after" | Test-after verifies what was built, not what should be built. It misses edge cases the implementation accidentally handles. The test becomes a mirror of the code, not a specification of behavior. |
| "The test would just test the framework" | Then the code is probably pure configuration. If it contains any conditional logic, branching, or data transformation, it needs a test. |
| "It's just a config change" | Config changes that affect runtime behavior (feature flags, security settings, connection parameters) need tests. Config changes that don't affect behavior (comments, formatting) don't. |
| "I need to see the shape of the code first" | Spike in a throwaway branch. Delete it. Then TDD the real implementation. |
| "The tests are slowing me down" | Tests that slow you down are usually too large. Write smaller tests. Test one behavior per test. |

---

## When TDD Does Not Apply

- **Generated code** — Code produced by generators, scaffolders, or code-gen tools. Test the generator's output, not the generator's internals (unless you own the generator).
- **Build configuration** — Gradle/Maven/package.json changes that don't contain logic. Validated by the build itself.
- **Documentation** — Markdown, comments, READMEs.
- **Static assets** — Images, fonts, icons.
- **One-off scripts** — Migration scripts, data fixes. These are tested by running them, not by unit tests.

If in doubt, write the test. The cost of an unnecessary test is low. The cost of a missing test is a production bug.

---

## Quick Reference Checklist

Before writing production code, verify:

- [ ] A test exists for the behavior I am about to implement
- [ ] I have run the test and watched it fail
- [ ] The failure message clearly describes what is missing
- [ ] I am writing the minimum code to pass this one test
- [ ] After the test passes, I will refactor before adding the next test
- [ ] I have not written production code "just to set things up" without a corresponding test
