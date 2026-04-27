#!/usr/bin/env bats
#
# Phase 4 injection format contract: catches accidental drift in the
# markdown block emitted by hooks._py.learnings_format.render.

setup() {
  export PYTHONPATH="$BATS_TEST_DIRNAME/../.."
}

@test "render emits stable ## Relevant Learnings header" {
  run python -c "
from hooks._py.learnings_format import render
from hooks._py.learnings_selector import LearningItem
items = [LearningItem(
    id='spring-tx-scope-leak',
    source_path='shared/learnings/spring-persistence.md',
    body='Persistence layer tends to leak @Transactional boundaries.',
    base_confidence=0.82,
    confidence_now=0.82,
    half_life_days=30,
    applied_count=3,
    last_applied='2026-04-18T14:22:33Z',
    applies_to=('implementer',),
    domain_tags=('spring', 'persistence'),
    archived=False,
)]
print(render(items), end='')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Relevant Learnings (from prior runs)"* ]]
  [[ "$output" == *"[confidence 0.82, 3× applied]"* ]]
  [[ "$output" == *"shared/learnings/spring-persistence.md"* ]]
  [[ "$output" == *"Decay: 30d half-life, last applied 2026-04-18"* ]]
}

@test "render truncates body at 300 chars on whitespace" {
  long=$(python -c "print('word ' * 80, end='')")
  run python -c "
from hooks._py.learnings_format import render
from hooks._py.learnings_selector import LearningItem
body = 'word ' * 80
items = [LearningItem(id='big', source_path='x.md', body=body,
    base_confidence=0.6, confidence_now=0.6, half_life_days=30,
    applied_count=0, last_applied=None, applies_to=('implementer',),
    domain_tags=(), archived=False)]
out = render(items)
# body line ends with ellipsis
print('ELLIPSIS' if '…' in out else 'NO', end='')
print(' LEN:', len(out))
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ELLIPSIS"* ]]
}

@test "render omits applied N× when applied_count == 0" {
  run python -c "
from hooks._py.learnings_format import render
from hooks._py.learnings_selector import LearningItem
items = [LearningItem(id='new', source_path='x.md', body='body',
    base_confidence=0.7, confidence_now=0.7, half_life_days=30,
    applied_count=0, last_applied=None, applies_to=('implementer',),
    domain_tags=(), archived=False)]
print(render(items), end='')
"
  [[ "$output" != *"× applied"* ]]
  [[ "$output" != *"last applied"* ]]
}

@test "render emits empty string for empty input" {
  run python -c "from hooks._py.learnings_format import render; print(render([]), end='')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "render hard-caps at 6 items" {
  run python -c "
from hooks._py.learnings_format import render
from hooks._py.learnings_selector import LearningItem
items = [LearningItem(id=f'id-{n}', source_path='x.md', body='b',
    base_confidence=0.7, confidence_now=0.7, half_life_days=30,
    applied_count=0, last_applied=None, applies_to=('implementer',),
    domain_tags=(), archived=False) for n in range(10)]
out = render(items)
import re
print(len(re.findall(r'^\d+\.\s', out, flags=re.MULTILINE)))
"
  [ "$output" = "6" ]
}
