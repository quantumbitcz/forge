#!/usr/bin/env bash
# Forge eval report generator. Analyzes results without running evals.
# Usage: eval-report.sh summary <result-file>
#        eval-report.sh compare <result-file> --baseline <name>
#        eval-report.sh trend --results <f1> <f2> ...
#        eval-report.sh cross-model --results <f1> <f2> ...
#        eval-report.sh export <result-file> --format csv|markdown|json
set -euo pipefail
[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || { echo "ERROR: bash 4.0+ required" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared config
source "${SCRIPT_DIR}/eval-config.sh"

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat <<'USAGE'
Forge Eval Report Generator

Usage:
  eval-report.sh summary <result-file> [--format table|json|markdown]
  eval-report.sh compare <result-file> --baseline <name|path> [--format table|json|markdown]
  eval-report.sh trend --results <f1> [<f2> ...] [--format table|json|markdown]
  eval-report.sh cross-model --results <f1> [<f2> ...] [--format table|json|markdown]
  eval-report.sh export <result-file> --format csv|markdown|json

Commands:
  summary       Pretty-print per-task results and aggregate metrics
  compare       Compare results against a baseline
  trend         Show quality trajectory across multiple runs
  cross-model   Compare results across different model configurations
  export        Convert result file to different format
USAGE
  exit 2
}

# ---------------------------------------------------------------------------
# cmd_summary <result-file> [--format <fmt>]
# ---------------------------------------------------------------------------
cmd_summary() {
  local result_file="" format="table"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format) format="${2:?--format requires a value}"; shift 2 ;;
      -*)       echo "ERROR: Unknown option: $1" >&2; usage ;;
      *)        result_file="$1"; shift ;;
    esac
  done

  if [[ -z "$result_file" || ! -f "$result_file" ]]; then
    echo "ERROR: Valid result file required" >&2
    exit 2
  fi

  "${FORGE_PYTHON:-python3}" -c "
import json, sys

data = json.load(open('${result_file}'))
fmt = '${format}'
tasks = data.get('results', {}).get('tasks', [])
agg = data.get('results', {}).get('aggregate', {})

if fmt == 'json':
    print(json.dumps(data, indent=2))
elif fmt == 'markdown':
    print('## Eval Summary')
    print('')
    print(f'Suite: **{data.get(\"suite\", \"unknown\")}**')
    print(f'Timestamp: {data.get(\"timestamp\", \"unknown\")}')
    print(f'Duration: {data.get(\"duration_seconds\", 0)}s')
    print('')
    print(f'Pass Rate: **{agg.get(\"pass_rate\", 0):.1%}** ({agg.get(\"passed\", 0)}/{agg.get(\"total\", 0)})')
    print('')
    print('| Task | Language | Difficulty | Result | Score | Duration |')
    print('|------|----------|------------|--------|-------|----------|')
    for t in tasks:
        score = t.get('final_score', '-') or '-'
        print(f'| {t[\"id\"]} | {t[\"language\"]} | {t[\"difficulty\"]} | {t[\"result\"]} | {score} | {t.get(\"duration_seconds\", 0)}s |')
    qs = agg.get('quality_summary', {})
    if qs:
        print('')
        print('### Quality')
        print(f'- Avg Score: {qs.get(\"avg_score\", \"-\")}')
        print(f'- Total Tokens: {qs.get(\"total_tokens\", 0):,}')
        print(f'- Total Cost: \${qs.get(\"total_cost_usd\", 0):.2f}')
else:
    # Table format
    print(f'Suite: {data.get(\"suite\", \"unknown\")}')
    print(f'Timestamp: {data.get(\"timestamp\", \"unknown\")}')
    print(f'Duration: {data.get(\"duration_seconds\", 0)}s')
    print(f'Pass Rate: {agg.get(\"pass_rate\", 0):.1%} ({agg.get(\"passed\", 0)}/{agg.get(\"total\", 0)})')
    print('')
    print('{:<25} {:<12} {:<10} {:<8} {:<8} {:<10}'.format(
        'Task', 'Language', 'Difficulty', 'Result', 'Score', 'Duration'))
    print('-' * 75)
    for t in tasks:
        score = str(t.get('final_score', '-') or '-')
        print('{:<25} {:<12} {:<10} {:<8} {:<8} {}s'.format(
            t['id'], t['language'], t['difficulty'],
            t['result'], score, t.get('duration_seconds', 0)))
    qs = agg.get('quality_summary', {})
    if qs and qs.get('avg_score') is not None:
        print('')
        print(f'Avg Score: {qs[\"avg_score\"]}  Tokens: {qs.get(\"total_tokens\", 0):,}  Cost: \${qs.get(\"total_cost_usd\", 0):.2f}')
"
}

# ---------------------------------------------------------------------------
# cmd_compare <result-file> --baseline <name|path>
# ---------------------------------------------------------------------------
cmd_compare() {
  local result_file="" baseline="" format="table"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --baseline) baseline="${2:?--baseline requires a value}"; shift 2 ;;
      --format)   format="${2:?--format requires a value}"; shift 2 ;;
      -*)         echo "ERROR: Unknown option: $1" >&2; usage ;;
      *)          result_file="$1"; shift ;;
    esac
  done

  if [[ -z "$result_file" || -z "$baseline" ]]; then
    echo "ERROR: result file and --baseline required" >&2
    exit 2
  fi

  # Resolve baseline
  local baseline_file="$baseline"
  if [[ ! -f "$baseline_file" ]]; then
    baseline_file="${SCRIPT_DIR}/baselines/${baseline}.json"
  fi

  "${FORGE_PYTHON:-python3}" "${SCRIPT_DIR}/compare-results.py" \
    --baseline "$baseline_file" \
    --current "$result_file" \
    --format "$format"
}

# ---------------------------------------------------------------------------
# cmd_trend --results <f1> <f2> ...
# ---------------------------------------------------------------------------
cmd_trend() {
  local format="table"
  local -a result_files=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --results) shift; while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do result_files+=("$1"); shift; done ;;
      --format)  format="${2:?--format requires a value}"; shift 2 ;;
      -*)        echo "ERROR: Unknown option: $1" >&2; usage ;;
      *)         result_files+=("$1"); shift ;;
    esac
  done

  if [[ ${#result_files[@]} -eq 0 ]]; then
    echo "ERROR: At least one result file required" >&2
    exit 2
  fi

  "${FORGE_PYTHON:-python3}" -c "
import json, sys

files = $(printf '"%s",' "${result_files[@]}" | sed 's/,$//' | sed 's/^/[/' | sed 's/$/]/')
fmt = '${format}'

runs = []
for f in files:
    try:
        data = json.load(open(f))
        agg = data.get('results', {}).get('aggregate', {})
        qs = agg.get('quality_summary', {})
        runs.append({
            'file': f,
            'timestamp': data.get('timestamp', 'unknown'),
            'suite': data.get('suite', 'unknown'),
            'pass_rate': agg.get('pass_rate', 0),
            'total': agg.get('total', 0),
            'passed': agg.get('passed', 0),
            'avg_score': qs.get('avg_score'),
            'total_tokens': qs.get('total_tokens', 0),
            'total_cost': qs.get('total_cost_usd', 0)
        })
    except Exception as e:
        print(f'WARNING: Could not load {f}: {e}', file=sys.stderr)

if not runs:
    print('No valid results found.')
    sys.exit(1)

# Determine trend
if len(runs) >= 2:
    first_pr = runs[0]['pass_rate']
    last_pr = runs[-1]['pass_rate']
    if last_pr > first_pr + 0.05:
        trend = 'IMPROVING'
    elif last_pr < first_pr - 0.05:
        trend = 'DEGRADING'
    else:
        trend = 'STABLE'
else:
    trend = 'INSUFFICIENT_DATA'

if fmt == 'json':
    print(json.dumps({'trend': trend, 'runs': runs}, indent=2))
elif fmt == 'markdown':
    print('## Trend Analysis')
    print('')
    print(f'Overall Trend: **{trend}**')
    print('')
    print('| Timestamp | Suite | Pass Rate | Passed/Total | Avg Score | Tokens | Cost |')
    print('|-----------|-------|-----------|--------------|-----------|--------|------|')
    for r in runs:
        score = r['avg_score'] if r['avg_score'] is not None else '-'
        print(f'| {r[\"timestamp\"]} | {r[\"suite\"]} | {r[\"pass_rate\"]:.1%} | {r[\"passed\"]}/{r[\"total\"]} | {score} | {r[\"total_tokens\"]:,} | \${r[\"total_cost\"]:.2f} |')
else:
    print(f'Trend: {trend}')
    print('')
    print('{:<25} {:<10} {:<12} {:<14} {:<10} {:<12} {:<8}'.format(
        'Timestamp', 'Suite', 'Pass Rate', 'Passed/Total', 'Avg Score', 'Tokens', 'Cost'))
    print('-' * 90)
    for r in runs:
        score = str(r['avg_score']) if r['avg_score'] is not None else '-'
        print('{:<25} {:<10} {:<12} {:<14} {:<10} {:<12} \${:<.2f}'.format(
            r['timestamp'], r['suite'], f'{r[\"pass_rate\"]:.1%}',
            f'{r[\"passed\"]}/{r[\"total\"]}', score,
            f'{r[\"total_tokens\"]:,}', r['total_cost']))
"
}

# ---------------------------------------------------------------------------
# cmd_cross_model --results <f1> <f2> ...
# ---------------------------------------------------------------------------
cmd_cross_model() {
  local format="table"
  local -a result_files=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --results) shift; while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do result_files+=("$1"); shift; done ;;
      --format)  format="${2:?--format requires a value}"; shift 2 ;;
      -*)        echo "ERROR: Unknown option: $1" >&2; usage ;;
      *)         result_files+=("$1"); shift ;;
    esac
  done

  if [[ ${#result_files[@]} -lt 2 ]]; then
    echo "ERROR: At least two result files required for cross-model comparison" >&2
    exit 2
  fi

  "${FORGE_PYTHON:-python3}" -c "
import json, sys

files = $(printf '"%s",' "${result_files[@]}" | sed 's/,$//' | sed 's/^/[/' | sed 's/$/]/')
fmt = '${format}'

models = []
for f in files:
    try:
        data = json.load(open(f))
        env = data.get('environment', {})
        agg = data.get('results', {}).get('aggregate', {})
        qs = agg.get('quality_summary', {})
        models.append({
            'file': f,
            'model': env.get('model', 'unknown'),
            'pass_rate': agg.get('pass_rate', 0),
            'passed': agg.get('passed', 0),
            'total': agg.get('total', 0),
            'avg_score': qs.get('avg_score'),
            'total_tokens': qs.get('total_tokens', 0),
            'total_cost': qs.get('total_cost_usd', 0)
        })
    except Exception as e:
        print(f'WARNING: Could not load {f}: {e}', file=sys.stderr)

if fmt == 'json':
    print(json.dumps({'models': models}, indent=2))
else:
    print('Cross-Model Comparison')
    print('')
    print('{:<12} {:<12} {:<14} {:<10} {:<12} {:<8}'.format(
        'Model', 'Pass Rate', 'Passed/Total', 'Avg Score', 'Tokens', 'Cost'))
    print('-' * 70)
    for m in models:
        score = str(m['avg_score']) if m['avg_score'] is not None else '-'
        print('{:<12} {:<12} {:<14} {:<10} {:<12} \${:<.2f}'.format(
            m['model'], f'{m[\"pass_rate\"]:.1%}',
            f'{m[\"passed\"]}/{m[\"total\"]}', score,
            f'{m[\"total_tokens\"]:,}', m['total_cost']))
"
}

# ---------------------------------------------------------------------------
# cmd_export <result-file> --format <fmt>
# ---------------------------------------------------------------------------
cmd_export() {
  local result_file="" format=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format) format="${2:?--format requires a value}"; shift 2 ;;
      -*)       echo "ERROR: Unknown option: $1" >&2; usage ;;
      *)        result_file="$1"; shift ;;
    esac
  done

  if [[ -z "$result_file" || -z "$format" ]]; then
    echo "ERROR: result file and --format required" >&2
    exit 2
  fi

  "${FORGE_PYTHON:-python3}" -c "
import json, sys

data = json.load(open('${result_file}'))
fmt = '${format}'
tasks = data.get('results', {}).get('tasks', [])

if fmt == 'json':
    print(json.dumps(data, indent=2))
elif fmt == 'csv':
    print('id,language,difficulty,result,final_score,duration_seconds')
    for t in tasks:
        score = t.get('final_score', '')
        if score is None:
            score = ''
        print(f'{t[\"id\"]},{t[\"language\"]},{t[\"difficulty\"]},{t[\"result\"]},{score},{t.get(\"duration_seconds\", 0)}')
elif fmt == 'markdown':
    print('| Task | Language | Difficulty | Result | Score | Duration |')
    print('|------|----------|------------|--------|-------|----------|')
    for t in tasks:
        score = t.get('final_score', '-') or '-'
        print(f'| {t[\"id\"]} | {t[\"language\"]} | {t[\"difficulty\"]} | {t[\"result\"]} | {score} | {t.get(\"duration_seconds\", 0)}s |')
else:
    print(f'ERROR: Unknown format: {fmt}', file=sys.stderr)
    sys.exit(1)
"
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  summary)     shift; cmd_summary "$@" ;;
  compare)     shift; cmd_compare "$@" ;;
  trend)       shift; cmd_trend "$@" ;;
  cross-model) shift; cmd_cross_model "$@" ;;
  export)      shift; cmd_export "$@" ;;
  *)           usage ;;
esac
