#!/usr/bin/env bats
# Contract tests: shared/learnings/memory-discovery.md — validates the autonomous
# memory discovery contract document.

load '../helpers/test-helpers'

DOC="$PLUGIN_ROOT/shared/learnings/memory-discovery.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "memory-discovery: document exists" {
  [[ -f "$DOC" ]]
}

# ---------------------------------------------------------------------------
# 2. Required section: Discovery Categories
# ---------------------------------------------------------------------------
@test "memory-discovery: Discovery Categories section exists" {
  grep -qi "Discovery Categories" "$DOC" \
    || fail "Discovery Categories section not found"
}

# ---------------------------------------------------------------------------
# 3. Required section: Discovery Flow
# ---------------------------------------------------------------------------
@test "memory-discovery: Discovery Flow section exists" {
  grep -qi "Discovery Flow" "$DOC" \
    || fail "Discovery Flow section not found"
}

# ---------------------------------------------------------------------------
# 4. Required section: Configuration
# ---------------------------------------------------------------------------
@test "memory-discovery: Configuration section exists" {
  grep -qi "Configuration" "$DOC" \
    || fail "Configuration section not found"
}

# ---------------------------------------------------------------------------
# 5. Required section: Constraints
# ---------------------------------------------------------------------------
@test "memory-discovery: Constraints section exists" {
  grep -qi "Constraints" "$DOC" \
    || fail "Constraints section not found"
}

# ---------------------------------------------------------------------------
# 6. All six discovery categories documented
# ---------------------------------------------------------------------------
@test "memory-discovery: all six discovery categories documented" {
  for category in "Naming patterns" "Architecture decisions" "Test patterns" \
                  "Configuration quirks" "Dependency patterns" "Error patterns"; do
    grep -qi "$category" "$DOC" \
      || fail "Discovery category '$category' not documented"
  done
}

# ---------------------------------------------------------------------------
# 7. Evidence fields documented (files_matching, files_violating, pattern)
# ---------------------------------------------------------------------------
@test "memory-discovery: evidence fields documented" {
  grep -q "files_matching" "$DOC" \
    || fail "Evidence field 'files_matching' not documented"
  grep -q "files_violating" "$DOC" \
    || fail "Evidence field 'files_violating' not documented"
  grep -q "evidence.*pattern\|pattern.*evidence" "$DOC" \
    || grep -q "evidence.pattern" "$DOC" \
    || fail "Evidence field 'pattern' not documented"
}

# ---------------------------------------------------------------------------
# 8. decay_multiplier documented
# ---------------------------------------------------------------------------
@test "memory-discovery: decay_multiplier documented" {
  grep -q "decay_multiplier" "$DOC" \
    || fail "decay_multiplier not documented"
}

# ---------------------------------------------------------------------------
# 9. Source field is auto-discovered
# ---------------------------------------------------------------------------
@test "memory-discovery: source field set to auto-discovered" {
  grep -q "auto-discovered" "$DOC" \
    || fail "source: auto-discovered not documented"
}

# ---------------------------------------------------------------------------
# 10. Initial confidence is MEDIUM
# ---------------------------------------------------------------------------
@test "memory-discovery: initial confidence is MEDIUM" {
  grep -qi "confidence.*MEDIUM\|MEDIUM.*initial" "$DOC" \
    || fail "Initial confidence MEDIUM not documented"
}

# ---------------------------------------------------------------------------
# 11. Promotion to HIGH after 3 successful runs documented
# ---------------------------------------------------------------------------
@test "memory-discovery: promotion to HIGH after 3 runs documented" {
  grep -q "3" "$DOC" || fail "Promotion threshold 3 not documented"
  grep -qi "promote.*HIGH\|promoted.*HIGH\|HIGH" "$DOC" \
    || fail "Promotion to HIGH not documented"
}

# ---------------------------------------------------------------------------
# 12. Configuration parameters documented
# ---------------------------------------------------------------------------
@test "memory-discovery: all configuration parameters documented" {
  for param in "memory_discovery.enabled|enabled" \
               "max_discoveries_per_run" \
               "min_evidence_files" \
               "auto_promote_after_runs"; do
    grep -qE "$param" "$DOC" \
      || fail "Configuration parameter matching '$param' not documented"
  done
}

# ---------------------------------------------------------------------------
# 13. Max 5 discoveries per run constraint
# ---------------------------------------------------------------------------
@test "memory-discovery: max 5 discoveries per run constraint documented" {
  grep -q "5" "$DOC" \
    || fail "Max 5 discoveries per run not documented"
  grep -qi "maximum\|max\|cap" "$DOC" \
    || fail "Discovery cap language not documented"
}

# ---------------------------------------------------------------------------
# 14. Min 3 evidence files constraint
# ---------------------------------------------------------------------------
@test "memory-discovery: min 3 evidence files constraint documented" {
  grep -qE "min.*3.*evidence|3.*evidence.*files|min_evidence_files.*3" "$DOC" \
    || fail "Min 3 evidence files constraint not documented"
}

# ---------------------------------------------------------------------------
# 15. Retrospective integration documented
# ---------------------------------------------------------------------------
@test "memory-discovery: retrospective integration documented" {
  grep -qi "retrospective\|fg-700" "$DOC" \
    || fail "Retrospective integration not documented"
}

# ---------------------------------------------------------------------------
# 16. PREEMPT item ID format uses auto- prefix
# ---------------------------------------------------------------------------
@test "memory-discovery: PREEMPT item ID uses auto- prefix" {
  grep -q "auto-" "$DOC" \
    || fail "auto- prefix for PREEMPT item IDs not documented"
}

# ---------------------------------------------------------------------------
# 17. discovered_run field documented
# ---------------------------------------------------------------------------
@test "memory-discovery: discovered_run field documented" {
  grep -q "discovered_run" "$DOC" \
    || fail "discovered_run field not documented"
}

# ---------------------------------------------------------------------------
# 18. Discovery flow stages (EXPLORE, REVIEW, LEARN) documented
# ---------------------------------------------------------------------------
@test "memory-discovery: discovery flow stages documented" {
  grep -q "EXPLORE" "$DOC" || fail "EXPLORE stage not documented in discovery flow"
  grep -q "REVIEW" "$DOC" || fail "REVIEW stage not documented in discovery flow"
  grep -qi "LEARN\|retrospective" "$DOC" || fail "LEARN stage not documented in discovery flow"
}

# ---------------------------------------------------------------------------
# 19. 2+ runs = candidate threshold documented
# ---------------------------------------------------------------------------
@test "memory-discovery: 2+ runs candidate threshold documented" {
  grep -qE "2\+? runs|observed in 2" "$DOC" \
    || fail "2+ runs candidate threshold not documented"
}

# ---------------------------------------------------------------------------
# 20. forge-log.md labeling documented
# ---------------------------------------------------------------------------
@test "memory-discovery: forge-log.md labeling documented" {
  grep -q "forge-log.md" "$DOC" \
    || fail "forge-log.md labeling not documented"
}
