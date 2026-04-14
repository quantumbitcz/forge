---
name: forge-compress
description: "Use when you want to reduce agent system prompt token cost by compressing verbose prose in .md files. Applies caveman-style terse rewriting while preserving all technical rules, code blocks, and structural elements."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent']
---

# /forge-compress -- Agent Prompt Compression

Reduces token cost of agent `.md` files by 30-50% through aggressive prose compression while preserving all technical rules, code blocks, tables, and frontmatter.

## Prerequisites

1. **Forge initialized:** `.claude/forge.local.md` exists. If not: "Run /forge-init first." STOP.
2. **Target files exist:** `ls agents/*.md` returns at least one file.

## Instructions

### 1. List and classify targets

```bash
ls agents/*.md | sort
```

Classify each file:
- **Already compressed** (previously handled) -- skip
- **Target** -- compress

If user specifies a subset, use that. Otherwise, compress all unhandled files.

### 2. Read each target file

Read the full file. Identify:
- **Frontmatter** (YAML between `---` markers) -- NEVER modify
- **Code blocks** (fenced with ``` or ~~~) -- NEVER modify
- **Tables** (pipe-delimited rows) -- NEVER modify
- **Technical rules** (specific values, thresholds, commands, category codes, severity levels) -- preserve exactly
- **Prose sections** -- compress targets

### 3. Apply compression rules

For each prose section:

**Drop:**
- Articles: "a", "an", "the" (unless part of a proper noun or code reference)
- Filler phrases: "in order to", "it is important to note that", "make sure to", "please ensure"
- Hedging: "should be", "it would be", "you might want to"
- Transition phrases: "however", "furthermore", "in addition", "as a result"
- Pleasantries: "You are the...", "Your job is to..."
- Redundant explanations after a clear rule statement
- Repeated context already stated in the file

**Preserve:**
- Technical terms exactly as written
- All code references, paths, commands, config keys
- Category codes (e.g., `QUAL-ERR-*`, `SEC-AUTH`, `ARCH-HEX`)
- Severity levels (CRITICAL, WARNING, INFO)
- Threshold values and numeric constraints
- Tool names, agent IDs, file paths
- Section structure (headings, numbered lists)

**Pattern:** `[subject] [action] [reason].` -- terse, declarative sentences.

**Examples:**
- Before: "You are the build verifier agent. Your job is to verify that the codebase builds and lints cleanly."
- After: "Verifies build + lint pass."

- Before: "If the conventions file is missing or unreadable, skip convention-specific checks across all perspectives and proceed with universal checks only."
- After: "Conventions missing -> universal checks only."

- Before: "Before emitting any finding, ask yourself: Can you point to the exact line?"
- After: "Before emitting: exact line?"

### 3a. Validate compression output

After compressing each file, run the validation script:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/shared/compression-validation.py" \
    "{filename}.original.md" "{filename}"
```

If validation fails (exit code 1):
1. Read the JSON output to identify which check failed
2. Send a targeted fix prompt addressing only the failed check:
   - Code block mutation: "Restore the exact code block content from the original"
   - Heading removed: "Restore the missing heading: {heading text}"
   - URL missing: "Restore the URL: {url}"
   - Frontmatter changed: "Restore the original frontmatter block"
   - Table changed: "Restore the original table at line {N}"
3. Re-validate after the fix
4. If still fails after 2 retries, restore original from `.original.md` backup
5. Report the file as "compression failed" in the summary

If validation warns (exit code 2):
- Log the warning (bullet drift or file path drift) but continue
- Include warning details in the compression report

If validation passes (exit code 0):
- Continue to next file

### 4. Final validation summary (per-file)

The automated validation (step 3a) handles structural checks. This step summarizes results:
- [ ] All files passed validation or were restored from backup
- [ ] No new content added (compression only removes, never adds)

### 5. Report savings

After compression, report:

```
## Compression Report

| File | Before (lines) | After (lines) | Reduction |
|------|----------------|---------------|-----------|
| fg-XXX-name.md | NNN | NNN | NN% |
| ... | ... | ... | ... |
| **Total** | **NNNN** | **NNNN** | **NN%** |
```

Target: 30-50% line reduction across all files.

## Error Handling

| Condition | Action |
|-----------|--------|
| File has no prose to compress (all code/tables) | Skip with note: "No compressible prose" |
| Compression would alter a technical rule | Revert that specific edit, keep original text |
| Frontmatter parse error after compression | File was corrupted -- revert entire file |
| Line reduction < 20% for a file | Acceptable for highly technical files with minimal prose |

## Extended Options

Parse flags from `$ARGUMENTS`:

| Flag | Default | Behavior |
|------|---------|----------|
| `--level <1\|2\|3>` | auto (per file type, see `input-compression.md`) | Compression intensity: 1=conservative, 2=aggressive, 3=ultra |
| `--scope <agents\|modules\|shared\|config\|all>` | `agents` | Target file group |
| `--dry-run` | false | Report estimated savings without modifying files |
| `--restore` | false | Restore all `.original.md` backups |

### Scope Targets

| Scope | Files Targeted |
|-------|---------------|
| `agents` | `agents/*.md` |
| `modules` | `modules/frameworks/*/conventions.md`, `modules/frameworks/*/testing/*.md` |
| `shared` | `shared/*.md` (excluding `shared/checks/`) |
| `config` | Convention templates (`local-template.md`, `forge-config-template.md`) |
| `all` | All of the above |

### --dry-run Mode

For each target file:
1. Read file, estimate token count (word count × 1.3)
2. Estimate reduction based on level (1=20%, 2=45%, 3=65%)
3. Report per-file: `{filename}: ~{current} tokens → ~{estimated} tokens ({reduction}% reduction)`
4. Report total savings
5. Do NOT modify any files

### --restore Mode

1. Find all `*.original.md` files in target scope directories
2. For each: rename `.original.md` back to `.md` (overwrite compressed version)
3. Report count of restored files
4. If no `.original.md` files found: "No backups to restore."

### Backup Rule

Before compressing any file, copy original to `{filename}.original.md`. Never compress a `.original.md` file (skip silently). Never compress files in `tests/`, `.git/`, or `node_modules/`.

## See Also

- `/forge-review` -- review changed files for quality
- `/forge-verify` -- build + lint + test check
- Compression rules and intensity levels -- see `input-compression.md` in `shared`
- See `shared/compression-validation.py` for post-compression structural validation
