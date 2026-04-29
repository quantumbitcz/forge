#!/usr/bin/env bash
# Forge eval runner. Executes eval suites and produces structured results.
# Usage: eval-runner.sh run --suite <name> [--live|--dry-run] [--model <model>]
#        eval-runner.sh compare --baseline <name> [--current <file>] [--format json|table|markdown]
#        eval-runner.sh save --baseline <name> [--from <file>] [--baseline-dir <dir>]
#        eval-runner.sh list [--suites|--baselines|--results]
#        eval-runner.sh clean [--all|--older-than <days>]
set -euo pipefail
[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || { echo "ERROR: bash 4.0+ required" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITES_DIR="${SCRIPT_DIR}/suites"
BASELINES_DIR="${SCRIPT_DIR}/baselines"
RESULTS_DIR="${SCRIPT_DIR}/results"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

# Source shared config
source "${SCRIPT_DIR}/eval-config.sh"

# ---------------------------------------------------------------------------
# _glob_exists <pattern>
# Returns 0 if any file matches the glob, 1 otherwise.
# Portable replacement for compgen -G (per CLAUDE.md gotcha).
# ---------------------------------------------------------------------------
_glob_exists() {
  local pattern="$1"
  local f
  for f in $pattern; do
    [[ -e "$f" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat <<'USAGE'
Forge Eval Runner

Usage:
  eval-runner.sh run --suite <name> [--live|--dry-run] [--model <model>] [--parallel <N>] [--tags <t1,t2>] [--keep-workdirs]
  eval-runner.sh compare --baseline <name|path> [--current <file>] [--suite <name>] [--format json|table|markdown|csv] [--threshold <N>]
  eval-runner.sh save --baseline <name> [--from <file>] [--baseline-dir <dir>]
  eval-runner.sh list [--suites|--baselines|--results]
  eval-runner.sh clean [--all|--older-than <days>]

Commands:
  run       Execute an eval suite (--dry-run for validation only, --live for real execution)
  compare   Compare current results against a baseline
  save      Save results as a named baseline
  list      List available suites, baselines, or results
  clean     Clean up result files

Options:
  --suite <name>          Suite to run (lite, convergence, cost, compression, smoke)
  --dry-run               Validate suite without API calls
  --live                  Execute tasks via claude CLI
  --model <model>         Model override (haiku, sonnet, opus)
  --parallel <N>          Concurrent tasks (1-5, default: 1)
  --tags <t1,t2>          Filter tasks by tags
  --keep-workdirs         Preserve task working directories
  --baseline <name|path>  Baseline name or file path
  --current <file>        Current result file for comparison
  --format <fmt>          Output format (json, table, markdown, csv)
  --threshold <N>         Regression threshold percent (5-50, default: 20)
  --from <file>           Source result file for save
  --baseline-dir <dir>    Custom baseline directory
USAGE
  exit 2
}

# ---------------------------------------------------------------------------
# validate_suite_json <suite_file>
# Validates a suite JSON file has correct schema.
# Returns 0 on success, 1 on validation failure (errors to stderr).
# ---------------------------------------------------------------------------
validate_suite_json() {
  local suite_file="$1"
  # Pass the suite path via argv (sys.argv[1]) instead of inlining it into
  # the Python source. On Windows, ``${suite_file}`` contains backslashes
  # which Python interprets as escape sequences inside the heredoc.
  "${FORGE_PYTHON:-python3}" - "$suite_file" <<'PYEOF' 2>&1
import json, sys, re, os

suite_file = sys.argv[1]
try:
    s = json.load(open(suite_file))
except (json.JSONDecodeError, FileNotFoundError) as e:
    print(f'ERROR: Invalid JSON in {suite_file}: {e}', file=sys.stderr)
    sys.exit(1)

errors = []

# Top-level required fields
for key in ['name', 'version', 'description', 'tasks']:
    if key not in s:
        errors.append(f'Missing required field: {key}')

if 'tasks' not in s:
    for e in errors:
        print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)

valid_languages = {'python', 'typescript', 'kotlin', 'go', 'rust'}
valid_difficulties = {'easy', 'medium', 'hard'}
task_id_pattern = re.compile(r'^[a-z]{2,5}-[0-9]{2}(-[a-z-]+)?$')
seen_ids = set()

for i, task in enumerate(s['tasks']):
    tid = task.get('id', f'task[{i}]')

    # Required task fields
    for key in ['id', 'language', 'difficulty', 'description', 'fixture', 'validation_command']:
        if key not in task:
            errors.append(f'Task {tid}: missing required field: {key}')

    # ID format
    if 'id' in task and not task_id_pattern.match(task['id']):
        errors.append(f'Task {tid}: ID does not match pattern ^[a-z]{2,5}-[0-9]{2}(-[a-z-]+)?$')

    # Duplicate IDs
    if 'id' in task:
        if task['id'] in seen_ids:
            errors.append(f'Task {tid}: duplicate task ID')
        seen_ids.add(task['id'])

    # Language validation
    if task.get('language') and task['language'] not in valid_languages:
        errors.append(f"Task {tid}: invalid language: {task['language']}")

    # Difficulty validation
    if task.get('difficulty') and task['difficulty'] not in valid_difficulties:
        errors.append(f"Task {tid}: invalid difficulty: {task['difficulty']}")

if errors:
    for e in errors:
        print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)

print(f"Validated {len(s['tasks'])} tasks in suite \"{s.get('name', 'unknown')}\"")
PYEOF
  return "${PIPESTATUS[0]}"
}

# ---------------------------------------------------------------------------
# cmd_run
# ---------------------------------------------------------------------------
cmd_run() {
  local suite="" mode="" model="" parallel="${EVAL_DEFAULT_PARALLEL}"
  local tags="" keep_workdirs="${EVAL_KEEP_WORKDIRS}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --suite)     suite="${2:?--suite requires a value}"; shift 2 ;;
      --dry-run)   mode="dry-run"; shift ;;
      --live)      mode="live"; shift ;;
      --model)     model="${2:?--model requires a value}"; shift 2 ;;
      --parallel)  parallel="${2:?--parallel requires a value}"; shift 2 ;;
      --tags)      tags="${2:?--tags requires a value}"; shift 2 ;;
      --keep-workdirs) keep_workdirs=true; shift ;;
      *)           echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
  done

  if [[ -z "$suite" ]]; then
    echo "ERROR: --suite is required" >&2
    echo "Usage: eval-runner.sh run --suite <name> [--live|--dry-run]" >&2
    exit 2
  fi

  if [[ -z "$mode" ]]; then
    echo "ERROR: Specify --live or --dry-run" >&2
    echo "Usage: eval-runner.sh run --suite <name> [--live|--dry-run]" >&2
    exit 2
  fi

  # Validate suite exists
  local suite_file="${SUITES_DIR}/${suite}.json"
  if [[ ! -f "$suite_file" ]]; then
    echo "ERROR: Unknown suite: ${suite}" >&2
    echo "Available suites:" >&2
    for f in "${SUITES_DIR}"/*.json; do
      [[ -f "$f" ]] && echo "  $(basename "$f" .json)" >&2
    done
    exit 2
  fi

  # Validate suite schema
  local validation_output
  if ! validation_output="$(validate_suite_json "$suite_file" 2>&1)"; then
    echo "$validation_output" >&2
    exit 1
  fi

  if [[ "$mode" == "dry-run" ]]; then
    # Dry-run: validate and report
    echo "=== Eval Dry Run ==="
    echo "$validation_output"

    # Count tasks and check fixtures (paths via argv to avoid Windows
    # backslash-escape parsing inside Python source strings).
    local task_count fixture_count missing_fixtures
    task_count="$("${FORGE_PYTHON:-python3}" - "$suite_file" <<'PYEOF'
import json, sys
print(len(json.load(open(sys.argv[1]))['tasks']))
PYEOF
)"
    fixture_count=0
    missing_fixtures=0

    local fixtures_json
    fixtures_json="$("${FORGE_PYTHON:-python3}" - "$suite_file" <<'PYEOF'
import json, sys
s = json.load(open(sys.argv[1]))
for t in s['tasks']:
    print(t['fixture'])
PYEOF
)"

    while IFS= read -r fixture; do
      if [[ -d "${FIXTURES_DIR}/${fixture}" ]]; then
        fixture_count=$((fixture_count + 1))
      else
        missing_fixtures=$((missing_fixtures + 1))
      fi
    done <<< "$fixtures_json"

    echo ""
    echo "Suite: ${suite}"
    echo "Tasks: ${task_count}"
    echo "Fixtures found: ${fixture_count}"
    if (( missing_fixtures > 0 )); then
      echo "Fixtures missing: ${missing_fixtures} (stub fixtures expected)"
    fi
    echo "Estimated time: ~$((task_count * EVAL_DEFAULT_TIMEOUT)) minutes"
    echo ""
    echo "Dry-run complete. No API calls made."
    return 0
  fi

  if [[ "$mode" == "live" ]]; then
    # Live mode: check prerequisites
    if ! command -v claude &>/dev/null; then
      echo "ERROR: claude CLI not found. Install from https://claude.ai/code" >&2
      exit 1
    fi

    echo "=== Eval Live Run ==="
    echo "Suite: ${suite}"
    echo "Model: ${model:-default}"
    echo "Parallel: ${parallel}"

    local task_count
    task_count="$("${FORGE_PYTHON:-python3}" - "$suite_file" <<'PYEOF'
import json, sys
print(len(json.load(open(sys.argv[1]))['tasks']))
PYEOF
)"
    echo "Tasks: ${task_count}"

    local timestamp
    timestamp="$(date -u '+%Y-%m-%d-%H-%M-%S')"
    local result_file="${RESULTS_DIR}/${timestamp}-${suite}.json"

    # Execute tasks
    local task_results_dir
    task_results_dir="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/forge-eval.XXXXXX")"

    "${FORGE_PYTHON:-python3}" -c "
import json, subprocess, sys, os, time, shutil

suite = json.load(open('${suite_file}'))
fixtures_dir = '${FIXTURES_DIR}'
task_results_dir = '${task_results_dir}'
model = '${model}' or None
tags_filter = '${tags}'.split(',') if '${tags}' else []
keep_workdirs = True if '${keep_workdirs}' != 'false' else False
timeout_min = ${EVAL_DEFAULT_TIMEOUT}

results = {
    'suite': suite['name'],
    'version': suite['version'],
    'timestamp': '${timestamp}'.replace('-', '', 2).replace('-', 'T', 1).replace('-', ':', 2) + 'Z',
    'duration_seconds': 0,
    'environment': json.loads('$(eval_get_environment)'),
    'results': {
        'tasks': [],
        'aggregate': {}
    }
}

start_time = time.time()
passed = 0
failed = 0
errors = 0
skipped = 0

for i, task in enumerate(suite['tasks']):
    tid = task['id']

    # Tag filtering
    if tags_filter:
        task_tags = task.get('tags', [])
        if not set(tags_filter) & set(task_tags):
            skipped += 1
            continue

    print(f'  [{i+1}/{len(suite[\"tasks\"])}] {tid}', end='', flush=True)

    fixture_path = os.path.join(fixtures_dir, task['fixture'])
    if not os.path.isdir(fixture_path):
        print(f' SKIP (fixture not found)')
        errors += 1
        results['results']['tasks'].append({
            'id': tid,
            'language': task['language'],
            'difficulty': task['difficulty'],
            'result': 'ERROR',
            'error': 'fixture not found',
            'duration_seconds': 0,
            'final_score': None,
            'tags': task.get('tags', [])
        })
        continue

    # Create isolated workdir
    workdir = os.path.join(task_results_dir, tid)
    shutil.copytree(fixture_path, workdir)

    task_start = time.time()
    try:
        # Determine skill
        skill = task.get('skill', 'forge-fix')
        prompt = task['description']

        cmd = ['claude', '--print', '--dangerously-skip-permissions', '-p', f'/{skill} {prompt}']
        if model:
            cmd.extend(['--model', model])

        proc = subprocess.run(
            cmd, cwd=workdir,
            timeout=timeout_min * 60,
            capture_output=True, text=True
        )
        task_duration = time.time() - task_start

        # Check for state.json
        state_file = os.path.join(workdir, '.forge', 'state.json')
        final_score = None
        convergence = {}
        if os.path.isfile(state_file):
            state = json.load(open(state_file))
            sh = state.get('score_history', [])
            final_score = sh[-1] if sh else None
            convergence = state.get('convergence', {})

        # Run validation command
        val_cmd = task['validation_command']
        val_timeout = ${EVAL_DEFAULT_VALIDATION_TIMEOUT}
        try:
            val_proc = subprocess.run(
                val_cmd, shell=True, cwd=workdir,
                timeout=val_timeout,
                capture_output=True, text=True
            )
            val_passed = val_proc.returncode == 0
        except subprocess.TimeoutExpired:
            val_passed = False

        result_status = 'PASS' if val_passed else 'FAIL'
        if result_status == 'PASS':
            passed += 1
        else:
            failed += 1

        print(f' {result_status} ({task_duration:.0f}s, score={final_score})')

        results['results']['tasks'].append({
            'id': tid,
            'language': task['language'],
            'difficulty': task['difficulty'],
            'result': result_status,
            'duration_seconds': round(task_duration),
            'final_score': final_score,
            'convergence': convergence,
            'tags': task.get('tags', [])
        })

    except subprocess.TimeoutExpired:
        task_duration = time.time() - task_start
        print(f' TIMEOUT ({task_duration:.0f}s)')
        errors += 1
        results['results']['tasks'].append({
            'id': tid,
            'language': task['language'],
            'difficulty': task['difficulty'],
            'result': 'TIMEOUT',
            'duration_seconds': round(task_duration),
            'final_score': None,
            'tags': task.get('tags', [])
        })
    except Exception as e:
        task_duration = time.time() - task_start
        print(f' ERROR: {e}')
        errors += 1
        results['results']['tasks'].append({
            'id': tid,
            'language': task['language'],
            'difficulty': task['difficulty'],
            'result': 'ERROR',
            'error': str(e),
            'duration_seconds': round(task_duration),
            'final_score': None,
            'tags': task.get('tags', [])
        })

    if not keep_workdirs:
        shutil.rmtree(workdir, ignore_errors=True)

total_duration = time.time() - start_time
total = passed + failed + errors
results['duration_seconds'] = round(total_duration)
results['results']['aggregate'] = {
    'total': total,
    'passed': passed,
    'failed': failed,
    'errors': errors,
    'skipped': skipped,
    'pass_rate': passed / (total - errors - skipped) if (total - errors - skipped) > 0 else 0.0
}

json.dump(results, open('${result_file}', 'w'), indent=2)
print(f'')
print(f'Results: {passed} passed, {failed} failed, {errors} errors')
print(f'Pass rate: {results[\"results\"][\"aggregate\"][\"pass_rate\"]:.1%}')
print(f'Duration: {total_duration:.0f}s')
print(f'Results saved to: ${result_file}')
"
    return $?
  fi
}

# ---------------------------------------------------------------------------
# cmd_compare
# ---------------------------------------------------------------------------
cmd_compare() {
  local baseline="" current="" format="table" suite="" threshold="${EVAL_DEFAULT_REGRESSION_THRESHOLD}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --baseline)  baseline="${2:?--baseline requires a value}"; shift 2 ;;
      --current)   current="${2:?--current requires a value}"; shift 2 ;;
      --suite)     suite="${2:?--suite requires a value}"; shift 2 ;;
      --format)    format="${2:?--format requires a value}"; shift 2 ;;
      --threshold) threshold="${2:?--threshold requires a value}"; shift 2 ;;
      *)           echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
  done

  if [[ -z "$baseline" ]]; then
    echo "ERROR: --baseline is required" >&2
    exit 2
  fi

  # Resolve baseline path
  local baseline_file="$baseline"
  if [[ ! -f "$baseline_file" ]]; then
    baseline_file="${BASELINES_DIR}/${baseline}.json"
    if [[ ! -f "$baseline_file" ]]; then
      echo "ERROR: Baseline not found: ${baseline}" >&2
      exit 2
    fi
  fi

  # Resolve current result
  local current_file="$current"
  if [[ -z "$current_file" ]]; then
    # Auto-detect latest result
    local pattern="*.json"
    if [[ -n "$suite" ]]; then
      pattern="*-${suite}.json"
    fi
    current_file="$(ls -t "${RESULTS_DIR}"/${pattern} 2>/dev/null | head -1)" || true
    if [[ -z "$current_file" || ! -f "$current_file" ]]; then
      echo "ERROR: No result file found. Run an eval first or specify --current." >&2
      exit 2
    fi
  fi

  # Pass paths and parameters via argv to avoid Windows backslash-escape
  # parsing inside the Python source.
  "${FORGE_PYTHON:-python3}" - "$baseline_file" "$current_file" "$format" "$threshold" <<'PYEOF'
import json, sys

baseline = json.load(open(sys.argv[1]))
current = json.load(open(sys.argv[2]))
format_type = sys.argv[3]
threshold = int(sys.argv[4])
baseline_arg = sys.argv[1]
current_arg = sys.argv[2]

# Build task maps
baseline_tasks = {t['id']: t for t in baseline.get('results', {}).get('tasks', [])}
current_tasks = {t['id']: t for t in current.get('results', {}).get('tasks', [])}

all_ids = sorted(set(list(baseline_tasks.keys()) + list(current_tasks.keys())))

regressions = []
improvements = []
stable = []
new_tasks = []
removed = []

for tid in all_ids:
    bt = baseline_tasks.get(tid)
    ct = current_tasks.get(tid)

    if bt and not ct:
        removed.append(tid)
    elif ct and not bt:
        new_tasks.append(tid)
    else:
        br = bt.get('result', 'UNKNOWN')
        cr = ct.get('result', 'UNKNOWN')
        if br == 'PASS' and cr != 'PASS':
            regressions.append(tid)
        elif br != 'PASS' and cr == 'PASS':
            improvements.append(tid)
        else:
            stable.append(tid)

# Aggregate comparison
b_agg = baseline.get('results', {}).get('aggregate', {})
c_agg = current.get('results', {}).get('aggregate', {})
pass_rate_delta = c_agg.get('pass_rate', 0) - b_agg.get('pass_rate', 0)

verdict = 'REGRESSION' if regressions else ('IMPROVEMENT' if improvements else 'STABLE')

comparison = {
    'verdict': verdict,
    'regression_count': len(regressions),
    'improvement_count': len(improvements),
    'aggregate': {
        'baseline_pass_rate': b_agg.get('pass_rate', 0),
        'current_pass_rate': c_agg.get('pass_rate', 0),
        'pass_rate_delta': round(pass_rate_delta, 4),
        'regressions': regressions,
        'improvements': improvements,
        'stable': stable,
        'new': new_tasks,
        'removed': removed
    }
}

result = {
    'baseline': baseline_arg,
    'current': current_arg,
    'comparison': comparison
}

if format_type == 'json':
    print(json.dumps(result, indent=2))
elif format_type == 'markdown':
    print(f'## Eval Comparison')
    print(f'')
    print(f'Verdict: **{verdict}**')
    print(f'')
    print(f'| Metric | Baseline | Current | Delta |')
    print(f'|--------|----------|---------|-------|')
    print(f"| Pass Rate | {b_agg.get('pass_rate', 0):.1%} | {c_agg.get('pass_rate', 0):.1%} | {pass_rate_delta:+.1%} |")
    if regressions:
        print(f'')
        print(f'### Regressions ({len(regressions)})')
        for r in regressions:
            print(f'- {r}')
    if improvements:
        print(f'')
        print(f'### Improvements ({len(improvements)})')
        for imp in improvements:
            print(f'- {imp}')
else:
    # table format
    print(f'Verdict: {verdict}')
    print(f"Pass Rate: {b_agg.get('pass_rate', 0):.1%} -> {c_agg.get('pass_rate', 0):.1%} ({pass_rate_delta:+.1%})")
    if regressions:
        print(f"Regressions ({len(regressions)}): {' '.join(regressions)}")
    if improvements:
        print(f"Improvements ({len(improvements)}): {' '.join(improvements)}")

sys.exit(3 if verdict == 'REGRESSION' else 0)
PYEOF
  return $?
}

# ---------------------------------------------------------------------------
# cmd_save
# ---------------------------------------------------------------------------
cmd_save() {
  local baseline_name="" from_file="" baseline_dir="${BASELINES_DIR}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --baseline)     baseline_name="${2:?--baseline requires a value}"; shift 2 ;;
      --from)         from_file="${2:?--from requires a value}"; shift 2 ;;
      --baseline-dir) baseline_dir="${2:?--baseline-dir requires a value}"; shift 2 ;;
      *)              echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
  done

  if [[ -z "$baseline_name" ]]; then
    echo "ERROR: --baseline is required" >&2
    exit 2
  fi

  # Resolve source file
  local source_file="$from_file"
  if [[ -z "$source_file" ]]; then
    source_file="$(ls -t "${RESULTS_DIR}"/*.json 2>/dev/null | head -1)" || true
    if [[ -z "$source_file" || ! -f "$source_file" ]]; then
      echo "ERROR: No result file found. Run an eval first or specify --from." >&2
      exit 2
    fi
  fi

  if [[ ! -f "$source_file" ]]; then
    echo "ERROR: Source file not found: ${source_file}" >&2
    exit 1
  fi

  mkdir -p "$baseline_dir"
  local dest="${baseline_dir}/${baseline_name}.json"

  # Pass paths and the baseline name via argv to avoid Windows backslash-
  # escape parsing inside the Python source.
  "${FORGE_PYTHON:-python3}" - "$source_file" "$baseline_name" "$dest" <<'PYEOF'
import json, sys, time
source_file, baseline_name, dest = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(source_file))
data['baseline_metadata'] = {
    'name': baseline_name,
    'created': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'source_file': source_file
}
json.dump(data, open(dest, 'w'), indent=2)
print(f'Baseline saved: {dest}')
PYEOF
}

# ---------------------------------------------------------------------------
# cmd_list
# ---------------------------------------------------------------------------
cmd_list() {
  local what="suites"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --suites)    what="suites"; shift ;;
      --baselines) what="baselines"; shift ;;
      --results)   what="results"; shift ;;
      *)           echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
  done

  case "$what" in
    suites)
      echo "Available suites:"
      if _glob_exists "${SUITES_DIR}/*.json"; then
        for f in "${SUITES_DIR}"/*.json; do
          local name desc task_count
          name="$(basename "$f" .json)"
          # Pass path via argv to avoid Windows backslash-escape parsing.
          desc="$("${FORGE_PYTHON:-python3}" - "$f" 2>/dev/null <<'PYEOF'
import json, sys
print(json.load(open(sys.argv[1])).get('description',''))
PYEOF
)"
          [[ -z "$desc" ]] && desc=""
          task_count="$("${FORGE_PYTHON:-python3}" - "$f" 2>/dev/null <<'PYEOF'
import json, sys
print(len(json.load(open(sys.argv[1])).get('tasks',[])))
PYEOF
)"
          [[ -z "$task_count" ]] && task_count="?"
          echo "  ${name} (${task_count} tasks) -- ${desc}"
        done
      else
        echo "  (none)"
      fi
      ;;
    baselines)
      echo "Available baselines:"
      if _glob_exists "${BASELINES_DIR}/*.json"; then
        for f in "${BASELINES_DIR}"/*.json; do
          echo "  $(basename "$f" .json)"
        done
      else
        echo "  (none)"
      fi
      ;;
    results)
      echo "Recent results:"
      if _glob_exists "${RESULTS_DIR}/*.json"; then
        for f in "${RESULTS_DIR}"/*.json; do
          echo "  $(basename "$f")"
        done
      else
        echo "  (none)"
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# cmd_clean
# ---------------------------------------------------------------------------
cmd_clean() {
  local mode="all"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)        mode="all"; shift ;;
      --older-than) mode="older"; shift ;;  # TODO: implement age-based cleanup
      *)            echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
  done

  if [[ "$mode" == "all" ]]; then
    if _glob_exists "${RESULTS_DIR}/*.json"; then
      local count=0
      for f in "${RESULTS_DIR}"/*.json; do
        rm -f "$f"
        count=$((count + 1))
      done
      echo "Cleaned ${count} result files."
    else
      echo "No result files to clean."
    fi
  fi
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  run)     shift; cmd_run "$@" ;;
  compare) shift; cmd_compare "$@" ;;
  save)    shift; cmd_save "$@" ;;
  list)    shift; cmd_list "$@" ;;
  clean)   shift; cmd_clean "$@" ;;
  *)       usage ;;
esac
