# Changelog

All notable changes to the Forge plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [5.1.0] — Mega C: Brainstorming Behavior

### Added (Phase C1 — Shaper rewrite)

- **`agents/fg-010-shaper.md`** rewritten (377 lines) adopting the proven `superpowers:brainstorming` pattern in-tree (no runtime dependency). Seven canonical headings (substring-greppable, AC-S021): `## Explore project context`, `## Ask clarifying questions`, `## Propose 2-3 approaches`, `## Present design sections`, `## Write spec`, `## Self-review`, `## Handoff`.
- **Autonomous-mode degradation path** — when `state.brainstorm.autonomous == true`, the shaper does NOT call `AskUserQuestion`/`EnterPlanMode`. It invokes `python3 ${CLAUDE_PLUGIN_ROOT}/shared/ac-extractor.py --input -` (CLI added in this release), parses the JSON output, and writes the spec one-shot. AC-S022.
- **Transcript mining** (AC-BEYOND-001/002/003) — the new `## Historical context` H2 (between `Explore` and `Ask`) queries F29 run-history-store FTS5 (`run_search` virtual table, BM25-ranked against `requirement` column). `## Handoff` writes a JSONL transcript to `.forge/brainstorm-transcripts/<run_id>.jsonl`. Honors `brainstorm.transcript_mining.enabled: false` short-circuit.
- **Resume semantics** (AC-S023) — three resume cases enumerated: interactive-with-spec, interactive-without-spec, autonomous. `state.brainstorm.spec_path` is repo-relative (matches schema; absolute-path drift fixed during review).

### Added (Phase C2 — Orchestrator wiring)

- **`agents/fg-100-orchestrator.md`** updated (~180 lines added, 1 line removed; 1976 → 2120 lines total).
- **§1 stage banner** — now reads `PREFLIGHT -> [BRAINSTORMING (feature mode only)] -> EXPLORE -> ...`. Bracket notation makes BRAINSTORMING explicitly conditional.
- **§0.1 dispatch matrix** — replaces the legacy line `fg-010-shaper NOT dispatched by orchestrator — runs via /forge run.`. New matrix routes: standard mode → PREFLIGHT → BRAINSTORMING → EXPLORING; bug/migrate/bootstrap/--spec/--from past skip BRAINSTORMING; `brainstorm.enabled: false` short-circuits with log line `[AUTO] brainstorm disabled by config`.
- **§0.4d Platform Detection** — new PREFLIGHT phase between §0.4c Background Execution and §0.5. Invokes `python3 ${CLAUDE_PLUGIN_ROOT}/shared/platform-detect.py --repo-root <path> --config-platform-detection <auto|...> --config-remote-name <name>` (CLI added in this release), parses JSON `{platform, remote_url, api_base, auth_method}`, writes `state.platform = {name, remote_url, api_base, auth_method, detected_at}`. Skip on resume if `state.platform.detected_at` already set. Failure → `state.platform.name = "unknown"`, log WARNING, **do NOT abort**. AC-FEEDBACK-006.
- **`## Stage 0.5: BRAINSTORM`** — new stage block between Stage 0 PREFLIGHT and Stage 1 EXPLORE. SS0.5.1 (skip conditions), SS0.5.2 (dispatch via §4 standard 3-step wrapper), SS0.5.3 (post-dispatch validation: `state.brainstorm.spec_path` exists + matches the well-formedness regex from `tests/unit/skill-execution/spec-wellformed.bats`), SS0.5.4 (BRAINSTORMING → EXPLORING transition), SS0.5.5 (resume-routing note). On agent failure, logs `BRAINSTORM-NO-SPEC` finding (CRITICAL). AC-S019/S020/S023.
- **§0.14 Check for Interrupted Runs** — extended to recognize `state.story_state == "BRAINSTORMING"`. Pass-through to BRAINSTORMING stage; the shaper agent owns the resume sub-routing.
- **§5 --spec mode parser** updated to accept the canonical Goal/Scope/Acceptance criteria schema written by C1 (matches `spec-wellformed.bats` regex `## (Objective|Goal|Goals) | ## (Scope|Non-goals) | ## (Acceptance Criteria|ACs)`). The pre-existing Problem-Statement/Story schema is dropped per `feedback_no_backcompat`.
- **MAX_LINES bump** — `tests/contract/test_fg100_size_budget.py` 2000 → 2200 (per `feedback_orchestrator_size`). Orchestrator at 2120, ~80 lines headroom.

### Added (Phase A helper CLIs — backfilled this release)

- **`shared/ac-extractor.py` CLI** — `__main__` + `argparse` block (`--input <path|->`) reads stdin or file, calls `extract_acs()`, prints `json.dumps({"acs": [...], "objective": "...", "confidence": "low|medium|high"})` to stdout. Exit 0 on success, 2 on parse error. The library `extract_acs(raw_text)` function remains unchanged for in-process callers.
- **`shared/platform-detect.py` CLI** — `__main__` + `argparse` block (`--repo-root <path>`, `--config-platform-detection <auto|github|gitlab|bitbucket|gitea|none>`, `--config-remote-name <name>`). Prints `json.dumps(asdict(result))` to stdout including the optional `warning` field. Always exits 0 (non-detection is `"unknown"`, not error).
- These CLIs were specified by Mega A's helper modules but never wired up; the v5.1.0 review caught the gap. The shaper (C1) and orchestrator §0.4d (C2) invocations would have silently degraded without them.

### Changed (Cross-cutting)

- **`shared/state-transitions.md`** — Row 1 BRAINSTORMING entry-guard fixed: `mode == "feature"` → `mode == "standard"` (matches the canonical `state.mode` enum from `state-schema-fields.md`). Without this fix, BRAINSTORMING never fired for the default mode (silent AC-S019 failure).
- **`shared/state-schema.md`** — added `forge.brainstorm.section_approved` to the Stage 0.5 OTel event table (consumed by the shaper Telemetry section's emission rate analytics).
- **OTel event renames in shaper** — `forge.brainstorm.start` → `forge.brainstorm.started`, `forge.brainstorm.question` → `forge.brainstorm.question_asked` (past tense, matches schema § OTel Events table).
- **auth_method enum** harmonized between orchestrator §0.4d JSON example and `state-schema.md`: canonical set is `gh-cli | glab-cli | app-password | gitea-token | none`.
- Mode vocabulary harmonized: "feature mode" → "standard mode" everywhere (in shaper, orchestrator, and the shared spec) to match the JSON value `state.mode == "standard"`.

### Tests

- **`tests/unit/ac_extractor_test.py`** + **`tests/unit/platform_detect_test.py`** — new CLI tests exercise the `__main__` blocks via `subprocess.run`, asserting JSON shape and exit codes.
- `tests/structural/fg-010-shaper-shape.bats` (B13) `skip` clauses lift now that the seven canonical headings are present.

### Notes

- **Helper-module CLI gap caught at review** — Phase A shipped library-only Python helpers (`ac-extractor.py`, `platform-detect.py`); Phase C's shaper and orchestrator prose called them as if they had CLIs. Neither phase verified the cross-layer contract end-to-end. The review caught this as CRITICAL-1/2; the fix wave backfilled both CLIs in `044c6dbc`. Lesson: agent-prose contract changes must be paired with a contract-test commit that exercises the prescribed shell command, not just the library function.
- **Cross-phase polish from review** — schema/parser/enum drifts (auth_method, OTel event names, mode value, FTS5 table name) all fixed in `c1ac042b`. The shared spec at `docs/superpowers/specs/2026-04-27-skill-consolidation-design.md` is allowlisted and was edited inline (still retained for Megas D/E).
- Carried-over dirty files (`spring/*`, `kotlin.md`, `tests/lib/bats-core`) remain unstaged across the v5.1.0 release window per existing convention.

## [5.0.0] — Mega B: Skill Surface (BREAKING)

### Removed (BREAKING)

The 27 individual `/forge-<verb>` skills are removed. Their functionality is preserved as subcommands of three consolidated entry skills (`/forge`, `/forge-admin`, `/forge-ask`). Per `feedback_no_backcompat`, **no migration shim** is provided — old-name callers surface a "skill not found" at dispatch time.

Deleted directories (27 atomic via `git rm -r`):

`forge-abort`, `forge-automation`, `forge-bootstrap`, `forge-commit`, `forge-compress`, `forge-config`, `forge-deploy`, `forge-docs-generate`, `forge-fix`, `forge-graph`, `forge-handoff`, `forge-history`, `forge-init`, `forge-insights`, `forge-migration`, `forge-playbook-refine`, `forge-playbooks`, `forge-profile`, `forge-recover`, `forge-review`, `forge-run`, `forge-security-audit`, `forge-shape`, `forge-sprint`, `forge-status`, `forge-tour`, `forge-verify`.

`/forge-help` was retired earlier in v3.8.0 (Phase 2); recorded here as part of the v5.0.0 closed-set manifest.

`shared/skill-subcommand-pattern.md` deleted; the three consolidated skills inline their dispatch grammar.

### Mapping (old slash-command → new surface)

| Old | New | | Old | New |
|---|---|---|---|---|
| `/forge-init` | `/forge` (auto-bootstrap on first invocation) | | `/forge-recover` | `/forge-admin recover` |
| `/forge-run` | `/forge run` | | `/forge-abort` | `/forge-admin abort` |
| `/forge-fix` | `/forge fix` | | `/forge-config` | `/forge-admin config` |
| `/forge-shape` | `/forge run` (BRAINSTORMING absorbed) | | `/forge-handoff` | `/forge-admin handoff` |
| `/forge-sprint` | `/forge sprint` | | `/forge-automation` | `/forge-admin automation` |
| `/forge-review` | `/forge review` | | `/forge-playbooks` | `/forge-admin playbooks` |
| `/forge-verify` | `/forge verify` | | `/forge-playbook-refine` | `/forge-admin refine` |
| `/forge-deploy` | `/forge deploy` | | `/forge-compress` | `/forge-admin compress` |
| `/forge-commit` | `/forge commit` | | `/forge-graph` | `/forge-admin graph` |
| `/forge-migration` | `/forge migrate` | | `/forge-status` | `/forge-ask status` |
| `/forge-bootstrap` | `/forge bootstrap` | | `/forge-history` | `/forge-ask history` |
| `/forge-docs-generate` | `/forge docs` | | `/forge-insights` | `/forge-ask insights` |
| `/forge-security-audit` | `/forge audit` | | `/forge-profile` | `/forge-ask profile` |
| `/forge-help` | `/forge --help` | | `/forge-tour` | `/forge-ask tour` |

### Added (Phase B1-B3 — Three consolidated skills)

- **`skills/forge/SKILL.md`** (384 lines, `[writes]`) — universal write-surface entry. Hybrid grammar: 11 verb subcommands (run, fix, sprint, review, verify, deploy, commit, migrate, bootstrap, docs, audit) plus NL fallback through `shared/intent-classification.md`. Auto-bootstrap on missing `.claude/forge.local.md` via `shared/bootstrap-detect.py` (added in A2). Top-level flags `--dry-run`, `--autonomous`, `--from=<stage>`, `--spec`, `--background` consumed before verb dispatch.
- **`skills/forge-admin/SKILL.md`** (1532 lines, `[writes]`) — state-management surface. 9 subcommands: recover, abort, config, handoff, automation, playbooks, refine, compress, graph. Bodies copied verbatim from the now-deleted source skills. `### Subcommand: graph` enforces read-only Cypher (regex bans `CREATE | MERGE | DELETE | SET | REMOVE | DROP`).
- **`skills/forge-ask/SKILL.md`** (1000 lines, `[reads]`) — read-only surface (rewrite of pre-existing 171-line `/forge-ask`). 6 subcommands: ask (default NL Q&A), status, history, insights, profile, tour. `allowed-tools` excludes `Write`/`Edit` (AC-S012 contract; writes via `Bash` heredoc to `.forge/ask-cache/` and `.forge/reports/` only). Absorbs `forge-status --- live ---` content from Phase 1 Task 24.

### Changed (Phase B5-B10 — Repo-wide rewire)

- **~150 files rewired** across `docs/`, `tests/`, `agents/`, `shared/`, `modules/`, root files (`README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `plugin.json`, `marketplace.json`, `install.sh`, `install.ps1`, `.github/`, `hooks/`, `evals/`). Drove by a single canonical perl mapping run against the B4 snapshot (`tests/structural/migration-callsites.txt`, 313 lines).
- B7 manually reviewed `agents/fg-100-orchestrator.md`, `agents/fg-700-retrospective.md`, `agents/fg-710-post-run.md` for embedded refs missed by the perl boundary.
- B8 reconciled `shared/intent-classification.md` to preserve A5's 11-verb list.
- **AC-S005 callsite-cleanliness regex hardened** to use `HEAD/TAIL` character classes that reject path-separator and identifier neighbours, addressing the failure mode where `\b` fired on filesystem paths and compound names like `forge-config-template.md`.

### Added (Phase B13 — Test fixtures)

- **`tests/structural/skill-consolidation.bats`** (13 tests) — locks in the 3-skill surface; asserts retired-name absence; per-skill subcommand counts (11/9/6); frontmatter strings; read-only contracts; AC-S005 straggler check (hardened regex).
- **`tests/unit/skill-execution/forge-dispatch.bats`** (15 tests) — 11 verb dispatch + 4 NL fallback (vague-input, classifier-resolved, unknown-verb, ambiguous-flag).
- **`tests/unit/skill-execution/spec-wellformed.bats`** (AC-S029) — regex for `## Objective | ## Scope | ## Acceptance Criteria` triple.
- **`tests/scenarios/autonomous-cold-start.bats`** (AC-S027) — full-pipeline cold-start scenario.
- **`tests/structural/fg-010-shaper-shape.bats`** (AC-S021) — `skip` clauses keep it green until Mega C lands the 7-step BRAINSTORMING headers.
- **`tests/structural/skill-references-allowlist.txt`** (13 entries) — explicit allowlist of files where retired-name references are intentionally retained (CHANGELOG, DEPRECATIONS, SHIP_ORDER, HANDOFF, Mega B plan, Mega E plan, Phase 2 design, shared spec, the 3 SKILLs, the snapshot, and the bats fixture itself).
- **`tests/structural/migration-callsites.txt`** — frozen B4 snapshot (313 lines); canonical input to B5-B10's perl pipeline.

### Removed (Tests)

- **`tests/contract/test_skill_inventory.py`** — asserted `skill_count == 28` and banned `forge-help` references; both are obsolete post-consolidation. Coverage replaced by `tests/structural/skill-consolidation.bats`.

### Changed (Module lists)

- **`tests/lib/module-lists.bash`** — `MIN_SKILLS=29 → 3`; `EXPECTED_SKILL_NAMES` array replaced with `(forge forge-admin forge-ask)` and now consumed by `skill-consolidation.bats` (DRY).

### Notes

- **Sed-substitution discipline gap** — B5-B10's perl pattern used `\b` word-boundary, which fires on path separators (`.claude/forge-config.md` matched `/forge-config\b`). The first review caught 75+ filesystem-path refs miscorrected to `.claude/forge-admin config.md` (literal-space path); the post-review fix wave reverse-substituted these and replaced the AC-S005 regex with `HEAD/TAIL` character classes that reject path neighbours. Future similar work should anchor on `(?<![./-])/forge-<verb>` from the start.
- **Plan + shared spec carry-over** — `docs/superpowers/specs/2026-04-27-skill-consolidation-design.md` is intentionally allowlisted and **retained** through this release; it is the shared mapping holder for Megas C/D/E and is removed only when Mega E ships. The Mega B plan is removed at this release per `feedback_cleanup_after_ship`.
- Carried-over dirty files (`spring/*`, `kotlin.md`, `tests/lib/bats-core` submodule) remain unstaged across the Mega B release window per existing convention.

## [4.3.0] — Mega A: Helpers + Schema

### Added (Phase A1 — Autonomous AC extractor)

- **`shared/ac-extractor.py`** — stdlib-only Python 3.10+ regex extractor. Three patterns: numbered list (`1.` / `1)`), Given/When/Then BDD lines, imperative-verb bullets (`must|should|will|ensure|validate|return|expose|accept|reject`). Imperative verb is retained in the extracted AC body. Patterns applied in source-line order (deduplicated, order-preserving). Three-tier confidence enum (`low` < 2 ACs / `medium` 2-4 / `high` 5+). Used by `fg-010-shaper` autonomous-mode degradation path (Mega C1).

### Added (Phase A2 — Atomic bootstrap detect)

- **`shared/bootstrap-detect.py`** — `detect_stack(repo_root: Path) -> StackResult` probes Kotlin/Spring (build.gradle.kts), TypeScript/Next (package.json + next.config.{js,mjs,ts,cjs} or tsconfig), Python/FastAPI/Django (pyproject.toml). Returns `ambiguous: True` when 0 or ≥2 stacks match. **`write_forge_local_md(stack, target_path)` uses atomic-write contract**: write to `<target>.tmp` → `Path.replace` (cross-platform atomic on POSIX and Windows ≥ Vista). Refuses to write ambiguous stacks. Cleans temp on failure. AC-S027 covered by simulated-interrupt test (monkeypatch `Path.replace` to raise; assert target absent + temp cleaned). Used by `skills/forge` and `skills/forge-admin` config wizards (Mega B).

### Added (Phase A3 — Platform detection + adapter stubs)

- **`shared/platform-detect.py`** — `detect_platform(repo_root, config=None) -> PlatformInfo`. Resolution: explicit `config['platform']['detection']` override → `git remote get-url <remote_name>` match against known hosts (github.com, gitlab.com, bitbucket.org with anchored regex `(?:^|@|//)host[:/]` to reject `subgithub.com`-style spoofs) → Gitea API probe at `<host>/api/v1/version` (User-Agent header; per-socket-op timeout, not wall-clock — documented). Falls back to `platform: "unknown"`. Auth env-var map: `GITLAB_TOKEN`, `BITBUCKET_APP_PASSWORD`, `GITEA_TOKEN` (GitHub uses `gh` CLI auth, no env-var canonical).
- **`shared/platform_adapters/{__init__,github,gitlab,bitbucket,gitea}.py`** — 4 adapter stubs raising `NotImplementedError("D5 wires this up")`. `__init__.py` exposes `PlatformAdapter` Protocol + `PostResult` TypedDict so D5 has a typed contract.

### Added (Phase A4-A5 — Config + classification docs)

- **`shared/preflight-constraints.md`** — 7 new validation bullets covering 16 mega-consolidation config keys: `brainstorm.*` (enabled, spec_dir with PREFLIGHT write-probe, autonomous_extractor_min_confidence, transcript_mining.*), `quality_gate.consistency_promotion.*`, `bug.{hypothesis_branching,fix_gate_threshold}`, `post_run.{defense_enabled,defense_min_evidence}`, `pr_builder.{default_strategy,cleanup_checklist_enabled}`, `worktree.stale_after_days`, `platform.{detection,remote_name}`. All keys go in `<!-- locked -->` blocks (not subject to retrospective auto-tuning).
- **`shared/intent-classification.md`** — new "Hybrid-grammar verbs" section: 11 explicit verbs (run, fix, sprint, review, verify, deploy, commit, migrate, bootstrap, docs, audit) recognized at first-token position with priority over signal-counting. Concrete "Vague outcome" definition: signal-count < 2 AND no explicit-verb match → routes to `run` mode (which triggers BRAINSTORMING).

### Changed (Phase A6 — State schema bump)

- **State schema v2.0.0 → v2.1.0** (`shared/state-schema.md`, `shared/checks/state-schema-v2.0.json`, `shared/python/state_init.py`). Per `feedback_no_backcompat`: no migration shim. Adds:
  - `state.story_state` enum gains **`BRAINSTORMING`** (between PREFLIGHT and EXPLORING)
  - **`state.brainstorm`** — spec_path, original_input (verbatim free-text input), started_at/completed_at, autonomous, questions_asked, approaches_proposed, section_approvals
  - **`state.bug`** — ticket_id, reproduction_attempts/succeeded, branching_used, fix_gate_passed, hypotheses[] with id/statement/falsifiability_test/evidence_required/status/passes_test/confidence/posterior
  - **`state.feedback_decisions[]`** — comment_id, verdict (actionable|wrong|preference), reasoning, evidence, addressed (actionable_routed|defended|defended_local_only|acknowledged), posted_at
  - **`state.platform`** — name, remote_url, api_base, auth_method, detected_at
- **`shared/state-transitions.md`** — 4 new BRAINSTORMING transition rows (PREFLIGHT→BRAINSTORMING gated on `mode==feature AND brainstorm.enabled AND not dry_run`; BRAINSTORMING→EXPLORING on completion; BRAINSTORMING→ABORTED on user abort; BRAINSTORMING self-loop on resume from cache). Deferred-C2 note for `--spec` and `--from=<stage>` skip paths.
- **`shared/stage-contract.md`** — BRAINSTORMING declared as Stage 0.5 (conditional, feature-mode-only) in both overview table and per-stage block. Avoids renumbering 10 stages (deferred to Mega C2).
- **6 OTel events registered** (slot only; emission lands in C1/C2): `forge.brainstorm.{started, question_asked, approaches_proposed, spec_written, completed, aborted}`.

### Changed (Tooling)

- **`pyproject.toml`** — `python_files` accepts both `test_*.py` and `*_test.py` so the new helper tests are discovered by `pytest tests/unit -q`.

### Tests

- 40 new pytest cases (`tests/unit/{ac_extractor,bootstrap_detect,platform_detect}_test.py` covering AC patterns + confidence boundaries + atomic-write under simulated interrupt + disk-full + 4 platform happy paths + explicit override + missing auth + DNS-rebind defense). Hoisted `load_hyphenated_module` helper to `tests/unit/conftest.py`.
- 30 new bats structural tests (`tests/structural/{preflight-new-keys,intent-classification-verbs,state-schema-mega}.bats`).

### Notes

- `shared/python/state_transitions.py` FSM event wiring (`brainstorm_complete`, `resume_with_cache`) is intentionally deferred to Mega C2; `tests/contract/state-machine-contract.bats:59` will remain red until that orchestrator surgery lands.
- Carried-over dirty files (`shared/ac-extractor.py`, `tests/unit/ac_extractor_test.py`) staged for the first time in Wave 1 (commit `38ab7796`); the carry-over set is reduced from 7 to 5 (spring/* and kotlin.md remain unstaged across phases).

## [4.2.0] — Phase 7 Intent Assurance

### Added (F35 — Intent Verification Gate)

- **`fg-540-intent-verifier`** (Tier 3, color violet, tools `['Read','Grep','Glob','WebFetch']` — explicitly no Bash/Edit/Write/Agent/Task) dispatched at end of Stage 5 VERIFY. Receives an orchestrator-filtered context brief that excludes plan / tests / diff / prior findings.
- **Two-layer context isolation.** Layer 1 (`hooks/_py/handoff/intent_context.py:build_intent_verifier_context`) is the enforcement — `ALLOWED_KEYS` allow-list + deep-leak walker (covers dict keys, lists, tuples, sets, bytes; fail-closed on unknown types). Layer 2 (agent-side "Context Exclusion Contract" clause) is defense-in-depth.
- **Sandboxed runtime probes** (`hooks/_py/intent_probe.py`) — `ipaddress`-based forbidden-host parser (CIDR + IPv6 + metadata ranges); HTTP scheme allowlist `{http, https}`; userinfo rejected; IPv6 scope-id stripped; custom opener restricts handlers (no `file://` / `ftp://`); DNS-rebind defense via `resolve_host_for_denylist`; per-AC budget + timeout; deny-path warning logs; `IMPL-VOTE-WORKTREE-FAIL`-style fallback semantics.
- **Five `INTENT-*` scoring categories** + `INTENT-NO-ACS` + `INTENT-CONTEXT-LEAK` (7 total) registered in `shared/checks/category-registry.json` and mirrored in `shared/scoring.md`.
- **Hard SHIP gate** in `agents/fg-590-pre-ship-verifier.md` Step 6: `verdict = SHIP` requires 0 open `INTENT-MISSED` CRITICAL findings AND `verified_pct >= intent_verification.strict_ac_required_pct` (default 100). Vacuous-pass path documented; strict-mode promotes `INTENT-NO-ACS` to BLOCK.
- **OTel spans** `forge.intent.verify_ac` (per AC) and `forge.impl.vote` (per voted sample) with 10 new `forge.intent.*` / `forge.impl_vote.*` attribute constants (`hooks/_py/otel_attributes.py`).
- **AC source precedence:** `state.brainstorm.spec_path` (canonical post-Mega-C) → `.forge/specs/index.json` (fallback for bugfix/migration/bootstrap or pre-Mega).

### Added (F36 — Confidence-Gated Implementer Voting)

- **`fg-302-diff-judge`** (Tier 4, color gray, Read-only) compares two parallel `fg-300-implementer` samples via structural AST diff.
- **`hooks/_py/diff_judge.py`** engine: Python via stdlib `ast` (canonical dump + SHA256); 11 other languages via `tree-sitter-language-pack` 1.6.3 with feature-detected `get_language()` (defensive `tsx → typescript` and `kts → kotlin` fallback); whitespace+comment-stripped textual fallback otherwise. Iterative-DFS AST serialization (no `RecursionError` on deeply-nested files); io-error wrapping; frozen dataclasses. `judge()` raises `ValueError` on empty `touched_files` (no silent SAME-on-zero); confidence forced LOW when all comparisons are file-presence-only.
- **N=2 voting gate** (`agents/fg-100-orchestrator.md` `should_vote` + `dispatch_with_voting`) gated on (a) `impl_voting.enabled`, (b) >30% budget remaining, (c) any of: LOW confidence, high-risk task tags, or recent regression history.
- **`task.risk_tags[]`** emitted by `fg-200-planner` per task. Closed canonical vocabulary (`hooks/_py/risk_tags.BASE_RISK_TAGS`): `{high, data-mutation, auth, payment, concurrency, migration}`. Mode overlay extension: `bugfix → +"bugfix"`.
- **Sub-worktrees at `.forge/votes/<task_id>/sample_{1,2}/`** with crash-recovery stale sweep extension to `fg-101-worktree-manager.detect-stale`.
- **`IMPL-VOTE-WORKTREE-FAIL` fallback** in orchestrator: try/except around `fg101_create`, emits WARNING + appends `skipped_reason: "worktree_fail"` to `impl_vote_history`, falls back to single-sample dispatch.
- **6 informational telemetry categories** (`IMPL-VOTE-TRIGGERED/DEGRADED/UNRESOLVED/TIMEOUT/WORKTREE-FAIL` + `COST-SKIP-VOTE`) with explicit `score_impact: "0"`.

### Added (Verification & Analytics)

- **`shared/intent-verification.md`** — end-to-end architectural doc with ASCII dataflow diagrams; covers F35 + F36, two-layer isolation rationale, voting topology, 30%-vs-20% cost-skip rationale, syntactic-vs-semantic diff caveat.
- **`fg-700-retrospective.md` §2j** Intent & Vote Analytics + **§2j.bis** Cost-of-voting analytics (`vote_cost_usd`, `vote_cost_pct_of_run`, `vote_savings_estimate_usd`).
- **Auto-tuning Rule 11** (propose-only via `/forge-playbook-refine`): `intent_missed_count >= 2` across last 3 runs proposes `living_specs.strict_mode: true`.
- **9 scenario tests** under `tests/scenario/sc-{intent-missed,impl-vote-diverge,impl-vote-disabled,impl-vote-cost-skip,autonomous-intent,vote-worktree-cleanup,retrospective-intent-metrics,intent-no-acs,intent-layer2-tripwire}/`.

### Changed

- **State schema** v2.0.0 narrative + canonical `state-schema.json` + `state-schema-fields.md` document new top-level keys `intent_verification_results[]` and `impl_vote_history[]`. (Schema literal already at 2.0.0 from coordinated Phase 5/6 bump; Phase 7 only adds the two new arrays.)
- **Finding schema v1 → v2** (`shared/checks/finding-schema.json`): `file` and `line` become nullable; `ac_id` conditional-required when `category` starts with `INTENT-`.
- **Agent count 48 → 50** at every callsite (`CLAUDE.md`, `shared/agents.md`).
- **`fg-300-implementer` §5.3c "Voting Mode"** — `dispatch_mode: vote_sample` (skips REFLECT) / `vote_tiebreak` (reconciles divergences).
- **`fg-101-worktree-manager.detect-stale`** scans `.forge/votes/*/sample_*` (orphaned sub-worktree sweep).
- **`shared/state-integrity.sh`** stale-detection block for `.forge/dispatch-contexts/`; `${DISPATCH_CONTEXT_STALE_HOURS:-24}` config-driven.
- **`agents/fg-100-orchestrator.md` PREFLIGHT** instructs `rm -rf .forge/dispatch-contexts/` (canonical destructive cleanup; ephemeral, not preserved across runs).
- **Mode overlays.** `bootstrap` disables F35 + F36 (greenfield: no ACs, no risk baseline). `migration` disables F35 (use `fg-506-migration-verifier` instead). `bugfix` extends `impl_voting.trigger_on_risk_tags` with `"bugfix"`.
- **`tests/contract/test_fg100_size_budget.py`** `MAX_LINES` 1800 → 2000 (orchestrator grew through Phase 7 voting + intent dispatch wiring; per maintainer policy the orchestrator is loaded once per run, not per stage).
- **24 framework `forge-config-template.md`** files declare `intent_verification:` and `impl_voting:` blocks.

### Dependencies

- Added `tree-sitter>=0.25.2,<0.26` and `tree-sitter-language-pack>=1.6.3,<2.0` under `[project.optional-dependencies].test`. Production install unaffected.

## [4.1.0] — Phase 6 Cost Governance

### Added

- **USD cost ceiling** (`cost.ceiling_usd`, default $25). Orchestrator blocks any dispatch that would breach the ceiling; in interactive mode escalates via AskUserQuestion (pattern §8), in autonomous mode auto-decides per `cost_governance.downgrade_tier()`.
- **`## Cost Budget` brief injection** — every dispatched subagent receives a current Spent/Remaining/Tier summary.
- **Soft cost throttle in implementer (§5.3b)** — emits `COST-THROTTLE-IMPL` INFO at 80% / WARNING at 90% consumed; skips discretionary refactor+critic passes while keeping RED/GREEN inviolate.
- **Dynamic tier downgrade** (`cost.aware_routing: true`) with hardcoded SAFETY_CRITICAL list: `fg-210`, `fg-250`, `fg-411`, `fg-412`, `fg-414`, `fg-419`, `fg-500`, `fg-505`, `fg-506`, `fg-590`. These agents are NEVER silently skipped.
- **`forge.cost.*` / `forge.agent.tier_*` OTel attributes** — six new attrs on every dispatch span, round-tripped through `otel.replay()`.
- **Cost incident log** — `.forge/cost-incidents/<timestamp>.json` per escalation, schema at `shared/schemas/cost-incident.schema.json`.
- **Retrospective cost analytics** — per-run summary, cost-per-actionable-finding flagging (gated on peer cohort ≥1 CRITICAL/WARNING), EST-DRIFT detection, four new `run_summary` columns (migration 002).
- **300-second default timeout** for interactive AskUserQuestion patterns §3, §7, §8.

### Changed

- **`shared/forge-token-tracker.sh` pricing table** refreshed to Anthropic 2026-04-22 rates: Haiku 4.5 $1/$5, Sonnet 4.6 $3/$15, Opus 4.7 $5/$25 per MTok.
- **State schema bumps to v2.0.0** (coordinated with Phase 5 and Phase 7). Old `1.x.x` state files reset `cost` block on load per no-backcompat policy.
- **`shared/observability.md`** codifies `forge.*` namespace contract; Phase 4's unprefixed `learning.*` attrs are renamed to `forge.learning.*` as a prerequisite.

### Tests

- 3 unit bats suites (cost-governance-helpers, cost-governance-downgrade, token-tracker-pricing)
- 8 scenario bats suites (ceiling-interactive, ceiling-autonomous, soft-throttle, incident-write, otel-attrs, no-silent-safety-skip, ceiling-disabled, aware-routing, retro-per-finding)
- 1 contract extension (framework-config-templates.bats — 24 frameworks × 3 assertions)

## [4.0.0] - 2026-04-27

### Breaking

- Renamed `fg-205-planning-critic` → `fg-205-plan-judge` with binding REVISE authority.
- Renamed `fg-301-implementer-critic` → `fg-301-implementer-judge` with binding REVISE authority.
- State schema bumped v1.x → v2.0.0 (coordinated with Phases 6 and 7). Fields `critic_revisions` and `implementer_reflection_cycles` removed; replaced by `plan_judge_loops` (int), `impl_judge_loops` (object keyed by task_id), `judge_verdicts[]` (array of {judge_id, verdict, dispatch_seq, timestamp}).
- Stage 6 REVIEW migrated from batched-dispatch-with-dedup-hints to Agent Teams pattern (shared findings store at `.forge/runs/<run_id>/findings/<reviewer>.jsonl`, append-only, read-peers-before-write).
- `shared/agent-communication.md` Shared Findings Context section deleted; replaced by Findings Store Protocol reference.
- fg-400-quality-gate §5.2 (inter-batch dedup hints / "previous batch findings" / "top 20" prose) deleted — fg-400 still dispatches reviewers in parallel fan-out, but dedup is now read-time per the Findings Store Protocol (`shared/findings-store.md`). Reviewer registry §20 shrunk to a 3-line reference; orchestrator injects the registry slice into the Stage 6 dispatch payload (`fg-100` SS6.1a) and fg-400 forwards it verbatim into each reviewer's prompt.
- v1.x state.json files are auto-invalidated on version mismatch (no migration shim, per `feedback_no_backcompat`).

## [3.10.0] - 2026-04-27

Phase 4 of the A+ roadmap (Learnings Dispatch Loop) ships. The learning database becomes an active prompt-time input: relevant learnings inject into agent prompts at PLAN/IMPLEMENT/REVIEW, then reinforce via marker-protocol parsing at LEARN.

### Added

- **Phase 4: Learnings Dispatch Loop**
  - **Foundation modules:**
    - `hooks/_py/memory_decay.py` — `pre_fp_base` snapshot, `apply_vindication()` for bit-exact restore, `archival_floor()` returning `(bool, reason)`. New constants: SPARSE_THRESHOLD, MAX_DELTA_T_DAYS, ARCHIVAL_CONFIDENCE_FLOOR, ARCHIVAL_IDLE_DAYS, VINDICATE_FALLBACK_FACTOR.
    - `hooks/_py/agent_role_map.py` — frozen 12-entry MappingProxyType (fg-200, fg-300, fg-400, 9 reviewers). `role_for_agent()` API.
    - `hooks/_py/learnings_selector.py` — frozen `LearningItem` dataclass + `select_for_dispatch()` with role/domain/recency/cross-project ranking and id-ascending tiebreak.
    - `hooks/_py/otel_attributes.py` — 5 `FORGE_LEARNING_*` constants + `FORGE_AGENT_NAME` registered in UNBOUNDED/BOUNDED_ATTRS.
  - **Schema migration:** v1 → v2 across 292 learning files in `shared/learnings/`. Migration script removed after successful application (no shim, per "no back-compat" rule).
  - **I/O stack:** `learnings_io.py` (parser, `_body_slice` scoped past frontmatter, matches `id="X"` HTML anchors), `learnings_format.py` (`## Relevant Learnings` block renderer + `_sanitize` strips control bytes), `learnings_markers.py` (line-anchored parser for LEARNING_APPLIED / LEARNING_FP / LEARNING_VINDICATED), `learnings_writeback.py` (applies markers + archival floor with idempotent updates).
  - **Orchestrator dispatch seam:** `agents/fg-100-orchestrator.md` §0.6.1 builds dispatch context, wraps the rendered block in `<untrusted source="learnings">` envelope before concatenating into the agent prompt. Cache invalidation at LEARN stage.
  - **12 agent prompts** — fg-200, fg-300, fg-400, and the nine reviewers (fg-410..414, fg-416..419) gain `## Learnings Injection` sections describing how they consume the injected block and emit reinforcement markers.
  - **Tests:** structural decay-singleton bats; orchestrator-seam contract bats; cache-invalidation contract bats; integration test exercising the full loop; sanitization hardening tests; `_body_slice` smoke test against real spring.md (204 items render real prose, zero empty bodies).
  - **Documentation:** `decay.md` (explicit formulas + §10 Vindication), `learnings/README.md` (§Read Path), `cross-project-learnings.md` (§Selector Interaction), `observability.md` (forge.learning.* events + attributes), `agent-communication.md` (§Learning Markers parallel to §PREEMPT), `CLAUDE.md` (Phase 4 read path summary).

### Changed

- `state.learnings_cache` field documented in `shared/state-schema-fields.md`.
- `_body_slice` rewritten — was matching anchors inside YAML frontmatter, leaking schema text into rendered prompts. Now scoped past frontmatter and aligned with the `<a id="X">` migration convention.
- `body_ref` values normalized to bare ids (no `#` prefix) across 28 learning files; legacy `#X` form still tolerated.
- `bats` contract tests use `python3` explicitly (cross-platform).

### Process

30 plan tasks across 28 implementation commits. Code review via `superpowers:requesting-code-review` found 3 critical / 6 important / 8 minor. All 17 issues fixed across 10 follow-up commits before release. Critical #1+#2 (`_body_slice` broken end-to-end) caught before any agent dispatch saw malformed payloads. Phase 1-3 ACs re-verified (in scope) — no regressions.

## [3.9.0] - 2026-04-27

Phase 3 of the A+ roadmap (Correctness Proofs) ships. Closes 4 correctness gaps with proof-grade infrastructure.

### Added

- **Phase 3: Correctness Proofs**
  - **Convergence engine `>=` boundary fix:** flipped strict `>` to `>=` in `shared/convergence_engine_sim.py` and `shared/python/state_transitions.py`. Off-by-one bug fix that under-counted plateau iterations. 4 new boundary tests in `tests/unit/test_convergence_engine_sim.py` (16 tests pass total). Documentation aligned in `convergence-engine.md`, `state-transitions.md` rows 37/C9, `convergence-examples.md` (Scenarios 5+6), CLAUDE.md.
  - **End-to-end dry-run smoke harness** at `tests/e2e/dry-run-smoke.py` — symlinks plugin into a temp project (Windows junction fallback), runs forge through PREFLIGHT→VALIDATE only, verifies state.json shape. `--self-test` negative control. Exit-77 SKIP semantics for env-level failures. Cross-OS `e2e:` job in `.github/workflows/test.yml`. Fixture: `tests/e2e/fixtures/ts-vitest/`.
  - **State-transitions sensitivity probe** at `tests/mutation/state_transitions.py` (renamed from "mutation testing" to clarify semantics — flips bats scenario assertions via MUTATE_ROW env var; not classical source mutation). Negative-control baseline run per seed row. 5 seed rows. Canary fixtures + tests. New `mutation:` CI job. Schema test pins REPORT.md columns.
  - **Scenario coverage reporter** at `tests/scenario/report_coverage.py` — walks `# Covers:` headers, generates `tests/scenario/COVERAGE.md` matrix vs `state-transitions.md` rows. Tightened table parser (gates on canonical headers only). Python 3.10+ pinned. New `coverage:` CI job with **T-* hard gate at 60%** (current: 86.3%, well above). Backfilled `# Covers:` headers across the entire scenario suite (T-* coverage 19.6% → 86.3%).
  - **Pathlib-only enforcement** extended to all 3 new Phase 3 harnesses.
  - **`tests/README.md`** — 8-tier matrix + regen workflow.
  - **`README.md`** — testing tier matrix added.

### Changed

- `tests/scenario/oscillation.bats` test 5 tolerance bumped 20 → 21 to reflect post-`>=` boundary semantics (delta=-20 now equals tolerance=20 → REGRESSING; tolerance=21 preserves "very permissive" intent).
- 51 existing scenario `.bats` files gained `# Covers:` headers (4 explicitly enumerate every T-/C-/E-/D-/R- row; 47 are placeholder pending follow-up).
- `tests/validate-plugin.sh` Phase 3 harness check now prints stderr on parse failure (was silenced).

### Process

29 plan tasks landed across 11 implementation commits. Code review via `superpowers:requesting-code-review` found 2 critical / 7 important / 11 minor. All 20 issues fixed across 14 follow-up commits before release. Phase 1 + Phase 2 ACs re-verified after Phase 3 fixes (in scope of mutation harness changes) — no regressions.

## [3.8.0] - 2026-04-27

Phase 2 of the A+ roadmap (Contract Enforcement) ships. Closes 5 contract and hygiene gaps.

### Added

- **Phase 2: Contract Enforcement**
  - 5 pytest contract tests under `tests/contract/test_*.py` — `ui_frontmatter_required`, `skill_grammar`, `fg100_size_budget`, `feature_matrix_freshness`, `skill_inventory`. 207+ assertions enforcing structural contracts that bats can't easily express.
  - **Universal `ui:` frontmatter:** all 48 fg-* agents now carry explicit `ui:` blocks (13 missing agents added; Tier-4-by-omission no longer accepted).
  - **Skill grammar contract:** `shared/skill-grammar.md` defines strict skill `ui:` block shape (`{tasks, ask, plan_mode}`); 8 skills migrated from shorthand. §4 accepts both `## Subcommands` and `## Subcommand dispatch` headings.
  - **Feature activation matrix:** `shared/feature-matrix.md` (30-row activation table, sentinel-fenced), `shared/feature-lifecycle.md` (90/180-day deprecation policy), `shared/feature_matrix_generator.py` (idempotent regenerator), `shared/feature_deprecation_check.py` (180-day removal-PR proposer), `shared/run-history/migrations/002-feature-usage.sql`. `agents/fg-700-retrospective.md` aggregates feature_usage. `agents/fg-100-orchestrator.md` emits `feature_used` events into `.forge/events.jsonl`.
  - **fg-100-orchestrator size budget:** `tests/contract/test_fg100_size_budget.py` enforces a 1800-line ceiling. `shared/agent-philosophy.md` adds the authoring rule.
  - **pyproject test extras:** `pip install -e ".[test]"` brings `pydantic>=2.0`, `pyyaml>=6.0`, `pytest>=8.0`. CI installs via this group; `tests/run-all.sh` dispatches pytest after bats in `contract` and `all` tiers.

### Changed

- **`/forge-help` skill DELETED.** LLM routing handles skill discovery. Skills count: 29 → 28. References scrubbed across CLAUDE.md, README.md, skill-contract.md, forge-config/tour skills, tests.
- **`/forge-verify --config` subcommand DELETED.** Folded into `/forge-status` (Config validation summary section). 10 stale references swept across CLAUDE.md (3), README.md, and 6 SKILL.md files.
- **`/forge-status` extended:** absorbs config validation + recent hook failures sections. `/forge-recover diagnose` embeds `/forge-status --json`.
- **`forge-sprint` skill:** drops `EnterPlanMode`/`ExitPlanMode` from `allowed-tools` (was inconsistent with `ui.plan_mode: false`).
- **`feature_usage.run_id` column:** gains `REFERENCES runs(id) ON DELETE CASCADE` (matches rest of run-history schema).

### Removed

- `skills/forge-help/` (directory)
- `tests/unit/skill-execution/decision-tree-refs.bats` (all 7 tests referenced forge-help)
- `/forge-verify --config` subcommand
- Phase 1 contradictory bats assertion `every Tier-4 agent omits ui:` (rewritten to `every fg-*.md agent has explicit ui: block`).

### Process

29 plan tasks landed across 7 implementation commits. Code review via `superpowers:requesting-code-review` found 4 critical / 6 important / 13 minor. All 23 issues fixed across 9 follow-up commits before release. Phase 1 ACs re-verified after Phase 2 fixes — no regressions. 2429 contract tests pass; 19 structural bats pass.

## [3.7.0] - 2026-04-27

Phase 1 of the A+ roadmap (Truth & Observability) ships. Closes four credibility gaps: Windows is now a real first-class CI target, every hook crash gets a durable JSONL audit trail, every module is tagged with a truthful support tier, and a cat/jq/Get-Content-readable live-run surface is live. Plus the cross-verification prerequisite edits coordinating the 13-plan ship train (`SHIP_ORDER.md`).

### Added

- **Phase 1: Truth & Observability** — Windows install helper (`install.ps1`);
  bash helper (`install.sh`) supersedes `ln -s`; `shared/check-environment.sh`
  ported to `shared/check_environment.py`; `tests/run-all.ps1` + `run-all.cmd`
  wrappers; new CI jobs `test-windows-pwsh-structural` and `test-windows-cmd`.
  `hooks/_py/failure_log.py` + `hooks/_py/progress.py` — every hook entry
  wraps `main()` and appends to `.forge/.hook-failures.jsonl` (renamed from
  `.log`; no shim). `SessionStart` rotates archives (gzip at 7 d, delete at
  30 d). `post_tool_use_agent.py` rewrites `.forge/progress/status.json`
  atomically on every subagent completion. `fg-700-retrospective` generates
  `.forge/run-history-trends.json` (last 30 runs + last 10 hook failures).
  Support-tier badge system: `docs/support-tiers.md`, generator
  `tests/lib/derive_support_tiers.py`, drift gate in `docs-integrity.yml`.
  `/forge-status` gains a `--- live ---` section. `shared/observability.md`
  gains `§Local inspection` recipes for bash/pwsh/cmd.
- **5 new pipeline agents** (opt-in via `agents.*` config schema):
  - `fg-143-observability-bootstrap` (PREFLIGHT Tier-3) — auto-wires OTel exporter when `observability_bootstrap.enabled=true`.
  - `fg-155-i18n-validator` (PREFLIGHT Tier-3) — hardcoded-string / RTL / locale checks; default-enabled.
  - `fg-506-migration-verifier` (VERIFY, migration mode only) — cycles MIGRATING/PAUSED/CLEANUP/VERIFY.
  - `fg-555-resilience-tester` (VERIFY Tier-3, opt-in) — chaos/fault-injection on changed surface.
  - `fg-414-license-reviewer` (split from `fg-417`) — license-compliance finding surface distinct from CVE/compat.
- **`trigger:` expression grammar** and evaluator contract (`shared/agent-communication.md`) — declarative predicate for conditional dispatch.
- **`shared/agents.md`** — consolidates agent model, tier table, dispatch graph, and registry (supersedes the deleted `agent-model.md`, `agent-registry.md`, and narrow parts of `agent-communication.md`).
- **`shared/learnings-index.md`** and `docs.learnings_index.auto_update` config key — retrospective auto-regenerates the index when `true` (default); CI `docs-integrity` workflow enforces freshness regardless.
- **Start Here (5-minute path)** block at the top of `CLAUDE.md` — install / first-run / skill-selection on-ramp.
- **`docs-integrity` CI workflow** (`.github/workflows/docs-integrity.yml`) — strict lychee, anchor check, ADR validator, 600-line ceiling, framework-count guard.
- **`{{REPO_MAP_PACK}}` placeholder** injected into `fg-100-orchestrator`, `fg-200-planner`, and `fg-300-implementer` prompts — replaces full directory listings with PageRank-ranked file packs (30-50% token saving when `code_graph.prompt_compaction.enabled=true`, default OFF).
- **Repo-map A/B eval scenario** and compaction workflow — 20-run graduation gate before default-on consideration.
- **Speculative dispatch section** in `fg-100-orchestrator` — full behavioral contract for when Branch Mode fires.
- **Speculation eval corpus + CI gates** — quality, token, and precision regression guards on speculation.
- **`state.json.plan_candidates` + `speculation.*` fields** — candidate persistence and selection audit.

### Changed

- **`shared/state-schema.md` split** into overview (355L) + `state-schema-fields.md` (1133L, exempt from 600L ceiling). No content change; the two files supersede the former 1461L monolith.
- **Agent docs consolidation** — `shared/agent-communication.md` narrowed to inter-agent messaging; `agent-model.md`, `agent-registry.md`, and `agent-tiers.md` deleted (content merged into `shared/agents.md`).
- **Dead-link sweep** — pre-existing broken links fixed; lychee switched to strict mode.
- **`fg-413-frontend-reviewer` slimmed** to ≤400 lines; frontend-performance findings delegated to `fg-416-performance-reviewer`.
- **`fg-417-dependency-reviewer` split**: license-compliance moved to `fg-414`; `fg-417` now scoped to CVEs / version conflicts / transitive compatibility.
- CLAUDE.md hook count corrected (7 → 6); Agent model row added to Key entry points.

### Fixed

- `.github/workflows/` — `contents: read` permissions added to three workflows lacking an explicit permission block.
- `opentelemetry.io/docs/specs/semconv/*` flake — ignored in `.lycheeignore` (GitHub runners surface intermittent 403s).
- bats-core submodule refreshed to latest tag.

## [3.6.0] — 2026-04-21 — Session Handoff (F34)

Structured, portable session handoff system preserving forge run state across Claude Code session boundaries. Deterministic Python writer (no LLM call), thin projection over existing `.forge/state.json` and F08 retention tags.

### Added

- **`/forge-handoff` skill** — `write`/`list`/`show`/`resume`/`search` subcommands for managing session handoffs (`skills/forge-handoff/SKILL.md`).
- **`hooks/_py/handoff/` package** — `config`, `frontmatter`, `sections`, `redaction`, `writer`, `resumer`, `alerts`, `triggers`, `milestones`, `search`, `auto_memory`, `cli` (12 modules, all deterministic).
- **State-handoff tracking** — `state.json.handoff.*` sub-object (`last_written_at`, `last_path`, `chain`, per-level trigger counters, `suppressed_by_rate_limit`).
- **Trigger levels** — soft (50% default) / hard (70% default) / milestone (stage transitions) / terminal (SHIP/ABORT/FAIL) / manual. Autonomous mode: write-and-continue, never pauses.
- **`CONTEXT_CRITICAL` safety escalation** — interactive-mode-only pause at hard threshold; documented in `shared/error-taxonomy.md`.
- **Compact-check hook integration** — `hooks/_py/check_engine/compact_check.py` dispatches handoff writer at threshold while preserving legacy stderr hint.
- **MCP server tools** (F30 extension) — `forge_list_handoffs(run_id)` + `forge_get_handoff(path)` expose handoff chains to any MCP client.
- **Auto-memory promotion** — top HIGH-confidence PREEMPTs + user-decision statements auto-flow to `~/.claude/projects/<hash>/memory/` on terminal handoffs.
- **FTS5 search** over all handoffs via `run-history.db` (`handoff_fts` virtual table), with freetext phrase-quote escaping to prevent syntax-error crashes.
- **Chain rotation** — past `handoff.chain_limit` (default 50), oldest handoffs move to `handoffs/archive/` silently.
- **`ADR-0012`** — session handoff as a thin state projection, not an LLM summarisation.
- **3 scenario bats tests** in `tests/scenario/handoff-*.bats` + 78 Python unit/integration tests in `hooks/_py/tests/test_handoff_*.py`.

### Changed

- **State schema bumped 1.9.0 → 1.10.0** with new `handoff.*` sub-object (clean cut per no-backcompat policy).
- **`CLAUDE.md`** — adds F34 Feature row, `/forge-handoff` skill selection row, `.forge/runs/<id>/handoffs/` added to `/forge-recover reset` survivors list.
- **`.claude-plugin/plugin.json`** → 3.6.0.
- **`.claude-plugin/marketplace.json`** → 3.6.0 (lockstep with plugin).

### Configuration

- New `handoff.*` config block (see `shared/preflight-constraints.md`): `enabled`, `soft_threshold_pct`, `hard_threshold_pct`, `min_interval_minutes`, `autonomous_mode`, `auto_on_ship`, `auto_on_escalation`, `chain_limit`, `auto_memory_promotion`, `mcp_expose`.

## [3.5.0] — 2026-04-20 — Speculative Plan Branches

Branch-mode planner dispatches 2-3 candidate plans in parallel for MEDIUM-confidence ambiguous requirements, validates each, and selects the highest-scored.

### Added

- **`fg-200-planner` Branch Mode** — N=2-5 parallel candidate invocations with distinct exploration seeds when `speculation.enabled=true` and confidence gate fires MEDIUM (`plans/candidates/` per-run persistence with FIFO eviction).
- **Speculation CLI** (`hooks/_py/speculation/`) — `derive-seed`, `estimate-cost`, `diversity`, `selection`, `winner` subcommands drive candidate generation, cost-aware gating, and tie-break.
- **`plan-cache` schema v2.0** — candidate set + winner tracking; survives `/forge-recover reset`.
- **Repo-map PageRank** (`hooks/_py/repomap.py`) — biased PageRank with recency + keyword-overlap re-ranking, token-budgeted pack assembly, LRU cache (`.forge/ranked-files-cache.json`). `code_graph.prompt_compaction.*` config block. CLI subcommands: `rank`, `pack`, `stats`.
- **`state.json.prompt_compaction`** block records ranked-file hit rate and token savings per stage.
- **`shared/graph/pagerank-sql.md`** — PageRank algorithm reference with SQLite DDL and worked example.
- **`shared/` grouped index** — logical groupings for 80+ shared docs.

### Changed

- `.claude-plugin/plugin.json` → 3.5.0.

## [3.4.0] — 2026-04-20 — OTel GenAI Semconv + Skill Consolidation + Time-Travel Checkpoints

Three major feature streams converged in a single version bump: OpenTelemetry GenAI Semantic Conventions for observability, skill consolidation (35 → 28), and the content-addressable checkpoint DAG.

### Breaking — OTel

- **OTel exporter rewritten in Python.** `shared/forge-otel-export.sh` is **removed**. Use `python -m hooks._py.otel_cli replay ...` for post-hoc export from the event log. Live emission happens automatically via `hooks/_py/otel.py` when `observability.otel.enabled=true`.
- **Attribute rename** — legacy custom names removed; semconv replacements:
  - `tokens_in` → `gen_ai.tokens.input`
  - `tokens_out` → `gen_ai.tokens.output`
  - `agent` → `gen_ai.agent.name`
  - `model` → `gen_ai.request.model`
  - `findings_count` → `forge.findings.count`

  Rebuild dashboards keyed on the old names.
- **Config keys removed.** Replace `observability.export` and `observability.otel_endpoint` with the nested `observability.otel.*` form documented in `shared/observability.md`. `telemetry.export_status` is no longer written to `state.json`.

### Breaking — Skill Consolidation

Seven top-level skills have been removed and their capabilities folded into three unified skills. Skill count: 35 → 28.

| Removed                 | Use instead                              |
|-------------------------|------------------------------------------|
| /forge-codebase-health  | /forge-review --scope=all                |
| /forge-deep-health      | /forge-review --scope=all --fix          |
| /forge-graph-status     | /forge-graph status                      |
| /forge-graph-query      | /forge-graph query <cypher>              |
| /forge-graph-rebuild    | /forge-graph rebuild                     |
| /forge-graph-debug      | /forge-graph debug                       |
| /forge-config-validate  | /forge-verify --config                   |

`/forge-review --scope=all --fix` presents an `AskUserQuestion` safety gate before the first commit unless `autonomous: true` or `--yes`. Subcommand dispatch pattern documented in `shared/skill-subcommand-pattern.md`.

### Breaking — Time-Travel

- **State schema 1.8.0 → 1.9.0.** The linear `.forge/checkpoint-{storyId}.json` format is replaced by a content-addressable DAG under `.forge/runs/<run_id>/checkpoints/`. Orchestrators on v1.9.0+ refuse to proceed on pre-1.9.0 state; run `/forge-recover reset` to migrate (no automatic upgrade — formats are not compatible).

### Added — OTel

- OTel GenAI Semantic Conventions (2026) span emission per pipeline, stage, and agent dispatch (`hooks/_py/otel.py`).
- W3C Trace Context propagation to subagent dispatches via `TRACEPARENT` (`otel.dispatch_env`).
- `ParentBased(TraceIdRatioBased)` sampler — subagent decisions inherit the root. Inbound `sampled=0` is respected (child emits nothing).
- `otel.replay()` — authoritative recovery path from `.forge/events.jsonl`. Live streaming via `BatchSpanProcessor` is best-effort; replay is the source of truth.
- Optional OpenInference compatibility mirror (`observability.otel.openinference_compat: true`) — emits `openinference.span.kind=AGENT`, `llm.token_count.{prompt,completion,total}`, `llm.model_name`, `agent.name` alongside `gen_ai.*` for Arize-heavy backends.
- Pinned semconv schema (`shared/schemas/otel-genai-v1.json`) + CI validator (`tests/unit/otel_semconv_validator.py`).
- CI workflow `.github/workflows/otel.yml` — Docker collector sidecar, semconv conformance test, replay parity job, and disabled-overhead guard (<1ms/stage when `enabled=false`, no `opentelemetry.*` imports).
- `observability.otel.*` PREFLIGHT constraints (`shared/preflight-constraints.md`).
- `[otel]` optional dependency group in `pyproject.toml` — `pip install forge-plugin[otel]` pulls `opentelemetry-api>=1.30.0`, `opentelemetry-sdk>=1.30.0`, `opentelemetry-exporter-otlp>=1.30.0`, `jsonschema>=4.0.0`.
- Orchestrator OTel instrumentation contract documented in `agents/fg-100-orchestrator.md`.

### Added — Time-Travel

- `hooks/_py/time_travel/` Python package — CAS checkpoint store (`cas.py`), atomic rewind protocol with per-run `.rewind-tx/` (`restore.py`), GC policy with HEAD-path protection (`gc.py`), and `RewoundEvent` schema (`events.py`).
- `hooks/_py/time_travel/__main__.py` CLI — invoked as `python3 -m hooks._py.time_travel <op>`; supports `list-checkpoints`, `rewind`, `repair`, `gc`. Exit codes 5/6/7 distinguish dirty-worktree, unknown-id, and tx-collision aborts.
- `/forge-recover rewind --to=<id> [--force]` — time-travel to any prior checkpoint with an atomic four-tuple restore (state, worktree, events, memory).
- `/forge-recover list-checkpoints [--json]` — render the checkpoint DAG with HEAD marked.
- Orchestrator `recovery_op: rewind|list-checkpoints` routing (`agents/fg-100-orchestrator.md` §Recovery op dispatch).
- Orchestrator-start crash repair contract: every active run invokes `python3 -m hooks._py.time_travel repair` to roll forward or discard a half-finished rewind tx.
- Pseudo-state `REWINDING` in `shared/state-transitions.md` — appears only in `events.jsonl` `StateTransitionEvent` pairs that bracket a rewind op; never persists to `state.story_state`.
- `recovery.time_travel.*` config block (`enabled`, `retention_days`, `max_checkpoints_per_run`, `require_clean_worktree`, `compression`, `preserve_legacy`).
- `state.json.checkpoints` (append-only audit array) and `state.json.head_checkpoint` (mirrors on-disk `HEAD`).
- `shared/recovery/time-travel.md` — full protocol spec (CAS layout, atomic 5-step restore, crash repair, DAG semantics, GC policy, failure modes).
- `tests/evals/time-travel/` — bats eval harness covering round-trip, dedup, dirty-worktree abort, crash-mid-rewind repair (rollback + roll-forward), tree-DAG golden output, and rewind-then-replay convergence.
- `tests/run-all.sh` — new `time-travel` tier; the `all` and `eval` tiers now also pick up `tests/evals/time-travel/*.bats` when present.

### Added — Skill Consolidation tests

- `tests/structural/skill-consolidation.bats` — 16 assertions locking in skill count, expected names, removed names, subcommand-dispatch sections, `--json` schema_version, CLAUDE.md "(28 total)" header, and a `validate-config.sh` read-only regression guard.
- `tests/lib/module-lists.bash` — `DISCOVERED_SKILLS`, `MIN_SKILLS=28`, and `EXPECTED_SKILL_NAMES` fixture (28 entries).

### Added — eval harnesses

- Self-consistency voting — eval datasets + harness + CI gates.
- 5 reflection eval scenarios + structural validator.
- Ebbinghaus decay — docs sweep + frontmatter stamping + eval harness.
- Learnings-index generator + initial index; convergence-engine cleanup + anchor-map CSV.

### Changed — Skill Consolidation

- `CLAUDE.md` Skills paragraph rewritten for the 28-skill baseline; getting-started flows updated.
- `skills/forge-help/SKILL.md` rewritten — ASCII decision tree replaces tier tables; `--json` envelope bumps to `schema_version: "2"`; new Migration table.
- `shared/skill-contract.md` §4 Skill categorization rebased to the consolidated baseline (10 read-only + 18 writes = 28).
- `README.md`, `shared/graph/{schema,schema-versioning}.md`, `shared/graph/enrich-symbols.sh`, `shared/recovery/health-checks/dependency-check.sh`, `skills/forge-init/SKILL.md` — every `/forge-graph-*` and `/forge-config-validate` reference rewritten to the new `<sub>` form.

### Changed — Time-Travel

- `shared/state-schema.md` — `## § Checkpoints` section replaced with CAS DAG layout; deprecated `## checkpoint-{storyId}.json` section retained for reference only.
- `shared/state-transitions.md` — added `REWINDING` pseudo-state rows and a `§ Rewind transitions` section.
- `skills/forge-recover/SKILL.md` — subcommand table, flags, exit-codes block, examples, and dispatch prose extended for rewind + list-checkpoints.
- `CLAUDE.md` — state-schema version bumped from v1.6.0 → v1.9.0 in the key-entry-points table and state overview.

### Changed — Infra

- GitHub Actions workflows migrated to `actions/checkout@v6`.

### Fixed

- Untrusted Data Policy header injected into `fg-301-implementer-critic` (missed in the original injection-hardening sweep).

### Cardinality budget

Span names use only bounded attributes (`gen_ai.agent.name`, `gen_ai.request.model`, `gen_ai.operation.name`, `forge.stage`, `forge.mode`). Unbounded values (`forge.run_id`, `gen_ai.agent.id`, `gen_ai.tool.call.id`) appear as attributes only, never in span names. See `shared/observability.md` for the full table.

## [3.3.0] — 2026-04-20 — Implementer Reflection (Chain-of-Verification)

Fresh-context critic (`fg-301-implementer-critic`) inserted between GREEN and REFACTOR in `fg-300`'s TDD loop catches diffs that pass tests but fail to satisfy test intent (hardcoded returns, over-narrow conditionals, swallowed branches).

### Added

- **`fg-301-implementer-critic`** — Tier-4 fresh-context sub-subagent dispatched between GREEN and REFACTOR. Receives only (task description, test code, implementation diff) — no access to implementer reasoning, PREEMPT items, conventions stack, or scaffolder output.
- **`implementer.reflection.*` config block** — `enabled`, `max_cycles` (default 2), `fresh_context`.
- **Per-task `implementer_reflection_cycles` counter** in `state.json` — parallel to `implementer_fix_cycles`; does NOT feed into convergence counters, `total_retries`, or `total_iterations`.
- **New scoring categories** — `REFLECT-DIVERGENCE`, `REFLECT-HARDCODED-RETURN`, `REFLECT-OVER-NARROW`, `REFLECT-MISSING-BRANCH`. After 2 REVISE verdicts on the same task the critic escalates to `REFLECT-DIVERGENCE` (WARNING) and continues to REFACTOR so the reviewer panel gets a chance.
- **Model routing** — critic uses `fast` tier.
- **Self-consistency voting foundation** — dispatch bridge + state schema bump.
- **Ebbinghaus memory decay foundation** — agent edits + legacy-field removal.
- **Time-travel checkpoints foundation** (Tasks 1-4).
- **Speculative plan branches foundation** (Tasks 1-3).
- **Repo-map PageRank foundation** (Tasks 1-4).
- **New framework modules** — Rails, Swift structured concurrency, and Laravel. `MIN_FRAMEWORKS` raised from 22 to 24 with structural guards.

### Fixed

- `engine.sh` — bypass timeout+lock+ERR-trap silent-exit paths in operator modes (fixes silent failure on hook invocation edge cases).

### Changed

- `.claude-plugin/plugin.json` → 3.3.0.

## [3.2.0] — 2026-04-20 — Prompt Injection Hardening

Four-tier trust model (Silent / Logged / Confirmed / Blocked) wraps every piece of external data consumed by the 48 forge agents inside `<untrusted source="..." ...>` XML envelopes. A mandatory system-level Untrusted Data Policy header is injected into every agent, treating envelope contents as **data, never instructions**. Regex detection layer flags and quarantines likely-injection payloads before reaching any agent.

### Breaking

- **Every agent `.md` now carries the SHA-pinned Untrusted Data Policy header.** Hand-editing the header breaks the SHA pin — use `./tools/apply-untrusted-header.sh` for any header change.
- **MCP tool responses (Linear, Slack, Figma, Playwright, Context7, Neo4j, GitHub), wiki content, explore-cache JSON, cross-project learnings, and documentation-discovery output** are now filtered through `hooks/_py/mcp_response_filter.py` and wrapped in `<untrusted>` envelopes before reaching any agent.

### Added

- **`shared/untrusted-envelope.md`** — canonical XML envelope contract (`<untrusted source="..." trust_tier="..." ...>...</untrusted>`).
- **`shared/prompt-injection-patterns.json`** — curated regex library for four-tier detection.
- **`SEC-INJECTION-*` scoring categories** — findings distinguish Silent / Logged / Confirmed / Blocked severity.
- **`hooks/_py/mcp_response_filter.py`** — every external data source tiered and envelope-wrapped at the hook boundary.
- **`./tools/apply-untrusted-header.sh`** — SHA-pinned header application tool (hand-editing breaks the pin).
- **Skill consolidation foundation** (Tasks 1-3).
- **Documentation architecture foundation** — ADR scaffolding + 11 seed records.
- **Agent layer foundation** — `ui:` frontmatter trim + `trigger:` scaffolding.
- **Flask framework module** (first of four new frameworks).
- **OTel GenAI semconv foundation** (Tasks 1-4).
- **Residual bash audit scripts** ported to Python.

### Changed

- `.claude-plugin/plugin.json` → 3.2.0.

## [3.1.0] — 2026-04-19 — Cross-Platform Python Hooks

All 7 forge hooks, the check engine, and the critical `shared/*.sh` scripts ported to Python 3.10+ stdlib-only. The bash 4+ requirement is dropped; `windows-latest` is now a first-class CI target.

### Breaking

- **Bash 4+ no longer required.** Python 3.10+ is the only hard prerequisite for hook execution. A handful of developer-only simulation harnesses under `shared/` remain in bash (e.g., `shared/convergence-engine-sim.sh`) but are bash-3.2 compatible and do not run in hook paths.
- **`bash`-isms removed** — here-strings (`<<<`), process substitution (`< <(...)`), associative arrays (`declare -A`) that broke Git Bash 3.2 and MSYS/MinGW are gone from all hook-reachable code.

### Added

- **`hooks/_py/` Python package** — 6 hook entry scripts (`pre_tool_use.py`, `post_tool_use.py`, `post_tool_use_skill.py`, `post_tool_use_agent.py`, `stop.py`, `session_start.py`) + check engine (`_py.check_engine`), automation trigger (`_py.check_engine.automation_trigger`), and compact check.
- **`shared/python/`** — `state_init.py`, `guard_parser.py`, `state_transitions.py` (full transition table), `state_migrate.py` (v1.5.0 → v1.6.0 migration).
- **`check_prerequisites.py`** — Python 3.10+ validation for `/forge-init`.
- **`windows-latest` CI matrix** — full `unit | contract | scenario` jobs now run on Windows Git Bash (previously `structural`-only).
- **`shared/platform-support.md`** — cross-platform guidance (macOS / Linux / Windows Git Bash / WSL2 / PowerShell).
- **Pipeline evaluation harness** (`tests/evals/pipeline/`) — CI-only evals with 5 suite definitions (lite/25, convergence/10, cost/5, compression/5, smoke/5), 30 fixture stubs across 5 languages, baseline save/compare with regression detection.

### Changed

- `.claude-plugin/plugin.json` → 3.1.0.

## [3.0.0] — 2026-04-16

### Breaking changes

- **Removed 7 skills** (no aliases). See `DEPRECATIONS.md` for the migration table.
  - `/forge-diagnose`, `/forge-repair-state`, `/forge-reset`, `/forge-resume`, `/forge-rollback` → `/forge-recover <subcommand>`
  - `/forge-caveman`, `/forge-compression-help` → `/forge-compress <subcommand>`
- Skill count: 41 → 35.
- Every SKILL.md description now prefixed with `[read-only]` or `[writes]` badge.
- Every agent frontmatter now requires explicit `ui: { tasks, ask, plan_mode }` block — implicit Tier-4-by-omission no longer accepted.
- `ui: { tier: N }` shortcut removed in `fg-135`, `fg-510`, `fg-515`.
- `fg-210-validator` promoted Tier 4 → Tier 2 (frontmatter + tools only; behavior unchanged in this release).
- 22 agents received a new `color:` assignment to satisfy cluster-scoped uniqueness.

### Added

- `/forge-recover` skill with 5 subcommands.
- `shared/skill-contract.md` — authoritative skill-surface contract.
- `shared/agent-colors.md` — cluster-scoped color map (42 agents).
- `shared/ask-user-question-patterns.md` — canonical UX patterns.
- 14 Tier 1/2 agents now carry concrete `AskUserQuestion` JSON examples.
- `--help` on every skill; `--dry-run` on every mutating skill; `--json` on every read-only skill.
- Standard exit codes 0–4 documented in `shared/skill-contract.md`.
- `/forge-help --json` output mode.
- `shared/state-schema.md`: `recovery_op` field on orchestrator input payload (schema 1.6.0 → 1.7.0).
- `agents/fg-100-orchestrator.md`: §Recovery op dispatch section.
- `tests/contract/skill-contract.bats`: 8 new assertions.
- `tests/contract/ui-frontmatter-consistency.bats`: 5 new assertions.
- `tests/unit/skill-execution/forge-recover-integration.bats`: SKILL.md surface check.

### Changed

- `/forge-compress` rewritten from single-verb → 4-subcommand (`agents|output <mode>|status|help`).
- `/forge-help` augmented: existing 3-tier taxonomy preserved; added `[read-only]`/`[writes]` badges and `--json` output.
- `tests/unit/caveman-modes.bats` renamed and rewritten → `tests/unit/compress-output-modes.bats`.
- 24 `shared/*.md` references swept from old skill names to new.
- `shared/agent-ui.md`: "Omitting ui: means Tier 4" language removed.
- `shared/agent-role-hierarchy.md`: `fg-205` added; `fg-210` promoted.

### Removed

- `tests/structural/ui-frontmatter-consistency.bats` (duplicate of contract/ copy).
- `tests/unit/skill-execution/forge-compression-help.bats` (skill deleted).

### Migration notes

- All removed skills have direct replacements in the Breaking Changes list.
- No config changes required.
- Agents with new colors render differently in kanban — expected cosmetic change only.

## [2.8.0] - 2026-04-16

### Added
- **F29 Run History Store:** SQLite FTS5 database at `.forge/run-history.db` stores every pipeline run with queryable outcomes, learnings, and agent performance. Schema DDL in `shared/run-history/`, written by `fg-700-retrospective`, queried by `/forge-insights`, `/forge-ask`, and the MCP server. Config: `run_history.*` (enabled, retention_days, fts_enabled). Preflight validation rejects invalid retention ranges. Survives `/forge-recover reset`
- **F30 Forge MCP Server:** Python stdio MCP server in `shared/mcp-server/` exposes pipeline intelligence to any MCP-capable AI client (Claude Desktop, other agents). 11 tools covering runs, learnings, playbooks, scoring trends, agent stats, and wiki queries. Auto-provisioned by `/forge-init` into project `.mcp.json`. WAL-mode SQLite reads, `safe_json` decorator on every tool for graceful degradation on corrupt/missing files. Optional (requires Python 3.10+). Config: `mcp_server.*`
- **F31 Self-Improving Playbooks:** Retrospective analyzes run outcomes and proposes playbook refinements (stage reordering, agent swaps, threshold tuning). JSON schema in `shared/playbooks/refinement-proposal.schema.json`. Orchestrator auto-applies high-confidence refinements at PREFLIGHT with `playbook_pre_refine_version` snapshot for rollback. Proposals stored in `.forge/playbook-refinements/`. New skill `/forge-playbook-refine` for interactive review/apply/reject. Analytics tracked in `.forge/playbook-analytics.json`
- Contract tests for run-history schema, MCP server structure and integration, and playbook refinement proposals (including deferred-status coverage)

### Changed
- `fg-100-orchestrator` gained a PREFLIGHT playbook-refinement step with version-snapshot rollback
- `fg-700-retrospective` now writes a run record to the history store and analyzes outcomes for playbook refinement proposals
- `/forge-init` detects Python 3.10+ and provisions MCP server entry in `.mcp.json` when available
- CLAUDE.md adds F29/F30/F31 to the v2.0 features table and lists `/forge-playbook-refine` in the skill selection guide
- `shared/state-schema.md` registers `run-history.db` and `playbook-refinements/` as survivors of `/forge-recover reset`

### Fixed
- MCP server corrupt-file handling: `safe_json` decorator returns structured error responses instead of crashing when `.forge/` JSON is malformed or absent
- MCP server SQLite reads now use WAL mode to avoid locking conflicts with concurrent retrospective writes
- Field name mismatches and `version_history` population resolved in MCP server response shapes
- Retrospective `retention_days` preflight validator now enforces the documented 1-365 range
- Run-history schema test on macOS: strip the entire FTS5 block (macOS-shipped SQLite lacks FTS5) instead of a partial strip that left dangling syntax
- CI: skip-guard FTS5 tests when SQLite lacks the extension; skill-quality 'Use when' clause restored on new skills

### Performance
- CI bats test execution parallelized across CPU cores via xargs-based batching (~2-3x wall-clock reduction on GitHub-hosted runners)

## [2.7.0] - 2026-04-15

### Added
- **Python Extraction:** Embedded Python in `forge-state.sh` extracted into `shared/python/state_init.py`, `guard_parser.py`, and `state_transitions.py` (full transition table). Shell scripts now call out to versioned Python modules for testability
- **State Schema Migration Engine:** `state_migrate.py` performs the v1.5.0 → v1.6.0 migration (circuit-breaker tracking, planning-critic counter, schema-migration history). Integrated into `forge-state.sh`
- **Planning Critic:** New `fg-205-planning-critic` agent reviews plans for feasibility, risk gaps, and scope issues before validation
- **Circuit Breaker Flapping Detection:** Recovery engine now detects and handles circuit breakers that toggle repeatedly; dedup cap removed (unbounded dedup with size-cap safeguards)
- **Epsilon-Aware Score Comparison:** Helpers for floating-point score equality with documented epsilon semantics; simplified unfixable-INFO formula
- **Context-Aware PREEMPT Decay:** PREEMPT items now decay based on context-match signal strength; cross-project learnings shared via `shared/cross-project-learnings.md`
- **Mermaid Architecture Diagrams:** Pipeline, agents, and state-machine diagrams in `docs/architecture/`
- **Structural Tests:** ui-frontmatter consistency, architecture diagram validation, behavioral tests for 10 previously undertested agents
- `shared/preflight-constraints.md` and `shared/framework-gotchas.md` extracted from CLAUDE.md to keep the root doc lean

### Changed
- State schema bumped to v1.6.0 with documented checkpoint persistence lifecycle and size caps on unbounded state fields
- WAL recovery made atomic via double-check locking
- `FORGE_PYTHON` variable replaces hardcoded `python3` across all shell scripts; exported from `platform.sh`
- `detect_os` now returns `wsl` for WSL environments; bash version warning surfaced on session start
- Sleep-based timeout fallback for hooks on systems without `timeout`/`gtimeout`
- Temp dir cascade standardized (`TMPDIR:-${TMP:-${TEMP:-/tmp}}`) across all shell scripts
- `ui:` frontmatter added to 10 skills; caveman description corrected
- Redundant `skill-routing-guide.md` deleted (content absorbed into `/forge-help`)

### Fixed
- CI test failures from the v2.7.0 upgrade resolved across three follow-up commits

## [2.6.1] - 2026-04-15

### Fixed
- Skill descriptions for `forge-automation`, `forge-config-validate`, and `forge-graph-init` now include the required 'Use when' trigger clause, fixing `skill-quality` contract test failure

## [2.6.0] - 2026-04-14

### Added
- **Environment Health Check:** New `shared/check-environment.sh` script probes for optional CLI tools (jq, docker, tree-sitter, gh, sqlite3) and outputs structured JSON via Python. `/forge-init` now displays a categorized dashboard (required/recommended/optional tools + MCP integrations) with platform-specific install suggestions during Phase 1.1
- **Caveman Benchmark:** New `shared/caveman-benchmark.sh` measures estimated token savings across lite/full/ultra modes. `/forge-compress output benchmark [file]` subcommand for on-demand measurement
- **Dynamic Reviewer Scaling:** Quality gate (`fg-400`) now scales reviewer count by change scope: <50 lines dispatches batch 1 only, 50-500 dispatches all batches, >500 emits `APPROACH-SCOPE | INFO` splitting suggestion. Override with `quality_gate.force_full_review: true`
- **Forge-Help 3-Tier Structure:** Reorganized from flat A-G categories into Essential (7 skills) / Power User (12) / Advanced (20) tiers with "Similar Skills" disambiguation table
- **Platform Troubleshooting:** `/forge-tour` now includes platform-specific setup instructions for WSL2, Git Bash, macOS, and Linux
- **Windows Long Path Guard:** Worktree manager (`fg-101`) detects Windows filesystem paths and enables `core.longpaths`, truncates branch slugs over 200 chars
- **Cross-Reference Network:** Added See Also sections to `convergence-engine.md`, `scoring.md`, `agent-philosophy.md` with bidirectional links
- **PREEMPT Auto-Discovery Rules:** Formalized auto-discovered item decay (MEDIUM start, 2x faster decay, archive at decay_score >= 5, promote after 3 successes)
- **Structural Validation Tests:** `skill-descriptions.bats` (5 tests), `doc-cross-references` (5 tests), 3 new portability checks in `platform-portability.bats`
- **Regression Tests:** `deprecated-python-api.bats` (3 tests), `automation-cooldown.bats` (4 tests), `caveman-benchmark.bats` (5 tests), `check-environment.bats` (10 tests)

### Changed
- Caveman auto-activation default changed from `full` to `lite` (safer compression — keeps grammar and articles). Manual `/forge-compress output` invocation still defaults to `full`. Updated `session-start.sh`, `config-schema.json`, skill docs
- 11 skill descriptions rewritten for better trigger accuracy: forge-fix, forge-shape, forge-diagnose, forge-config, forge-config-validate, forge-compress, forge-automation, forge-bootstrap, forge-graph-init, forge-repair-state, forge-rollback
- Module documentation examples updated to use non-deprecated `datetime.now(timezone.utc)`: cassandra.md, pulsar.md, oauth2.md
- Documented PowerShell incompatibility and platform requirements in CLAUDE.md structural gotchas

### Fixed
- **Critical:** Automation cooldown never fired — `automation-trigger.sh` wrote timestamp as `'ts'` but cooldown reader looked for `'timestamp'`. `KeyError` silently swallowed by `except` clause
- Deprecated `datetime.utcnow()` replaced with `datetime.now(timezone.utc)` + `ImportError` fallback in `automation-trigger.sh`, `session-start.sh`, `feedback-capture.sh`
- Deprecated `datetime.utcfromtimestamp()` replaced with `datetime.fromtimestamp(ts, tz=timezone.utc)` + fallback in `session-start.sh`
- Deprecated `datetime.datetime.utcnow()` replaced with `datetime.datetime.now(datetime.timezone.utc)` + `AttributeError` fallback in `forge-event.sh`

## [2.5.0] - 2026-04-14

### Added
- **Cross-Platform Hardening:** `fcntl`→`msvcrt` fallback for Windows Git Bash, full TMPDIR/TMP/TEMP cascade, multi-platform `check-prerequisites.sh`, `shared/platform-support.md`, `platform.windows_mode` config, cross-platform CI matrix (MacOS, Ubuntu, Windows Git Bash)
- **Build System Intelligence:** `build-system-resolver.sh` introspects Maven, Gradle, npm/pnpm/yarn, Go, Cargo, .NET with heuristic fallback. `module-boundary-map.sh` discovers multi-module project boundaries. Module-aware import resolution with confidence tagging (resolved/module-inferred/heuristic). Build graph quality metrics in state.json
- **Compression & Caveman Alignment:** Unified compression eval harness (`benchmarks/compression-eval.sh`), post-compression validation (`shared/compression-validation.py`) with 8 structural checks, caveman statusline badge `[STATUS: CAVEMAN]`, enhanced SessionStart auto-injection with full compression rule blocks, research references (arXiv:2604.00025)
- **Eval & Benchmarking Framework:** `evals/pipeline/` with eval-runner, 5 suite definitions (lite/25, convergence/10, cost/5, compression/5, smoke/5), 30 fixture stubs across 5 languages, baseline save/compare with regression detection, CI workflow for automated eval
- **Observability & Cost Management:** `cost-alerting.sh` with multi-threshold budget alerting (50/75/90/100%), `context-guard.sh` for quality-focused condensation at 30K tokens, E8 orchestrator intercept (advisory before hard ESCALATED), per-stage cost reporting, model routing cost optimization, enhanced forge-insights Category 3
- **AI-Aware Code Quality:** 4 new wildcard categories (AI-LOGIC-*, AI-PERF-*, AI-CONCURRENCY-*, AI-SEC-*) with 26 discrete sub-categories, 15 L1 regex patterns across 15 language files, cross-category dedup rule for AI-*/non-AI-* overlap, SCOUT-AI learning loop, reviewer guidance for fg-410/fg-411/fg-416
- `shared/agent-role-hierarchy.md` — complete dispatch graph and tier definitions for all 41 agents
- `shared/tracking/ticket-format.md` — FG-NNN ticket format documentation
- `shared/hook-design.md` — hook execution model, ordering, and script contract
- `allowed-tools:` frontmatter on all 40 skills

### Changed
- 15 skills renamed to `forge-*` prefix: bootstrap-project→forge-bootstrap, codebase-health→forge-codebase-health, config-validate→forge-config-validate, deep-health→forge-deep-health, deploy→forge-deploy, docs-generate→forge-docs-generate, graph-debug→forge-graph-debug, graph-init→forge-graph-init, graph-query→forge-graph-query, graph-rebuild→forge-graph-rebuild, graph-status→forge-graph-status, migration→forge-migration, repair-state→forge-recover repair (consolidated in 3.0.0), security-audit→forge-security-audit, verify→forge-verify
- All cross-references updated across 90+ files (skills, agents, CLAUDE.md, README.md, CONTRIBUTING.md, shared docs, tests)
- Category registry expanded from 83 to 87 entries (23→27 wildcard prefixes)
- `/forge-deep-health` now documents fg-413 reviewer modes (full/conventions-only/a11y-only/performance-only)

### Deprecated
- `--sprint` and `--parallel` flags on `/forge-run` — use `/forge-sprint` instead

### Fixed
- `fcntl` import in `tracking-ops.sh` now uses try/except with msvcrt fallback (Windows compatibility)
- Incomplete `/tmp` cascade in `platform.sh:484` (`TMPDIR:-/tmp` → `TMPDIR:-${TMP:-${TEMP:-/tmp}}`)
- `BASH_SOURCE[0]` for path resolution in sourceable graph scripts
- Context-guard config parsing fallback when PyYAML unavailable

## [2.4.0] - 2026-04-14

### Added
- SessionStart hook — auto-activates caveman mode, displays forge status and unacknowledged alerts at session start
- `/forge-commit` skill — terse conventional commit message generator (<=50 char subject, why over what)
- `/forge-compress help` skill — quick reference card for all compression features
- Next.js App Router variant (`modules/frameworks/nextjs/variants/app-router.md`)
- Agent eval suite (`tests/evals/`) — 41 canonical input/expected pairs for all 8 review agents with convention-coverage checks
- Compression benchmarks (`benchmarks/`) — input compression measurement via programmatic rules, output compression 3-arm eval harness
- Graph schema versioning (`shared/graph/schema-versioning.md`) with migration infrastructure
- 9 new scenario tests: oscillation, recovery budget exhaustion, safety gate, cross-repo, multi-framework composition, nested errors, mode transitions, feedback loop, preview gating
- 57 hook and skill behavioral tests (L0 syntax, check engine, feedback capture, checkpoint, automation trigger, compact check, skill integration)
- Compression semantic integrity tests (verify compressed files preserve category codes, severities, frontmatter, code blocks)
- Cross-reference audit tests (validate markdown links, orchestrator agent references)
- Module overview length enforcement test (15-line soft cap)
- Deprecation migration examples in DEPRECATIONS.md (before/after for all active deprecations)
- Terse review format with text markers `[CRIT]`/`[WARN]`/`[INFO]`/`[PASS]` in forge-review
- Natural language trigger documentation for caveman mode
- `token_pricing` config section for overridable model pricing
- Log rotation for the hook failure log and `.forge/forge.log`

### Changed
- React TypeScript variant extended with generic components, context typing, strict TypeScript patterns
- Angular TypeScript variant extended with standalone components, signals, built-in control flow, `@defer`
- Vue TypeScript variant extended with typed slots, typed refs, composable patterns
- Django Python variant extended with Python 3.10+ patterns (match statements, async views, Django 5.0+ features)
- Composition engine documents variant selection rules (explicit config > language matching)
- Skill count 38 → 40, hook count 6 → 7
- `MIN_UNIT_TESTS` guard bumped to 93, `MIN_SCENARIO_TESTS` to 40
- Structural check count 51 → 73+
- CLAUDE.md and README.md updated with all new skills, hooks, and test counts

### Fixed
- Race condition in WAL recovery (`forge-state-write.sh`) — mkdir-based lock before concurrent recovery
- WAL truncation race — moved inside write lock scope, cleanup on failure
- Token tracker retry without backoff — exponential backoff with jitter (5 retries)
- Non-atomic compact counter (`forge-compact-check.sh`) — mkdir-based lock
- Datetime format inconsistency — Z suffix added to all timestamp fallback paths
- Model detection substring collision (`forge-token-tracker.sh`) — longest-match-first pattern list
- MacOS `sed` compatibility in `derive_project_id()` — replaced non-greedy `+?` with two-step sed

## [1.16.0] - 2026-04-12

### Changed
- CI test tiers run in parallel via matrix strategy (structural → unit/contract/scenario concurrent)
- `fail-fast: false` ensures all tiers report independently — no hidden failures

### Fixed
- Skip mkdir lock contention test when flock is available (platform-dependent CI failure)

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
- 3 new skills: `/forge-abort`, `/forge-recover resume`, `/forge-profile`
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
