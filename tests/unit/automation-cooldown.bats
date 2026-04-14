#!/usr/bin/env bats
# Validates that automation-trigger.sh cooldown logic reads the correct timestamp field.

load '../helpers/test-helpers'

@test "automation-trigger _log_entry writes 'ts' as timestamp key" {
  run grep "'ts':" hooks/automation-trigger.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"'ts'"* ]]
}

@test "automation-trigger last_dispatch_time reads 'ts' key" {
  run grep "entry\['ts'\]" hooks/automation-trigger.sh
  [ "$status" -eq 0 ]
}

@test "automation-trigger does not reference entry['timestamp']" {
  run grep "entry\['timestamp'\]" hooks/automation-trigger.sh
  [ "$status" -ne 0 ]
}

@test "automation-trigger write and read keys match" {
  # Extract the key used in the log writer (_log_entry function)
  local write_key
  write_key=$(grep -o "'ts'\|'timestamp'" hooks/automation-trigger.sh | head -1)

  # Extract the key used in the cooldown reader (last_dispatch_time function)
  local read_key
  read_key=$(sed -n "/last_dispatch_time/,/return None/p" hooks/automation-trigger.sh | grep -o "'ts'\|'timestamp'" | head -1)

  echo "Write key: $write_key, Read key: $read_key"
  [ "$write_key" = "$read_key" ]
}
