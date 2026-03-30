---
name: tool-diagnosis
description: Diagnoses and recovers from tool-level failures — OOM kills, missing binaries, configuration errors, and permission issues.
---

# Tool Diagnosis Strategy

Handles failures where a tool or binary crashed, is missing, or is misconfigured. Classifies the root cause and applies targeted remediation.

---

## 1. Classification by Exit Code

### Exit 137 — OOM Kill (SIGKILL)

The process was killed by the OS or container runtime due to memory exhaustion.

**Remediation steps:**

1. **Reduce scope:** If the action was a full build (`./gradlew build`), try building only the affected module (`./gradlew :module:build`).
2. **Increase heap:** If a JVM process, add/increase `-Xmx` flag. Start with halving current value to find a working baseline, then increase:
   - Default attempt: `-Xmx2g` (if current is higher or unset)
   - If still OOM: `-Xmx1g` with `--no-daemon`
3. **Kill competing processes:** Check for orphan build daemons (`pkill -f gradle` daemon, `pkill -f node` dev servers) that consume memory.
4. **Retry** with reduced configuration.

If all remediation fails: return `ESCALATE` with message recommending the user increase available memory or close other applications.

#### Test-Specific OOM Recovery

When OOM occurs during test execution (Phase B of VERIFY), apply different strategies than build OOM:

1. **Reduce test parallelism:** Lower `--workers` / `--forks` count (default: halve current value)
2. **Run tests in batches:** Split test suite into groups, execute sequentially
3. **Exclude memory-intensive tests:** Identify and defer integration/E2E tests to a separate run
4. **Do NOT reduce JVM/Node heap:** Test processes need memory for assertions and fixtures

Recovery sequence: reduce parallelism → batch execution → exclude heavy tests → escalate

### Exit 139 — Segmentation Fault (SIGSEGV)

A tool crashed due to a memory access violation.

**Remediation steps:**

1. **Identify the tool:** Parse stderr for the crashing binary name.
2. **Check version:** Run `<tool> --version` and compare against known-good versions.
3. **Clear caches:** Remove tool-specific caches (`.gradle/caches/`, `node_modules/.cache/`, `.kotlin/`).
4. **Retry** once after cache clear.

If retry fails: return `ESCALATE` — segfaults are typically not recoverable without tool updates.

### Exit 127 — Command Not Found

The binary is not installed or not on PATH.

**Remediation steps:**

1. **Identify the missing command** from stderr.
2. **Check common locations:** `/usr/local/bin/`, `/opt/homebrew/bin/`, `./node_modules/.bin/`, `./gradlew`.
3. **Suggest installation:**
   - `gradle/gradlew` → Check if `gradlew` wrapper exists in project root. If yes, it may not be executable (`chmod +x gradlew`).
   - `node/npm/pnpm` → Suggest `brew install node` or `nvm use`.
   - `docker` → Suggest installing Docker Desktop.
   - `gh` → Suggest `brew install gh`.
   - Other → Report the missing command name.
4. **Do NOT auto-install** tools. Return `ESCALATE` with the install suggestion.

### Exit 126 — Permission Denied

The binary exists but is not executable.

**Remediation steps:**

1. **Identify the file** from stderr.
2. **Fix permissions:** `chmod +x <file>`.
3. **Retry** the original action.

---

## 2. Configuration Errors

When stderr indicates a configuration problem (invalid YAML, malformed JSON, missing required field):

1. **Identify the config file** from the error message.
2. **Read the file** and validate syntax:
   - JSON: attempt parse, report location of syntax error.
   - YAML: check for tab/space mixing, unclosed quotes, bad indentation.
3. **If the file is a pipeline config** (`.pipeline/` or `.claude/`): attempt to regenerate from template.
4. **If the file is a project config** (build.gradle, package.json, etc.): return `ESCALATE` — do not auto-edit project configuration.

---

## 3. Compilation Errors — Routing Guard

**This is NOT a tool failure.** If the exit code is non-zero and stderr contains patterns like:

- `error:` followed by a filename with line number (e.g., `src/Main.kt:42: error:`)
- `FAILED` with `compilation` or `compile` in context
- `SyntaxError` with a source file reference
- `error TS` followed by a number (TypeScript compiler errors)

Then the tool ran correctly — it found code errors. **Do not apply tool diagnosis.** Return to the recovery engine with instruction to route this through the orchestrator's `verify_fix_count` loop instead.

---

## 4. Output

Return to recovery engine:

```json
{
  "result": "RECOVERED | ESCALATE",
  "details": "Root cause and remediation applied",
  "root_cause": "OOM | SEGFAULT | MISSING_BINARY | PERMISSION | CONFIG_ERROR",
  "remediation": "Description of what was done",
  "install_suggestion": "Optional: command to install missing tool"
}
```
