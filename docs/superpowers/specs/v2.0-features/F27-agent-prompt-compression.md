# F27: Agent System Prompt Compression (caveman-compress for .md files)

## Status
DRAFT — 2026-04-13

## Problem Statement

Agent `.md` files ARE the system prompt — every line is sent with every API call within that agent's conversation. The orchestrator alone is 2,365 lines. Across a full pipeline run with 20+ agent dispatches, system prompt tokens are a significant cost driver.

The caveman-compress tool (github.com/JuliusBrussee/caveman) demonstrates that LLM-powered rewriting can compress natural language instructions by ~46% while preserving all technical rules, code blocks, and structural elements.

**No backward compatibility needed** — compressed files replace originals directly.

## Proposed Solution

A `/forge-compress` skill that applies LLM-powered rewriting to agent `.md` files, stripping verbose prose while preserving all technical rules, finding formats, forbidden actions, code blocks, and YAML frontmatter.

## Detailed Design

### Architecture

1. **Classify**: Detect file type (agent .md, shared contract, convention doc)
2. **Compress**: Use LLM (fast tier) to rewrite prose sections into terse form
3. **Validate**: Verify structural integrity (section count, code blocks, frontmatter, key terms)
4. **Apply**: Replace original file directly (no backup — git is the backup)

### Compression Rules

Preserve exactly:
- YAML frontmatter (name, description, tools, ui, model)
- Code blocks (fenced and indented)
- Pipe-delimited finding format examples
- File paths, line numbers, category codes
- Forbidden Actions lists
- Configuration tables
- JSON/YAML examples

Compress:
- Explanatory prose between rules → terse form
- Rationale paragraphs → single-line summaries
- Repetitive instructions → deduplicated
- "When X happens, you should Y because Z" → "X → Y."

### Validation

After compression, verify:
- Section count matches original (## headings preserved)
- All code blocks from original appear in compressed version (exact match)
- YAML frontmatter unchanged
- Key terms preserved (finding categories, agent IDs, tool names)
- File is still valid markdown
- Compressed file is at least 30% smaller (otherwise compression failed)

### Skill Definition

```yaml
name: forge-compress
description: "Use when you want to reduce agent system prompt token cost by compressing verbose prose in agent .md files. Rewrites instructions into terse form while preserving all technical rules."
```

### Configuration

```yaml
agent_compression:
  enabled: false                    # Opt-in via /forge-compress
  target_savings_pct: 30            # Minimum compression ratio
  preserve_patterns:
    - "^---$"                       # YAML frontmatter boundaries
    - "```"                         # Code block boundaries
    - "\\|.*\\|.*\\|"              # Table rows
```

### Scope

Files eligible for compression:
- `agents/*.md` (42 files)
- `shared/*.md` (selected contracts — NOT schemas, NOT scripts)
- `modules/frameworks/*/conventions.md` (21 files)

Files NOT eligible:
- JSON files, shell scripts, Python scripts
- Test files
- Schema files
- CLAUDE.md (compressed separately, human-readable version needed)

## Acceptance Criteria

1. `/forge-compress` skill exists with proper frontmatter
2. Compression preserves all code blocks, frontmatter, tables, and finding formats
3. Section count matches original after compression
4. Minimum 30% size reduction achieved
5. Compressed agents pass all existing structural tests (validate-plugin.sh)
6. Git diff shows the changes for review before commit

## Dependencies

- Depends on: F26 (output compression — establishes the terse writing style)
- Depends on: F03 (model routing — uses fast tier for compression LLM calls)
