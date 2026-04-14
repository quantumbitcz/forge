#!/usr/bin/env bats
# Structural tests for the unified compression eval CLI wrapper.

load '../helpers/test-helpers'

@test "compression-eval.sh exists" {
  [[ -f "$PLUGIN_ROOT/benchmarks/compression-eval.sh" ]]
}

@test "compression-eval.sh is executable" {
  [[ -x "$PLUGIN_ROOT/benchmarks/compression-eval.sh" ]]
}

@test "compression-eval.sh has bash shebang" {
  head -1 "$PLUGIN_ROOT/benchmarks/compression-eval.sh" | grep -q '#!/usr/bin/env bash'
}

@test "compression-eval.sh supports --suite flag" {
  grep -q '\-\-suite' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
}

@test "compression-eval.sh supports --dry-run flag" {
  grep -q '\-\-dry-run' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
}

@test "compression-eval.sh supports --model flag" {
  grep -q '\-\-model' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
}

@test "compression-eval.sh supports --compare flag" {
  grep -q '\-\-compare' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
}

@test "compression-eval.sh references all three suite scripts" {
  grep -q 'run-evals.py' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
  grep -q 'run-benchmark.py' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
  grep -q 'measure.py' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
}

@test "compression-eval.sh dispatches eval suite" {
  grep -q 'eval|output' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
}

@test "compression-eval.sh dispatches full suite" {
  grep -qE 'full\)' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
}

@test "compression-eval.sh dispatches input suite" {
  grep -qE 'input\)' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
}

@test "compression-eval.sh dispatches all suite" {
  grep -qE 'all\)' "$PLUGIN_ROOT/benchmarks/compression-eval.sh"
}

@test "prompts.json exists and has 15 prompts" {
  [[ -f "$PLUGIN_ROOT/benchmarks/prompts.json" ]]
  run python3 -c "
import json
data = json.load(open('$PLUGIN_ROOT/benchmarks/prompts.json'))
total = sum(len(cat['prompts']) for cat in data['categories'].values())
assert total == 15, f'Expected 15 prompts, got {total}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "prompts.json has 3 categories (explanation, review, code-gen)" {
  run python3 -c "
import json
data = json.load(open('$PLUGIN_ROOT/benchmarks/prompts.json'))
cats = sorted(data['categories'].keys())
assert cats == ['code-gen', 'explanation', 'review'], f'Expected 3 categories, got {cats}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "session-start.sh emits STATUS badge for caveman mode" {
  grep -q '\[STATUS:' "$PLUGIN_ROOT/hooks/session-start.sh"
}

@test "session-start.sh contains full compression rule blocks" {
  grep -q "OUTPUT COMPRESSION -- LITE MODE" "$PLUGIN_ROOT/hooks/session-start.sh"
  grep -q "OUTPUT COMPRESSION -- FULL" "$PLUGIN_ROOT/hooks/session-start.sh"
  grep -q "OUTPUT COMPRESSION -- ULTRA" "$PLUGIN_ROOT/hooks/session-start.sh"
}

@test "output-compression.md references arXiv:2604.00025" {
  grep -q "2604.00025" "$PLUGIN_ROOT/shared/output-compression.md"
}

@test "output-compression.md includes error diagnostics auto-clarity trigger" {
  grep -q "Error diagnostics" "$PLUGIN_ROOT/shared/output-compression.md"
}

@test "output-compression.md has Session Savings column" {
  grep -q "Session Savings" "$PLUGIN_ROOT/shared/output-compression.md"
}

@test "config schema includes compression_eval section" {
  grep -q '"compression_eval"' "$PLUGIN_ROOT/shared/config-schema.json"
}

@test "config schema validates compression_eval.enabled as boolean" {
  run python3 -c "
import json
schema = json.load(open('$PLUGIN_ROOT/shared/config-schema.json'))
ce = schema['properties']['compression_eval']
assert ce['properties']['enabled']['type'] == 'boolean', 'enabled must be boolean'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "config schema validates compression_eval.drift_threshold_pct range" {
  run python3 -c "
import json
schema = json.load(open('$PLUGIN_ROOT/shared/config-schema.json'))
dtp = schema['properties']['compression_eval']['properties']['drift_threshold_pct']
assert dtp.get('minimum', 0) >= 10, 'minimum must be >= 10'
assert dtp.get('maximum', 999) <= 200, 'maximum must be <= 200'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "prompts.json prompts have required_facts" {
  run python3 -c "
import json
data = json.load(open('$PLUGIN_ROOT/benchmarks/prompts.json'))
for cat_name, cat in data['categories'].items():
    for prompt in cat['prompts']:
        assert 'required_facts' in prompt, f'{prompt[\"id\"]} missing required_facts'
        assert len(prompt['required_facts']) > 0, f'{prompt[\"id\"]} has empty required_facts'
print('OK')
"
  assert_success
  assert_output "OK"
}
