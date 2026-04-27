#!/usr/bin/env bats
# Structural test: verify markdown cross-references point to existing files
#
# This test scans shared/, agents/, and skills/ for *.md files referenced from
# other markdown and verifies the target exists in the plugin repo.
#
# A `.md` reference does NOT need to resolve to a plugin file when it points to
# a runtime artefact — files that the consuming project, the pipeline at
# runtime, or the wiki/learnings/kanban subsystems generate. Those are
# allow-listed via `is_runtime_artifact()` below; see the function for the
# rationale per entry.

load '../helpers/test-helpers'

# is_runtime_artifact <ref>
#
# Returns 0 (allow-listed, skip) when the reference is intentionally absent
# from the plugin repo, 1 otherwise.
#
# Rationale per entry:
#
# - forge-config.md / forge.local.md / forge-log.md: per-project runtime config
#   and log files generated under .claude/ in the consuming project. Plugin
#   docs reference them by basename when describing user workflow.
#
# - .forge/** and .claude/**: all paths under these directories are runtime
#   state (worktrees, caches, kanban board, baseline reports, shape plans,
#   spec registry, learnings index) created by the pipeline or by the consumer
#   project. They never live in the plugin repo.
#
# - abort-report.md / baseline-report.md: pipeline-generated reports written
#   to .forge/ at runtime.
#
# - stage_*.md: aspirational/templated PREFLIGHT stage docs referenced in
#   examples; they describe a per-project pattern, not a plugin file.
#
# - Wiki-generated docs (api-surface.md, data-model.md, conventions-summary.md,
#   dependency-graph.md, index.md, docs/index.md): produced by fg-135-wiki-
#   generator and fg-350-docs-generator into the consumer project.
#
# - Conventional project-doc names (ARCHITECTURE.md, CHANGES.md, HISTORY.md,
#   RELEASES.md, CONSTRAINTS.md, design.md, technical.md): consumer project
#   files that fg-130-docs-discoverer scans for.
#
# - Kanban tickets (FG-*.md, board.md): files under .forge/tracking/ — see the
#   tracking-schema docs which use them as illustrative examples.
#
# - Cross-project learnings (general.md, anything under forge-learnings/):
#   live in the user's home/.claude/forge-learnings/ directory, never in the
#   plugin.
#
# - cand-*.md: speculative plan candidates persisted under
#   .forge/plans/candidates/ at runtime.
#
# - frontend.md / testing.md (under shared/learnings/ context): referenced as
#   illustrative learnings categories inside JSON code blocks in fg-710 and
#   tracking docs. Not real targets.
#
# - YYYY-MM-DD-*.md and *-{N}.md (where N is a digit): dated learnings/report
#   filename templates demonstrated in docs.
is_runtime_artifact() {
  local ref="$1"
  local base
  base="${ref##*/}"  # bash-native basename, avoids `basename -*` parser issue

  # Skip refs whose basename starts with '-' or '.' (template fragments,
  # numeric suffix templates like -2.md, leading-dot files like .original.md
  # used in compaction examples).
  case "$base" in
    -*|.*) return 0 ;;
  esac

  # Per-project runtime config and log
  case "$base" in
    forge-config.md|forge.local.md|forge-log.md) return 0 ;;
  esac

  # Pipeline-generated reports
  case "$base" in
    abort-report.md|baseline-report.md) return 0 ;;
  esac

  # Aspirational / templated stage docs
  case "$base" in
    stage_*.md) return 0 ;;
  esac

  # Wiki-generated docs (fg-135) and generated docs index (fg-350)
  case "$base" in
    api-surface.md|data-model.md|conventions-summary.md|dependency-graph.md|index.md) return 0 ;;
  esac

  # Conventional consumer-project doc names scanned by fg-130
  case "$base" in
    ARCHITECTURE.md|CHANGES.md|HISTORY.md|RELEASES.md|CONSTRAINTS.md) return 0 ;;
    design.md|technical.md) return 0 ;;
  esac

  # Kanban tickets and board (under .forge/tracking/ at runtime)
  case "$base" in
    FG-*.md|board.md) return 0 ;;
  esac

  # Cross-project learnings (live in ~/.claude/forge-learnings/, not the plugin)
  case "$base" in
    general.md) return 0 ;;
  esac

  # Speculative plan candidates (.forge/plans/candidates/)
  case "$base" in
    cand-*.md) return 0 ;;
  esac

  # Illustrative learnings categories used in JSON examples
  case "$base" in
    frontend.md|testing.md) return 0 ;;
  esac

  # Dated filename templates: literal YYYY-MM-DD placeholder or real digits.
  case "$base" in
    YYYY-MM-DD-*.md) return 0 ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) return 0 ;;
  esac

  # Path-qualified runtime locations
  case "$ref" in
    .forge/*|*/.forge/*) return 0 ;;
    .claude/*|*/.claude/*) return 0 ;;
    */forge-learnings/*) return 0 ;;
  esac

  # Generated docs index referenced as docs/index.md
  case "$ref" in
    docs/index.md) return 0 ;;
  esac

  return 1
}

# is_non_skill_slashpath <path>
#
# Returns 0 when /<word> is NOT a skill reference. The skills test sees
# backtick-quoted slash paths like `/health`, `/metrics`, `/compact` and
# treats them as skill references. Some of those are HTTP endpoint paths
# (in observability/infra docs) or Claude Code built-in slash commands
# (`/compact`). Allow-list those so the test only flags genuine /forge-*
# style skill references that resolve to skills/ directories.
is_non_skill_slashpath() {
  case "$1" in
    # Claude Code built-in slash commands
    compact|clear|help|model|config|cost|memory) return 0 ;;
    # HTTP endpoint paths used in observability / k8s / infra docs
    health|healthz|livez|readyz|metrics|ready|liveness|readiness) return 0 ;;
  esac
  return 1
}

@test "all markdown cross-references point to existing files" {
  local violations=0

  while IFS= read -r -d '' md; do
    # Extract path-qualified .md references (per REVISIONS SPEC-09 #3)
    local refs
    refs=$(grep -oE '[a-zA-Z0-9_./-]+\.md' "$md" 2>/dev/null | sort -u || true)

    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      # Skip if inside a code block (heuristic: skip if ref contains ://)
      [[ "$ref" == *"://"* ]] && continue
      # Skip allow-listed runtime artefacts (see is_runtime_artifact comments)
      if is_runtime_artifact "$ref"; then continue; fi
      # Search for the referenced file. Use bash-native basename to avoid
      # `basename -2.md` parser errors on ref-template fragments.
      local base="${ref##*/}"
      local found
      found=$(find "$PLUGIN_ROOT" -name "$base" -not -path '*/.git/*' 2>/dev/null | head -1)
      if [[ -z "$found" ]]; then
        echo "BROKEN REF: $md references $ref but file not found"
        violations=$((violations + 1))
      fi
    done <<< "$refs"
  done < <(find "$PLUGIN_ROOT/shared" "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/skills" -name "*.md" -print0 2>/dev/null)

  [[ "$violations" -eq 0 ]]
}

@test "all agent references in orchestrator point to existing agents" {
  local violations=0
  local orch="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
  [[ -f "$orch" ]] || skip "orchestrator not found"

  local agent_refs
  agent_refs=$(grep -oE 'fg-[0-9]+-[a-z-]+' "$orch" | sort -u)

  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    if [[ ! -f "$PLUGIN_ROOT/agents/${ref}.md" ]]; then
      echo "BROKEN: orchestrator references $ref but agents/${ref}.md not found"
      violations=$((violations + 1))
    fi
  done <<< "$agent_refs"

  [[ "$violations" -eq 0 ]]
}

@test "all skill references in agents point to existing skills" {
  local violations=0
  local skills_dir="$PLUGIN_ROOT/skills"

  while IFS= read -r -d '' agent; do
    # Extract /skill-name references (backtick-escaped, lowercase with hyphens)
    local refs
    refs=$(grep -oE '`/[a-z][-a-z]+`' "$agent" 2>/dev/null | sed 's/`//g; s|^/||' | sort -u || true)

    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      # Allow-list non-skill slash paths (HTTP endpoints, Claude built-ins).
      # See is_non_skill_slashpath for the rationale.
      if is_non_skill_slashpath "$ref"; then continue; fi
      if [[ ! -d "$skills_dir/$ref" ]]; then
        echo "BROKEN: $(basename "$agent") references /$ref but skills/$ref/ not found"
        violations=$((violations + 1))
      fi
    done <<< "$refs"
  done < <(find "$PLUGIN_ROOT/agents" -name "*.md" -print0 2>/dev/null)

  [[ "$violations" -eq 0 ]]
}

@test "cross-references: convergence-engine.md has See Also section" {
  grep -q "## See Also" "$PLUGIN_ROOT/shared/convergence-engine.md"
}

@test "cross-references: scoring.md has See Also section" {
  grep -q "## See Also" "$PLUGIN_ROOT/shared/scoring.md"
}

@test "cross-references: agent-philosophy.md has See Also section" {
  grep -q "## See Also" "$PLUGIN_ROOT/shared/agent-philosophy.md"
}

@test "cross-references: convergence-engine.md references stage-contract.md" {
  grep -q "stage-contract.md" "$PLUGIN_ROOT/shared/convergence-engine.md"
}

@test "cross-references: scoring.md references convergence-engine.md" {
  grep -q "convergence-engine.md" "$PLUGIN_ROOT/shared/scoring.md"
}
