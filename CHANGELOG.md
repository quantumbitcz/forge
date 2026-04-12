# Changelog

All notable changes to the Forge plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.15.0] - 2026-04-12

### Added
- Skill selection guide in CLAUDE.md for intent→skill routing
- Architecture diagram in README.md (pipeline flow + module resolution)
- Troubleshooting section in README.md (10 common issues with fixes)
- Checkpoint schema reference in CLAUDE.md key entry points (`shared/state-schema.md` §checkpoint)
- Autonomous mode decision documentation in convergence-engine.md
- Cross-references: stage-contract→agent-communication (2K budget), agent-registry tier legend
- Learnings/ and checkpoint-schema references in CLAUDE.md key entry points
- 9 missing skills added to README.md skill table (29 total)
- `portable_timeout` wrapper in run-linter.sh for adapter timeout enforcement
- State validation guard in forge-checkpoint.sh hook
- New test files: hook-failure-scenarios.bats, recovery-burndown.bats, concurrent-state-access.bats
- PREEMPT items populated across 19 framework learnings files

### Fixed
- README.md skill count updated from 25 to 29
- Test framework binding mismatches resolved (angular, express, nestjs)
- 8 skill descriptions improved with "when to use" triggering context

### Changed
- CLAUDE.md updated from 25 to 29 skills with selection guide
- forge-checkpoint.sh validates state.json structure before atomic update

## [1.13.0] - 2026-04-12

### Added
- Skill routing guide (`shared/skill-routing-guide.md`) for canonical intent→skill mapping
- 3 new skills: `/forge-abort`, `/forge-resume`, `/forge-profile`
- Prerequisite checks for 7 skills (forge-run, forge-fix, forge-review, codebase-health, deep-health, graph-status, graph-query)
- `autonomous` field in state schema for fully autonomous pipeline runs
- Transition lock (`FD 201`) in `forge-state.sh` for concurrent transition safety
- Token tracker retry on stale `_seq` with up to 3 re-read/recompute attempts
- `phase_iterations >= 2` guard on convergence rows C8/C10 (first-cycle exemption)
- Row C10a: baseline-exempt plateau handling for first 2 convergence cycles
- Mode overlay → transition interaction documentation in `state-transitions.md`
- Recovery budget ↔ total retries independence documentation
- `smoothed_delta` scoping to current-phase scores after safety gate restart
- 80+ new BATS tests (state transitions per-row, convergence engine advanced)
- Hook failure visibility in session summary (`feedback-capture.sh`)
- Small file skip heuristic in engine.sh hook mode (files < 5 lines)

### Fixed
- Bash 3.2 compatibility: replaced `(( ))` arithmetic with `[ -lt ]` in engine.sh
- FD 200 leak in engine.sh: added cleanup in `handle_skip()` and EXIT trap
- `return 1` → `exit 1` in `platform.sh` `atomic_increment()` subshell
- `forge-checkpoint.sh` silent crash: removed blanket `{ } 2>/dev/null`, added type guard
- `forge-compact-check.sh` race condition: added flock-based fallback
- `feedback-capture.sh`: replaced bare `except:` with specific types, f-strings with `.format()`
- `scoring.md` effective_target formula aligned with `convergence-engine.md` (added `max(pass_threshold, ...)` floor)
- Error JSON output to stderr in `forge-state.sh` transition errors
- Signal trap for temp file cleanup in `forge-state.sh`
- Token tracker string interpolation: shell vars replaced with `sys.argv`
- fg-300 test file modification contradiction resolved with decision table
- fg-160 plan mode contradiction resolved with 3 clear contexts

### Changed
- 8 skill descriptions updated for routing clarity and disambiguation
- CLAUDE.md skill count updated from 25 to 28

## [1.12.0] - 2026-04-10

### Added
- Explicit `ui:` blocks on fg-410, fg-412, fg-420 for spec 1.7 completeness
- 3 new diagnostic skills

### Fixed
- Comprehensive code review findings (C1-C4, I1-I7, S1)
- Phase C code review findings (C1, I1-I7, S2-S5)
