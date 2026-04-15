#!/usr/bin/env bats
load '../helpers/test-helpers'

@test "session-start warns on bash < 4" {
  run bash -c "
    BASH_VERSINFO=(3 2 57)
    FORGE_OS='darwin'
    if [[ \"\${BASH_VERSINFO[0]:-0}\" -lt 4 ]]; then
      echo \"WARNING: Bash \${BASH_VERSION} detected. Forge check engine L1-L3 disabled.\"
      case \"\$FORGE_OS\" in
        darwin) echo '  Fix: brew install bash' ;;
        *)      echo '  Fix: Install bash 4.0+ via your package manager' ;;
      esac
    fi
  "
  assert_success
  assert_output --partial 'WARNING: Bash'
  assert_output --partial 'L1-L3 disabled'
  assert_output --partial 'brew install bash'
}

@test "session-start no warning on bash >= 4" {
  run bash -c "
    BASH_VERSINFO=(5 2 0)
    if [[ \"\${BASH_VERSINFO[0]:-0}\" -lt 4 ]]; then
      echo 'WARNING'
    fi
  "
  assert_success
  refute_output --partial 'WARNING'
}
