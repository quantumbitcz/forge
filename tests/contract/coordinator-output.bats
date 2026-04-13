#!/usr/bin/env bats
# Contract tests: coordinator structured output compliance.
# Validates that coordinator agents declare FORGE_STRUCTURED_OUTPUT and
# reference the required schema fields in their agent .md files.

load '../helpers/test-helpers'

QG="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
TG="$PLUGIN_ROOT/agents/fg-500-test-gate.md"
RETRO="$PLUGIN_ROOT/agents/fg-700-retrospective.md"
COMM="$PLUGIN_ROOT/shared/agent-communication.md"

# ---------------------------------------------------------------------------
# 1. All three coordinators declare FORGE_STRUCTURED_OUTPUT
# ---------------------------------------------------------------------------
@test "coordinator-output: fg-400-quality-gate declares FORGE_STRUCTURED_OUTPUT" {
  grep -q 'FORGE_STRUCTURED_OUTPUT' "$QG" \
    || fail "fg-400-quality-gate.md does not contain FORGE_STRUCTURED_OUTPUT"
}

@test "coordinator-output: fg-500-test-gate declares FORGE_STRUCTURED_OUTPUT" {
  grep -q 'FORGE_STRUCTURED_OUTPUT' "$TG" \
    || fail "fg-500-test-gate.md does not contain FORGE_STRUCTURED_OUTPUT"
}

@test "coordinator-output: fg-700-retrospective declares FORGE_STRUCTURED_OUTPUT" {
  grep -q 'FORGE_STRUCTURED_OUTPUT' "$RETRO" \
    || fail "fg-700-retrospective.md does not contain FORGE_STRUCTURED_OUTPUT"
}

# ---------------------------------------------------------------------------
# 2. Schema version is documented
# ---------------------------------------------------------------------------
@test "coordinator-output: fg-400 references coordinator-output/v1 schema" {
  grep -q 'coordinator-output/v1' "$QG" \
    || fail "fg-400-quality-gate.md does not reference coordinator-output/v1 schema"
}

@test "coordinator-output: fg-500 references coordinator-output/v1 schema" {
  grep -q 'coordinator-output/v1' "$TG" \
    || fail "fg-500-test-gate.md does not reference coordinator-output/v1 schema"
}

@test "coordinator-output: fg-700 references coordinator-output/v1 schema" {
  grep -q 'coordinator-output/v1' "$RETRO" \
    || fail "fg-700-retrospective.md does not reference coordinator-output/v1 schema"
}

# ---------------------------------------------------------------------------
# 3. fg-400-quality-gate required schema fields
# ---------------------------------------------------------------------------
@test "coordinator-output: fg-400 documents verdict field" {
  grep -q '"verdict"' "$QG" \
    || fail "fg-400-quality-gate.md does not document verdict field"
}

@test "coordinator-output: fg-400 documents score object" {
  grep -q '"score"' "$QG" \
    || fail "fg-400-quality-gate.md does not document score object"
}

@test "coordinator-output: fg-400 documents findings_summary" {
  grep -q '"findings_summary"' "$QG" \
    || fail "fg-400-quality-gate.md does not document findings_summary"
}

@test "coordinator-output: fg-400 documents batches array" {
  grep -q '"batches"' "$QG" \
    || fail "fg-400-quality-gate.md does not document batches array"
}

@test "coordinator-output: fg-400 documents dedup_stats" {
  grep -q '"dedup_stats"' "$QG" \
    || fail "fg-400-quality-gate.md does not document dedup_stats"
}

@test "coordinator-output: fg-400 documents cycle_info" {
  grep -q '"cycle_info"' "$QG" \
    || fail "fg-400-quality-gate.md does not document cycle_info"
}

@test "coordinator-output: fg-400 documents reviewer_agreement" {
  grep -q '"reviewer_agreement"' "$QG" \
    || fail "fg-400-quality-gate.md does not document reviewer_agreement"
}

@test "coordinator-output: fg-400 documents coverage_gaps" {
  grep -q '"coverage_gaps"' "$QG" \
    || fail "fg-400-quality-gate.md does not document coverage_gaps"
}

# ---------------------------------------------------------------------------
# 4. fg-500-test-gate required schema fields
# ---------------------------------------------------------------------------
@test "coordinator-output: fg-500 documents phase_a" {
  grep -q '"phase_a"' "$TG" \
    || fail "fg-500-test-gate.md does not document phase_a"
}

@test "coordinator-output: fg-500 documents phase_b" {
  grep -q '"phase_b"' "$TG" \
    || fail "fg-500-test-gate.md does not document phase_b"
}

@test "coordinator-output: fg-500 documents tests_pass" {
  grep -q '"tests_pass"' "$TG" \
    || fail "fg-500-test-gate.md does not document tests_pass"
}

@test "coordinator-output: fg-500 documents mutation_testing" {
  grep -q '"mutation_testing"' "$TG" \
    || fail "fg-500-test-gate.md does not document mutation_testing"
}

@test "coordinator-output: fg-500 documents verdict object" {
  grep -q '"verdict"' "$TG" \
    || fail "fg-500-test-gate.md does not document verdict object"
}

@test "coordinator-output: fg-500 documents proceed_to" {
  grep -q '"proceed_to"' "$TG" \
    || fail "fg-500-test-gate.md does not document proceed_to field"
}

@test "coordinator-output: fg-500 documents flaky_tests" {
  grep -q '"flaky_tests"' "$TG" \
    || fail "fg-500-test-gate.md does not document flaky_tests"
}

# ---------------------------------------------------------------------------
# 5. fg-700-retrospective required schema fields
# ---------------------------------------------------------------------------
@test "coordinator-output: fg-700 documents run_summary" {
  grep -q '"run_summary"' "$RETRO" \
    || fail "fg-700-retrospective.md does not document run_summary"
}

@test "coordinator-output: fg-700 documents learnings object" {
  grep -q '"learnings"' "$RETRO" \
    || fail "fg-700-retrospective.md does not document learnings object"
}

@test "coordinator-output: fg-700 documents config_changes" {
  grep -q '"config_changes"' "$RETRO" \
    || fail "fg-700-retrospective.md does not document config_changes"
}

@test "coordinator-output: fg-700 documents agent_effectiveness" {
  grep -q '"agent_effectiveness"' "$RETRO" \
    || fail "fg-700-retrospective.md does not document agent_effectiveness"
}

@test "coordinator-output: fg-700 documents trend_comparison" {
  grep -q '"trend_comparison"' "$RETRO" \
    || fail "fg-700-retrospective.md does not document trend_comparison"
}

@test "coordinator-output: fg-700 documents approach_accumulations" {
  grep -q '"approach_accumulations"' "$RETRO" \
    || fail "fg-700-retrospective.md does not document approach_accumulations"
}

# ---------------------------------------------------------------------------
# 6. Extraction standard documented in agent-communication.md
# ---------------------------------------------------------------------------
@test "coordinator-output: agent-communication.md documents structured output standard" {
  grep -q 'Structured Output Standard' "$COMM" \
    || fail "shared/agent-communication.md does not document Structured Output Standard"
}

@test "coordinator-output: agent-communication.md documents extraction regex" {
  grep -q 'FORGE_STRUCTURED_OUTPUT' "$COMM" \
    || fail "shared/agent-communication.md does not document FORGE_STRUCTURED_OUTPUT extraction"
}

@test "coordinator-output: agent-communication.md documents backward compatibility" {
  grep -qi 'backward compatibility' "$COMM" \
    || fail "shared/agent-communication.md does not document backward compatibility"
}

@test "coordinator-output: agent-communication.md documents schema versioning" {
  grep -q 'coordinator-output/v1' "$COMM" \
    || fail "shared/agent-communication.md does not document coordinator-output/v1 schema version"
}
