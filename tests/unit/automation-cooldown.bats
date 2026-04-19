#!/usr/bin/env bats
# Validates that automation_trigger_cli.py cooldown logic reads the correct timestamp field.
# (Internals live in hooks/_py/automation_trigger_cli.py after the Python port in Task 10.)

load '../helpers/test-helpers'

@test "automation-trigger _append_log writes 'timestamp' as timestamp key" {
  run grep "\"timestamp\":" $PLUGIN_ROOT/hooks/_py/automation_trigger_cli.py
  [ "$status" -eq 0 ]
}

@test "automation-trigger _last_dispatch reads 'timestamp' key" {
  run grep 'entry.get("timestamp")' $PLUGIN_ROOT/hooks/_py/automation_trigger_cli.py
  [ "$status" -eq 0 ]
}

@test "automation-trigger does not reference mismatched 'ts' key" {
  run grep "entry\[['\"]ts['\"]\]\|entry.get(['\"]ts['\"])" $PLUGIN_ROOT/hooks/_py/automation_trigger_cli.py
  [ "$status" -ne 0 ]
}

@test "automation-trigger write and read keys match" {
  # Extract the key used in the log writer (run function's entry dict)
  local write_key
  write_key=$(grep -o '"timestamp"\|"ts"' $PLUGIN_ROOT/hooks/_py/automation_trigger_cli.py | head -1)

  # Extract the key used in the cooldown reader (_last_dispatch)
  local read_key
  read_key=$(sed -n "/_last_dispatch/,/return last/p" $PLUGIN_ROOT/hooks/_py/automation_trigger_cli.py | grep -oE '"timestamp"|"ts"' | head -1)

  echo "Write key: $write_key, Read key: $read_key"
  [ "$write_key" = "$read_key" ]
}
