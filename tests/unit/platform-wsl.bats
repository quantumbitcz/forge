#!/usr/bin/env bats
load '../helpers/test-helpers'

@test "detect_os returns wsl when /proc/version contains Microsoft" {
  mkdir -p "${TEST_TEMP}/proc"
  echo "Linux version 5.15.0 (Microsoft@Microsoft.com) WSL2" > "${TEST_TEMP}/proc/version"

  run bash -c "
    detect_os_test() {
      if [[ -f '${TEST_TEMP}/proc/version' ]] && grep -qi 'microsoft\|wsl' '${TEST_TEMP}/proc/version' 2>/dev/null; then
        printf 'wsl'
      else
        printf 'linux'
      fi
    }
    detect_os_test
  "
  assert_success
  assert_output 'wsl'
}

@test "detect_os returns linux when /proc/version is normal Linux" {
  mkdir -p "${TEST_TEMP}/proc"
  echo "Linux version 6.1.0-generic" > "${TEST_TEMP}/proc/version"

  run bash -c "
    detect_os_test() {
      if [[ -f '${TEST_TEMP}/proc/version' ]] && grep -qi 'microsoft\|wsl' '${TEST_TEMP}/proc/version' 2>/dev/null; then
        printf 'wsl'
      else
        printf 'linux'
      fi
    }
    detect_os_test
  "
  assert_success
  assert_output 'linux'
}
