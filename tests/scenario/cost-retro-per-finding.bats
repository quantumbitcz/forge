#!/usr/bin/env bats
load '../helpers/test-helpers'

_cpaf() {
  python3 -c "
import json, sys, statistics
from collections import defaultdict
st = json.load(open(sys.argv[1]))
findings = st['findings']
actionable = [f for f in findings if f['severity'] in ('CRITICAL','WARNING')]
if not actionable:
    print('GATE_SKIP'); sys.exit(0)
# Cost per agent at Sonnet pricing (3/15 per MTok) or Opus (5/25).
PRICE = {'sonnet':(3.0,15.0),'opus':(5.0,25.0),'haiku':(1.0,5.0)}
costs = {}
for a, d in st['tokens']['by_agent'].items():
    pi, po = PRICE.get(d['model'], PRICE['sonnet'])
    costs[a] = d['input']*pi/1e6 + d['output']*po/1e6
# Unique actionable per reviewer.
per_rev = defaultdict(int)
for f in actionable:
    per_rev[f['agent']] += 1
cpaf = {a: costs[a]/per_rev[a] for a in per_rev}
if not cpaf:
    print('NO_REVIEWERS_WITH_FINDINGS'); sys.exit(0)
med = statistics.median(cpaf.values())
flagged = [a for a, c in cpaf.items() if c > 3 * med]
print('MEDIAN', round(med, 4), 'FLAGGED', ','.join(sorted(flagged)) or 'none')
" "$1"
}

@test "clean run: no reviewer flagged regardless of cost (AC-611 carve-out)" {
  run _cpaf "$PLUGIN_ROOT/tests/fixtures/retro-cost-scenarios/clean-run.json"
  assert_success
  assert_output "GATE_SKIP"
}

@test "dirty run: flagging engages only when peer cohort has >=1 CRITICAL/WARNING" {
  run _cpaf "$PLUGIN_ROOT/tests/fixtures/retro-cost-scenarios/dirty-run.json"
  assert_success
  # fg-411 had zero findings even though cohort was dirty; fg-410 had 2,
  # fg-412 had 1. fg-411 must NOT appear in flagged.
  refute_output -p "fg-411-security-reviewer"
}
