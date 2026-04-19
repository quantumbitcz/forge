#!/usr/bin/env bats
# Validates that automation_trigger.py cooldown logic reads the correct timestamp field.
# (Internals live in hooks/_py/check_engine/automation_trigger.py after the Python port.)

load '../helpers/test-helpers'

@test "automation-trigger _log_entry writes 'ts' as timestamp key" {
  run grep "'ts':" $PLUGIN_ROOT/hooks/_py/check_engine/automation_trigger.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"'ts'"* ]]
}

@test "automation-trigger last_dispatch_time reads 'ts' key" {
  run grep "entry\['ts'\]" $PLUGIN_ROOT/hooks/_py/check_engine/automation_trigger.py
  [ "$status" -eq 0 ]
}

@test "automation-trigger does not reference entry['timestamp']" {
  run grep "entry\['timestamp'\]" $PLUGIN_ROOT/hooks/_py/check_engine/automation_trigger.py
  [ "$status" -ne 0 ]
}

@test "automation-trigger write and read keys match" {
  # Extract the key used in the log writer (_log_entry function)
  local write_key
  write_key=$(grep -o "'ts'\|'timestamp'" $PLUGIN_ROOT/hooks/_py/check_engine/automation_trigger.py | head -1)

  # Extract the key used in the cooldown reader (last_dispatch_time function)
  local read_key
  read_key=$(sed -n "/last_dispatch_time/,/return None/p" $PLUGIN_ROOT/hooks/_py/check_engine/automation_trigger.py | grep -o "'ts'\|'timestamp'" | head -1)

  echo "Write key: $write_key, Read key: $read_key"
  [ "$write_key" = "$read_key" ]
}
