# Review — Phase 05 Skill Consolidation Design Spec

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-05-skill-consolidation-design.md`
**Date:** 2026-04-19
**Reviewer role:** Senior code reviewer (design spec pass)

---

## Verdict

**APPROVE WITH MINOR REVISIONS.**

The spec is thorough, internally consistent, and directly answers every one of the 10 review criteria with specific, actionable prose. Arithmetic checks out (35 − 2 − 4 − 1 = 28). Subcommand dispatch pattern is formally specified and factored into a shared contract doc. The hard-break policy is respected — no stubs, no aliases, old skill files are enumerated for deletion. CI-only testing is honored. The `/forge-help` decision tree is drawn in full and depth-checked. The three consolidations have before/after mappings, preserved config keys, preserved state-file paths, and clear file-deletion lists.

Three blocking-tier-low issues remain (below), none of which invalidate the design; they should be resolved before the implementer is dispatched.

---

## Criteria checklist

| # | Criterion | Met? | Evidence in spec |
|---|---|---|---|
| 1 | All 12 sections present | Yes | §1 Goal → §12 References, plus Arithmetic check |
| 2 | No placeholders | Yes | No `TODO`, `TBD`, `xxx`, or `<placeholder>` strings |
| 3 | Subcommand dispatch pattern specified | Yes | §4.1 dispatch algorithm + §4.2 `parse_args` helper |
| 4 | All 3 consolidations detailed with before/after | Yes | §5.1, §5.2, §5.3 |
| 5 | Old skill files deletion listed exhaustively | Yes | §5.1, §5.2, §5.3, §9 PR contents item 4 |
| 6 | CLAUDE.md skill table updates specified | Yes | §5.6 (line 274 header + Skill Selection Guide table) |
| 7 | /forge-help decision tree shown | Yes | §4.3 full ASCII tree with depth check |
| 8 | Arithmetic verified | Yes | §3 summary + §11 + dedicated Arithmetic check block |
| 9 | CI tests for new subcommands specified | Yes | §8 items 1–7 |
| 10 | No aliases/stubs | Yes | §3 Out, §7, §4.4 Alt B rejected |

All 10 criteria met.

---

## What was done well

1. **Progressive-disclosure argument with citation.** §2 grounds the consolidation in Anthropic's published skill best-practices, not just internal preference.
2. **Default-subcommand table with rationale per skill.** §4.1 explicitly states *why* `/forge-graph` has no default (safety against accidental rebuild) while `/forge-review` and `/forge-verify` do (muscle memory). This is the kind of reasoning reviewers can push back on, which is healthier than silent choices.
3. **Hard-break honored exactly.** §7 explicitly reaffirms "no stubs, no alias redirects, no tombstone SKILL.md entries," and redirects the migration affordance to a single table in `/forge-help`. This matches the user's requirement precisely and stops ambiguity.
4. **Preserved behavior, moved verbatim.** §5.1 / §5.2 / §5.3 repeatedly use the word "verbatim" for hard content (agent dispatch, Neo4j state machine, YAML validation). This signals low-risk content migration — the behavioral surface does not change, only the top-level skill surface.
5. **Cross-reference grep as a CI test (§8 item 6).** Making this structural rather than manual means dangling references cannot sneak back in.
6. **Arithmetic spelled out twice** — §3, §11, and the closing block — which is exactly what the user asked for.
7. **Alternatives rejected with reasons (§4.4).** Status-quo and alias-stub alternatives are named and refuted; the chosen option is not presented in isolation.

---

## Issues

### Important (should fix before implementation)

**I1 — `/forge-verify` frontmatter missing `Write/Edit/Bash` despite `--config` path invoking `validate-config.sh`.**

§5.3 declares `allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']` (read-only). The `config` subcommand body "delegates to `shared/validate-config.sh`" — that is an executable script, so `Bash` is correct and the tool list is fine. However, the current `/forge-config-validate` skill description is `[read-only]` and the new unified description is also `[read-only]`. Confirm that `validate-config.sh` itself does not write anywhere (it should only read + report). If it does write (e.g. cached validation results to `.forge/`), the unified skill's `[read-only]` label becomes a lie. **Action:** either verify the script is read-only and keep the label, or adjust the description to `[read-only for --build and --config report; no writes under any flag]` explicitly.

**I2 — `--scope=all --fix` commit-gate safety is flagged as an Open Question in §10 but not decided.**

§10 asks whether the unified `/forge-review --scope=all --fix` should require a confirmation prompt. The spec's *proposed answer* is "yes, add a single `AskUserQuestion` gate before the first commit, unless `--yes` is passed or `autonomous: true` is set." This is sound, but §5.1 does not specify this gate in the behavioral description of the `all --fix` mode, and §11 Success Criteria does not include it. Because this phase removes the natural "I typed the destructive skill name" confirmation that existed when `/forge-deep-health` was its own skill, the gate is a real safety regression if it's left open. **Action:** promote the proposed answer from Open Question to a concrete requirement in §5.1, §8 testing, and §11 success criteria — or explicitly accept the regression with a one-line justification.

### Suggestions (nice to have, not blocking)

**S1 — `/forge-help --json` schema-version bump is implied, not stated.**

§7 notes the `--json` envelope "bumps its implicit schema." Consumers (MCP server F30, `/forge-insights`) need a way to detect the new shape. Consider adding an explicit `schema_version: "2"` (or similar) field to the JSON envelope in the same PR. This is a one-line change in the generator and saves downstream consumers from sniffing for the presence of `subcommands` to detect the new shape.

**S2 — Rename `skills/forge-graph-init/` is a `git mv`; call that out for reviewers.**

§9 item 3 says "Renamed `skills/forge-graph-init/` → `skills/forge-graph/` with merged SKILL.md." In practice this is a `git mv` + content overwrite; make sure the PR actually uses `git mv` so the review diff shows a rename (preserves history) rather than a delete + add.

**S3 — Structural test for dispatch-section idempotency.**

§8 item 1 asserts each consolidated skill has "a `## Subcommand dispatch` section." Consider asserting exactly one such section per file — a duplicated dispatch block (from a future copy-paste mistake) would still pass the current contains-check but would be a real bug. One-line change: `grep -c` == 1.

---

## Top 3 issues (per review instructions)

1. **I2** — `--scope=all --fix` safety gate is only proposed in Open Questions; promote to a concrete §5.1 requirement and add a §11 success-criterion line, otherwise this phase introduces a safety regression relative to the old standalone `/forge-deep-health`.
2. **I1** — Verify `shared/validate-config.sh` is actually read-only before the unified `/forge-verify` keeps the `[read-only]` label; otherwise adjust the description.
3. **S1** — Add an explicit `schema_version` field to `/forge-help --json` so the MCP server (F30) and `/forge-insights` can detect the new cluster shape without schema-sniffing.

---

## Recommendation

**APPROVE once I1 and I2 are resolved** (both are small spec edits, not design changes). S1–S3 are post-merge follow-ups and not gating.

## Final response (≤80 words)

**APPROVE WITH MINOR REVISIONS.** All 10 criteria met; arithmetic checks (35−2−4−1=28); no placeholders, no stubs, CI-only testing honored. Top 3 issues: (1) `--scope=all --fix` safety-confirm gate is left as an Open Question — promote to a §5.1 requirement or accept the regression explicitly; (2) verify `validate-config.sh` is truly read-only before keeping `/forge-verify --config`'s `[read-only]` label; (3) add explicit `schema_version` to `/forge-help --json` for downstream consumers (MCP server F30, `/forge-insights`).
