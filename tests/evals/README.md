# Agent Eval Suite

Evaluation infrastructure for forge review agents. CI validates structure, convention coverage, and pattern consistency. Live behavioral evaluation via `--live` flag (future).

## Directory Structure

```
tests/evals/
  framework.bash              # Shared eval harness (validation functions)
  README.md                   # This file
  agents/
    fg-410-code-reviewer/     # 7 input/expected pairs + eval.bats
    fg-411-security-reviewer/ # 7 input/expected pairs + eval.bats
    fg-412-architecture-reviewer/ # 5 pairs + eval.bats
    fg-413-frontend-reviewer/ # 5 pairs + eval.bats
    fg-416-performance-reviewer/ # 5 pairs + eval.bats
    fg-417-dependency-reviewer/ # 4 pairs + eval.bats
    fg-418-docs-consistency-reviewer/ # 4 pairs + eval.bats
    fg-419-infra-deploy-reviewer/ # 4 pairs + eval.bats
```

Each agent directory contains:
- `inputs/NN-name.md` -- Code scenarios for the reviewer to evaluate
- `expected/NN-name.expected` -- Expected finding patterns
- `eval.bats` -- Bats tests that validate structure and convention coverage

Note: fg-414 and fg-415 are reserved/unassigned. Not a gap.

## Running

```bash
./tests/run-all.sh eval        # Run eval suite only
./tests/run-all.sh all         # Run all tiers including evals
```

## What CI Validates

1. **Input files are well-formed** -- Have required sections (`# Eval:`, `## Language:`, `## Code Under Review`, `## Expected Behavior`)
2. **Expected files are well-formed** -- All directives use valid syntax
3. **Input/expected pairs match** -- Every input has a matching expected file and vice versa
4. **Patterns are internally consistent** -- `MIN_FINDINGS <= MAX_FINDINGS`
5. **Convention coverage** -- For each `HAS_CATEGORY:` directive, the category is referenced in the agent's conventions, `category-registry.json`, or module files

## Input File Format

```markdown
# Eval: {descriptive name}
## Language: {language}
## Context
{Brief description of the scenario}

## Code Under Review

\`\`\`{language}
// file: {project-relative path}
{10-30 lines of focused code exhibiting the pattern}
\`\`\`

## Expected Behavior
{What the reviewer should find, or "No findings expected"}
```

Supported languages: kotlin, java, typescript, python, go, rust, swift, c, csharp, ruby, php, dart, elixir, scala, cpp. Also accepted for non-code files: json, yaml, markdown, dockerfile.

## Expected File Format

```
# Comment lines start with #
PATTERN: file:line | CATEGORY | SEVERITY | *glob*match* | *
NOT: file:line | CATEGORY | *should-not-appear*
MIN_FINDINGS: 1
MAX_FINDINGS: 3
HAS_CATEGORY: SEC-INJECTION
NOT_CATEGORY: SCOUT-CLEANUP
VERDICT: PASS|CONCERNS|FAIL
```

Directives:
- `PATTERN:` -- Glob pattern matching the pipe-delimited finding format. Must contain at least one `|`.
- `NOT:` -- Pattern that should NOT appear in findings.
- `MIN_FINDINGS:` -- Minimum expected finding count (non-negative integer).
- `MAX_FINDINGS:` -- Maximum expected finding count (non-negative integer).
- `HAS_CATEGORY:` -- Category code that must appear (format: `[A-Z]+-[A-Z0-9_-]+`).
- `NOT_CATEGORY:` -- Category code that must NOT appear.
- `VERDICT:` -- Expected verdict. Pipe-separated alternatives allowed (e.g., `PASS|CONCERNS`).

Note: `SCORE_MIN` and `SCORE_MAX` are intentionally omitted. Score verification requires live mode only.

## Adding a New Eval

1. Create `inputs/NN-descriptive-name.md` following the input format above
2. Create `expected/NN-descriptive-name.expected` with 2-5 pattern directives
3. Ensure the `HAS_CATEGORY` codes exist in `shared/checks/category-registry.json` or the agent's conventions
4. Run `./tests/run-all.sh eval` to verify

## Live Mode (Future)

The `--live` flag will invoke the Claude API with the agent's system prompt and the input scenario, then validate the output against the expected patterns. This is manual-only (not CI) due to API cost. Implementation is a placeholder for future development.
