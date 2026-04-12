# Forge Quality Improvement — Umbrella Spec

**Date:** 2026-04-12
**Goal:** Lift overall system grade from B+ (85/100) to A across all areas.
**Approach:** Test-gated fixes — write failing tests first, then fix to pass.
**Verification:** Self-review + agent review per spec; `/requesting-code-review` per phase.

## Scope

16 items across 4 phases, addressing findings from a comprehensive 6-agent audit of agents, skills, hooks, shared documentation, tests, and distribution.

### Corrections Applied During Design

Three findings from the initial audit were **disproven** during verification and removed from scope:

1. **"9 dispatch agents missing Agent tool"** — All 9 are leaf agents that do not dispatch sub-agents. Their tools lists are correct.
2. **"scoring.md dead reference to category-registry.json"** — The file `shared/checks/category-registry.json` exists with 22 category definitions.
3. **"PREEMPT marker format not formalized"** — Format exists at `agent-communication.md` lines 175-176 but could be more rigorous (retained as minor item).

## Phase Overview

| Phase | Focus | Files Modified | New Files | New Test Files | Est. Test Cases |
|---|---|---|---|---|---|
| 1 | Structural fixes | 15 | 0 | 3 | ~5 |
| 2 | Documentation tightening | 5 | 0 | 2 | ~9 |
| 3 | Test coverage | 0 | 0 | 4 | ~24 |
| 4 | Architecture refinements | 5 | 3 | 4 | ~15 |
| **Totals** | | **25** | **3** | **13** | **~53** |

## Execution Order

Phases execute sequentially: 1 → 2 → 3 → 4. Each phase completes with:
1. All new tests pass
2. All existing tests pass (`./tests/run-all.sh`)
3. `/requesting-code-review` verification

## Success Criteria

- All existing tests green (1,367+ cases)
- ~53 new test cases green
- No regressions in `validate-plugin.sh` (73 structural checks)
- Each phase independently reviewed

## Phase Specs

- [Phase 1: Structural Fixes](./2026-04-12-quality-improvement-phase1-structural.md)
- [Phase 2: Documentation Tightening](./2026-04-12-quality-improvement-phase2-docs.md)
- [Phase 3: Test Coverage](./2026-04-12-quality-improvement-phase3-tests.md)
- [Phase 4: Architecture Refinements](./2026-04-12-quality-improvement-phase4-architecture.md)
