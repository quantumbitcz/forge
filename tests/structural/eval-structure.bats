#!/usr/bin/env bats
# Structural tests for eval & benchmarking framework

load '../helpers/test-helpers'

@test "eval compression directory exists with relocated files" {
  [[ -d "$PLUGIN_ROOT/evals/compression" ]]
  [[ -f "$PLUGIN_ROOT/evals/compression/run-evals.py" ]]
  [[ -f "$PLUGIN_ROOT/evals/compression/measure.py" ]]
  [[ -d "$PLUGIN_ROOT/evals/compression/tasks" ]]
}

@test "eval pipeline directory structure exists" {
  [[ -d "$PLUGIN_ROOT/evals/pipeline" ]]
  [[ -d "$PLUGIN_ROOT/evals/pipeline/suites" ]]
  [[ -d "$PLUGIN_ROOT/evals/pipeline/fixtures" ]]
  [[ -d "$PLUGIN_ROOT/evals/pipeline/baselines" ]]
  [[ -d "$PLUGIN_ROOT/evals/pipeline/results" ]]
}

@test "eval results directory is gitignored" {
  [[ -f "$PLUGIN_ROOT/evals/pipeline/results/.gitignore" ]]
  grep -q '\*' "$PLUGIN_ROOT/evals/pipeline/results/.gitignore"
}

@test "eval suite files have valid JSON" {
  for suite in "$PLUGIN_ROOT"/evals/pipeline/suites/*.json; do
    [[ -f "$suite" ]] || continue
    run python3 -c "import json; json.load(open('$suite'))"
    [[ "$status" -eq 0 ]]
  done
}

@test "eval suite files have required fields" {
  for suite in "$PLUGIN_ROOT"/evals/pipeline/suites/*.json; do
    [[ -f "$suite" ]] || continue
    run python3 -c "
import json, sys
s = json.load(open('$suite'))
for key in ['name', 'version', 'description', 'tasks']:
    assert key in s, f'Missing {key} in $(basename "$suite")'
for task in s['tasks']:
    for key in ['id', 'language', 'difficulty', 'description', 'fixture', 'validation_command']:
        assert key in task, f'Missing {key} in task {task.get(\"id\", \"unknown\")}'
"
    [[ "$status" -eq 0 ]]
  done
}

@test "eval task IDs are unique per suite" {
  for suite in "$PLUGIN_ROOT"/evals/pipeline/suites/*.json; do
    [[ -f "$suite" ]] || continue
    run python3 -c "
import json
s = json.load(open('$suite'))
ids = [t['id'] for t in s['tasks']]
dupes = [x for x in ids if ids.count(x) > 1]
assert not dupes, f'Duplicate task IDs: {set(dupes)}'
"
    [[ "$status" -eq 0 ]]
  done
}

@test "eval task IDs follow naming convention" {
  for suite in "$PLUGIN_ROOT"/evals/pipeline/suites/*.json; do
    [[ -f "$suite" ]] || continue
    run python3 -c "
import json, re
s = json.load(open('$suite'))
for t in s['tasks']:
    assert re.match(r'^[a-z]{2,5}-[0-9]{2}(-[a-z-]+)?$', t['id']), f'Invalid task ID: {t[\"id\"]}'
"
    [[ "$status" -eq 0 ]]
  done
}

@test "eval fixtures exist for all tasks in all suites" {
  for suite in "$PLUGIN_ROOT"/evals/pipeline/suites/*.json; do
    [[ -f "$suite" ]] || continue
    run python3 -c "
import json, os
s = json.load(open('$suite'))
missing = []
for t in s['tasks']:
    p = os.path.join('$PLUGIN_ROOT', 'evals', 'pipeline', 'fixtures', t['fixture'])
    if not os.path.isdir(p):
        missing.append(t['fixture'])
if missing:
    print('Missing fixtures: ' + ', '.join(missing))
    raise SystemExit(1)
"
    [[ "$status" -eq 0 ]]
  done
}

@test "eval fixtures have .forge-eval.json metadata" {
  for fixture_dir in "$PLUGIN_ROOT"/evals/pipeline/fixtures/*/*; do
    [[ -d "$fixture_dir" ]] || continue
    [[ -f "$fixture_dir/.forge-eval.json" ]]
  done
}

@test "eval fixture metadata has required fields" {
  for fixture_dir in "$PLUGIN_ROOT"/evals/pipeline/fixtures/*/*; do
    [[ -d "$fixture_dir" ]] || continue
    [[ -f "$fixture_dir/.forge-eval.json" ]] || continue
    run python3 -c "
import json
m = json.load(open('$fixture_dir/.forge-eval.json'))
for key in ['fixture_version', 'created', 'language', 'build_command', 'test_command', 'known_failing_tests', 'forge_local_template']:
    assert key in m, f'Missing {key} in $fixture_dir/.forge-eval.json'
tpl = m['forge_local_template']
assert 'language' in tpl, 'Missing language in forge_local_template'
assert 'testing' in tpl, 'Missing testing in forge_local_template'
assert 'commands' in tpl, 'Missing commands in forge_local_template'
"
    [[ "$status" -eq 0 ]]
  done
}

@test "lite suite has exactly 25 tasks" {
  run python3 -c "
import json
s = json.load(open('$PLUGIN_ROOT/evals/pipeline/suites/lite.json'))
assert len(s['tasks']) == 25, f'Expected 25 tasks, got {len(s[\"tasks\"])}'
"
  [[ "$status" -eq 0 ]]
}

@test "lite suite has 5 tasks per language" {
  run python3 -c "
import json
from collections import Counter
s = json.load(open('$PLUGIN_ROOT/evals/pipeline/suites/lite.json'))
counts = Counter(t['language'] for t in s['tasks'])
for lang in ['python', 'typescript', 'kotlin', 'go', 'rust']:
    assert counts[lang] == 5, f'{lang} has {counts[lang]} tasks, expected 5'
"
  [[ "$status" -eq 0 ]]
}

@test "lite suite difficulty distribution is 2 easy 2 medium 1 hard per language" {
  run python3 -c "
import json
from collections import Counter
s = json.load(open('$PLUGIN_ROOT/evals/pipeline/suites/lite.json'))
by_lang = {}
for t in s['tasks']:
    by_lang.setdefault(t['language'], []).append(t['difficulty'])
for lang, diffs in by_lang.items():
    c = Counter(diffs)
    assert c['easy'] == 2, f'{lang}: {c[\"easy\"]} easy, expected 2'
    assert c['medium'] == 2, f'{lang}: {c[\"medium\"]} medium, expected 2'
    assert c['hard'] == 1, f'{lang}: {c[\"hard\"]} hard, expected 1'
"
  [[ "$status" -eq 0 ]]
}

@test "convergence suite has expected_convergence in each task" {
  run python3 -c "
import json
s = json.load(open('$PLUGIN_ROOT/evals/pipeline/suites/convergence.json'))
for t in s['tasks']:
    assert 'expected_convergence' in t, f'Missing expected_convergence in {t[\"id\"]}'
    ec = t['expected_convergence']
    assert 'max_iterations' in ec, f'Missing max_iterations in {t[\"id\"]}'
"
  [[ "$status" -eq 0 ]]
}

@test "convergence suite has 10 tasks" {
  run python3 -c "
import json
s = json.load(open('$PLUGIN_ROOT/evals/pipeline/suites/convergence.json'))
assert len(s['tasks']) == 10, f'Expected 10 tasks, got {len(s[\"tasks\"])}'
"
  [[ "$status" -eq 0 ]]
}

@test "cost suite has expected_cost in each task" {
  run python3 -c "
import json
s = json.load(open('$PLUGIN_ROOT/evals/pipeline/suites/cost.json'))
for t in s['tasks']:
    assert 'expected_cost' in t, f'Missing expected_cost in {t[\"id\"]}'
    ec = t['expected_cost']
    assert 'max_total_cost_usd' in ec, f'Missing max_total_cost_usd in {t[\"id\"]}'
"
  [[ "$status" -eq 0 ]]
}

@test "cost suite has 5 tasks" {
  run python3 -c "
import json
s = json.load(open('$PLUGIN_ROOT/evals/pipeline/suites/cost.json'))
assert len(s['tasks']) == 5, f'Expected 5 tasks, got {len(s[\"tasks\"])}'
"
  [[ "$status" -eq 0 ]]
}

@test "eval CI workflow exists" {
  [[ -f "$PLUGIN_ROOT/.github/workflows/eval.yml" ]]
}

@test "eval CI workflow has required jobs" {
  grep -q 'eval-structural' "$PLUGIN_ROOT/.github/workflows/eval.yml"
  grep -q 'eval-live' "$PLUGIN_ROOT/.github/workflows/eval.yml"
}

@test "eval CI workflow uses dry-run for structural validation" {
  grep -q '\-\-dry-run' "$PLUGIN_ROOT/.github/workflows/eval.yml"
}

@test "state-schema.md documents eval field" {
  grep -q 'eval' "$PLUGIN_ROOT/shared/state-schema.md"
}
