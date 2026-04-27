#!/usr/bin/env bats
#
# AC2: hooks/_py/memory_decay.py is the SINGLE module that computes the
# Ebbinghaus curve. This grep flags any other file that imports or
# recomputes the curve inline.

@test "no other module computes the decay curve" {
  repo_root="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    grep -RE 'math\\.pow\\s*\\(\\s*2\\.0|math\\.exp\\s*\\(\\s*-' \
         --include='*.py' \
         \"$repo_root\" \
         | grep -v 'hooks/_py/memory_decay\\.py' \
         | grep -v 'tests/unit/memory_decay' \
         | grep -v 'tests/unit/test_learnings_decay' \
         | grep -v '__pycache__'
  "
  [ -z "$output" ] || {
    echo "decay math found outside memory_decay.py:"
    echo "$output"
    false
  }
}

@test "no other module uses 'half_life' as a computation variable" {
  repo_root="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    grep -RE '(half_life|half-life)' --include='*.py' \"$repo_root\" \
      | grep -v 'hooks/_py/memory_decay\\.py' \
      | grep -v 'hooks/_py/learnings_selector\\.py' \
      | grep -v 'hooks/_py/learnings_io\\.py' \
      | grep -v 'hooks/_py/learnings_format\\.py' \
      | grep -v 'hooks/_py/learnings_writeback\\.py' \
      | grep -v 'hooks/_py/learnings_markers\\.py' \
      | grep -v 'tests/' \
      | grep -E 'math\\.|/=|\\*=|\\+=|-=|2\\.0|\\*\\*' \
  "
  [ -z "$output" ] || {
    echo "half_life computation found outside sanctioned modules:"
    echo "$output"
    false
  }
}
