# Spec Review — Phase 02: Cross-Platform Python Hook Migration

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-02-cross-platform-python-hooks-design.md`
**Reviewer:** Senior Code Reviewer (forge review agent)
**Date:** 2026-04-19

---

## Verdict

**REVISE.** The spec is well-structured and substantive — all 12 sections present, no placeholders, alternatives compared, OSTYPE skip addressed, CI matrix concrete. However it has **two Critical inconsistencies** that would cause real churn in implementation and one **Important** coverage gap. Fix the file-inventory contradictions and the spec is ready to execute.

---

## Strengths

1. **Complete section coverage.** All 12 sections (Goal, Motivation, Scope, Architecture, Components, Data/State/Config, Compatibility, Testing, Rollout, Risks, Success Criteria, References) are present and each carries genuine content rather than filler.
2. **Architecture comparison is genuinely comparative.** TypeScript and Go alternatives are rejected with specific numeric rationale (45 MB footprint, 10-15 MB binary, ~200ms `go run` overhead) rather than hand-waving. Selection of Python is justified on the existing-dependency basis (`engine.py`, MCP server).
3. **OSTYPE skip removal is explicitly and correctly addressed.** Section 8 ("Removed OSTYPE skip") and Success Criterion 4 both call out the deletion. The replacement mechanism (`pathlib.Path(...).resolve()` in `tests/validate_plugin.py`) is named concretely.
4. **Python version enforcement has multiple layers.** `check_prerequisites.py` at `/forge-init` (§7) + `from __future__ import annotations` forcing a clear `SyntaxError` on 3.9 (§10 R1) + `python.version_min` config key for discoverability. Defense in depth, not just one gate.
5. **CI matrix is fully concrete.** `actions/setup-python@v6` + `python-version: '3.11'` + `{ubuntu-latest, macos-latest, windows-latest} × {unit, contract, scenario}` = 9 jobs, with a YAML excerpt. No ambiguity about runner names or tier coverage.
6. **Hard-break rollout is unambiguous.** §7 explicitly says "HARD break. No deprecation window. No dual paths." §5 reinforces "All deletions land in the same commit." Matches the phase directive.
7. **Entry-script contract is testable.** §4 specifies a ~10-line shim pattern, importable `_py/` package, and stdin-JSON → exit-code protocol consistent with Claude Code's existing hook contract.
8. **Risks are technical, not platitudes.** R1 (Python version drift) and R2 (Windows path semantics) are grounded in specific failure modes (Debian 11 = 3.9, `PureWindowsPath` vs `PurePosixPath` in state files) with named mitigations including a test (`test_windows_path_roundtrip`).

---

## Critical

### C1 — Shell-script inventory is internally contradictory

The spec lists **7 hooks** in §3.1, but `/Users/denissajnar/IdeaProjects/forge/hooks/` contains only **5** `.sh` files (`automation-trigger-hook.sh`, `automation-trigger.sh`, `feedback-capture.sh`, `forge-checkpoint.sh`, `session-start.sh`). The spec conflates hooks and checks:

- Item 5 (`validate-syntax.sh`) and item 6 (`engine.sh --hook`) live under `shared/checks/`, not `hooks/`.
- Item 7 (`forge-compact-check.sh`) lives under `shared/`, not `hooks/`.
- `hooks/automation-trigger.sh` (21 lines, distinct from `automation-trigger-hook.sh`) **is not mentioned anywhere** in §3 scope, §5 file tables, or §10 risks. A quick `git grep` confirms both files exist and are referenced separately.

**Required revision:** (a) Rephrase §3 as "7 hook entry points across `hooks/` and `shared/checks/`" or split the count into "4 in `hooks/`, 3 in `shared/checks|/`." (b) Add `hooks/automation-trigger.sh` to the Files deleted table in §5 or explain why it's excluded. If it's a duplicate of `automation-trigger-hook.sh`, say so and delete it; if it's a different invocation path, port it.

### C2 — Bash-ism audit names files the port plan then skips

§2 lists six files with bash-4+ incompatibilities: `config-validator.sh`, `context-guard.sh`, `convergence-engine-sim.sh`, `cost-alerting.sh`, `validate-finding.sh`, `generate-conventions-index.sh`. Of these, only **`config-validator.sh`** appears in the §5 "Files created / deleted" tables. The other five are silently relegated to §3 "Out of scope" under "Internal orchestrator shell scripts never invoked by users" — but that categorization is wrong:

- `context-guard.sh` is called by `fg-100-orchestrator` context rails and runs on user machines.
- `cost-alerting.sh` is invoked by retrospective and monitoring paths.
- `validate-finding.sh` runs in the finding schema validation path invoked by reviewers.
- `generate-conventions-index.sh` runs at `/forge-init` (user-facing).

**Required revision:** either port these (expanding §5 Files created / deleted tables) or add an explicit §3 sub-bullet justifying — per file — why each is developer-only and will continue to require bash 4+. As written, Success Criterion 6 (`git grep -l '^#!/.*bash'` returns only "out-of-scope legacy scripts") is unverifiable because the out-of-scope list isn't enumerated.

### C3 — `tests/validate-plugin.sh:298` reference is off-by-two

The spec cites `tests/validate-plugin.sh:298` three times (§2 "Explicit Windows skip", §12 References, Success Criterion 4). Reading the file, **line 298 is the `else` branch**, not the skip condition; the MSYS/Cygwin/MinGW test is on line 296 and the skip `echo … NOTE …` is on line 297. This is a minor fidelity issue for a spec, but it becomes a Critical blocker because the phase directive and the review brief both pin the line number literally. An implementer grepping for `:298` will be off.

**Required revision:** reference the range `tests/validate-plugin.sh:290-298` (check 18b block) or correct to `:296` (the `if [[ "${OSTYPE:-}" == msys* …`). Better yet, quote the 3-line skip block verbatim in §2 so the target is unambiguous.

---

## Important

### I1 — Coverage of `hooks/*.sh` vs the "7 hooks" count

Related to C1 but distinct: the spec should either update the CLAUDE.md "Hooks (7):" enumeration so the count aligns with the new Python entry scripts (which is **6**: `pre_tool_use`, `post_tool_use`, `post_tool_use_skill`, `post_tool_use_agent`, `stop`, `session_start`), or keep 7 by adding a seventh hook event. Section 5 `hooks.json update` shows 6 entry scripts, but §3 says "all 7 hooks." One of the two must move.

### I2 — `pip install pyyaml` contradicts "stdlib-only"

§1 Goal says "Python 3.10+ **stdlib-only**." §4 rejects TypeScript partly because stdlib is already the dependency ("Zero additional dependencies; no install step."). §7 compatibility says "No bash requirement." Yet §8's CI YAML has:

```yaml
- run: pip install pyyaml
```

Either (a) drop `pyyaml` — use `tomllib` (stdlib in 3.11) or hand-parse the YAML frontmatter the plugin already reads, (b) justify the deviation explicitly in §4 Alternatives, or (c) bundle `pyyaml` as a vendored wheel so end users don't need it. The contradiction undermines the "zero dependencies" pitch.

### I3 — Entry-script count mismatch between §4 and `hooks.json` excerpt

§4 Package layout shows **6 entry files** (`pre_tool_use.py`, `post_tool_use.py`, `post_tool_use_skill.py`, `post_tool_use_agent.py`, `stop.py`, `session_start.py`). The `hooks.json` JSON in §4 has **6 hook entries**. §3 claims **7 hooks**. §5 "Files created" lists **6 entry scripts**. The "7" in §3 appears to incorrectly count `validate-syntax.sh`, `engine.sh`, and `forge-compact-check.sh` as hooks when they're actually dispatched from `hooks/post_tool_use*.py`. Merge the counting system: call them "3 hook entry scripts in `hooks/`" or "6 hook events" and pick one frame.

### I4 — Success Criterion 7 (latency) lacks Windows baseline

"Hook invocation latency p50 ≤ 150ms on Linux." The whole motivation of the phase is Windows parity. Windows-Python startup is closer to 80–100ms cold, and the L0 AST parse on Windows has been measured ~1.4× slower than Linux in comparable plugins. Either provide a Windows-specific target (e.g., p50 ≤ 220ms) or drop "on Linux" and reason about the slowest target platform.

### I5 — `bats` retention is underspecified

§8 "Bats tests retained" says "A few bats tests that reference `.sh` hook paths are updated in the same PR." Which tests? Where? Without enumeration, reviewers cannot verify the PR covers them. Add a sub-bullet: "Files touched: `tests/unit/hook-paths.bats`, `tests/structural/shebang.bats`, …" (or note "to be enumerated during implementation; validator will fail if any `*.sh` hook path remains referenced").

---

## Minor

### M1 — Version-bump rationale inverted

§9 says "Cut `v3.1.0` tag (major-feature minor bump; pipeline semantics unchanged)." A hard break that drops a runtime dependency (bash) and forces users to install Python 3.10+ is a **SemVer major** (v4.0.0), not minor. Even though pipeline *semantics* are unchanged, the installation/runtime contract changes breaking-ly — that's the axis SemVer tracks. Reconcile with the SEMVER doctrine or justify deviation.

### M2 — `FORGE_OS`/`FORGE_PYTHON` retirement claim needs audit

§6 says the env exports "were the only readers" of `platform.sh`'s `FORGE_*` exports. Verify with `grep -r 'FORGE_OS\|FORGE_PYTHON' .` before merging; if any agent `.md` or other `.sh` reads them, the retirement breaks silently.

### M3 — `pyproject.toml` mentions `ruff` without rollout step

§5 lists `pyproject.toml` with "ruff config" but §9 Rollout doesn't mention adding a ruff CI step. Either add a lint job or remove the ruff config from the scope.

### M4 — Reference §12 URL for Azure azd is a blog post

§2 and §12 cite `blog.jongallant.com/2026/04/azd-hooks-languages` as evidence of an "industry pivot." A single blog post is thin evidence. Either cite the azd release notes directly (GitHub `Azure/azure-dev`) or downgrade the claim to "example precedent" rather than "industry pivot."

### M5 — Risk coverage missing: bats requires bash on Windows runner

§8 keeps bats. `windows-latest` GitHub runners use Git Bash by default for `shell: bash`. If any kept `*.sh` test script hits the bash-isms §2 enumerates, it will fail on Windows. Either (a) acknowledge the residual bash-3.2-compat constraint on out-of-scope shell scripts, or (b) add a risk item "R3 — bats on Windows" with mitigation.

### M6 — Missing test for `check_prerequisites.py`

The new enforcement gate has no dedicated test in §8. Add a unit test asserting it exits 1 on Python 3.9 (simulated) and 0 on 3.10+.

### M7 — `io_utils.atomic_json_update` — Windows `msvcrt.locking` semantics

§8 mentions `msvcrt.locking` for Windows file locks. That API locks byte ranges (not whole files) and raises `OSError` rather than returning a lock handle. Worth a one-liner in §4 or §10 acknowledging the POSIX/Windows semantic divergence and how the code wraps both.

---

## Overall

Strong spec that achieves substance in every one of the 12 sections and correctly identifies the actual Windows friction points. The architecture section genuinely compares alternatives with numeric rationale, CI is concrete, and the hard-break rollout aligns with the phase directive. The blockers are **inventory precision**, not architectural flaws — (C1) the 7-hook count is wrong once you reconcile `hooks/` vs `shared/checks/` vs `shared/*.sh`; (C2) the motivation cites files it then leaves out of scope; (C3) the `:298` line pointer is off by two. Fix those three and address the stdlib-only contradiction (I2), and this is ready to execute.

**Score (informal):** 88/100 — would be 95+ after the three C-level revisions.

**Recommended next step:** spec author amends §3, §5, and §8; reviewer re-reads the three changed sections only; merge the amended spec. No need to re-review Sections 1, 4, 6, 7, 9, 10, 11, 12 — they are solid.
