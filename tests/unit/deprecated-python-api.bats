#!/usr/bin/env bats
# Ensures no script uses deprecated Python datetime APIs without a modern-API fallback.

load '../helpers/test-helpers'

# Helper: count bare deprecated calls (outside except blocks)
count_bare_deprecated() {
  local pattern="$1"
  shift
  local violations=0
  for f in "$@"; do
    [ -f "$f" ] || continue
    while IFS= read -r match; do
      local linenum
      linenum=$(echo "$match" | cut -d: -f1)
      # Check if this line is inside an except/else/fallback block
      # by looking at lines linenum-3 through linenum for "except" or "_utc" or "else"
      local context
      context=$(sed -n "$((linenum > 3 ? linenum - 3 : 1)),${linenum}p" "$f" 2>/dev/null)
      if ! echo "$context" | grep -qE "except|_utc.*else|if.*_utc|else:"; then
        echo "VIOLATION: $f:$linenum — bare $pattern without fallback"
        violations=$((violations + 1))
      fi
    done < <(grep -n "$pattern" "$f" 2>/dev/null || true)
  done
  echo "$violations"
}

@test "no bare utcnow() in hooks without fallback" {
  local result
  result=$(count_bare_deprecated "utcnow()" $PLUGIN_ROOT/hooks/*.sh)
  local count
  count=$(echo "$result" | tail -1)
  if [ "$count" -gt 0 ]; then
    echo "$result"
  fi
  [ "$count" -eq 0 ]
}

@test "no bare utcnow() in shared scripts without fallback" {
  local result
  result=$(count_bare_deprecated "utcnow()" $PLUGIN_ROOT/shared/forge-event.sh $PLUGIN_ROOT/shared/forge-state.sh $PLUGIN_ROOT/shared/forge-state-write.sh $PLUGIN_ROOT/shared/forge-token-tracker.sh)
  local count
  count=$(echo "$result" | tail -1)
  if [ "$count" -gt 0 ]; then
    echo "$result"
  fi
  [ "$count" -eq 0 ]
}

@test "no bare utcfromtimestamp() anywhere without fallback" {
  local result
  result=$(count_bare_deprecated "utcfromtimestamp(" $PLUGIN_ROOT/hooks/*.sh $PLUGIN_ROOT/shared/*.sh)
  local count
  count=$(echo "$result" | tail -1)
  if [ "$count" -gt 0 ]; then
    echo "$result"
  fi
  [ "$count" -eq 0 ]
}
