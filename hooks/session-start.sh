#!/usr/bin/env bash
# SessionStart event hook: Detects forge project, activates caveman mode,
# displays pipeline status, and surfaces unacknowledged alerts.
# Best-effort — fails silently. Always exits 0.

# Self-enforcing timeout — mirrors hooks.json value
_HOOK_TIMEOUT="${FORGE_HOOK_TIMEOUT:-3}"
if [[ "${_HOOK_TIMEOUT_ACTIVE:-}" != "1" ]]; then
  export _HOOK_TIMEOUT_ACTIVE=1
  if command -v timeout &>/dev/null; then
    timeout "$_HOOK_TIMEOUT" "$0" "$@" || true
    exit 0
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$_HOOK_TIMEOUT" "$0" "$@" || true
    exit 0
  fi
  # Fallback: background watchdog kill
  _SELF_PID=$$
  ( sleep "$_HOOK_TIMEOUT" && kill -TERM "$_SELF_PID" 2>/dev/null ) &
  _WATCHDOG_PID=$!
  trap "kill '$_WATCHDOG_PID' 2>/dev/null" EXIT
fi

(
  # --- Forge project detection ---
  # Require both .claude/forge.local.md and .forge/ to exist
  [[ -f ".claude/forge.local.md" && -d ".forge" ]] || exit 0

  # --- Bash version check ---
  if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    echo "WARNING: Bash ${BASH_VERSION} detected. Forge check engine L1-L3 disabled."
    case "${FORGE_OS:-unknown}" in
      darwin) echo "  Fix: brew install bash" ;;
      *)      echo "  Fix: Install bash 4.0+ via your package manager" ;;
    esac
  fi

  # --- Caveman mode auto-activation ---
  _caveman_mode=""
  if [[ -f ".forge/caveman-mode" ]]; then
    _caveman_mode="$(head -1 ".forge/caveman-mode" 2>/dev/null | tr -d '[:space:]')"
  else
    # Check if caveman.enabled is true in forge-config.md
    _caveman_enabled=""
    _caveman_default=""
    if [[ -f ".claude/forge-config.md" ]]; then
      _py=""
      command -v python3 &>/dev/null && _py="python3"
      [[ -z "$_py" ]] && command -v python &>/dev/null && _py="python"

      if [[ -n "$_py" ]]; then
        _caveman_enabled="$("$_py" -c "
import re, sys
try:
    content = open('.claude/forge-config.md').read()
    # Extract YAML block (between --- or from caveman: key)
    m = re.search(r'caveman:\s*\n((?:\s+\S.*\n)*)', content)
    if m:
        block = m.group(1)
        em = re.search(r'enabled:\s*(true|false)', block)
        if em:
            print(em.group(1))
        else:
            print('false')
    else:
        print('false')
except Exception:
    print('false')
" 2>/dev/null)" || _caveman_enabled="false"
        _caveman_default="$("$_py" -c "
import re, sys
try:
    content = open('.claude/forge-config.md').read()
    m = re.search(r'caveman:\s*\n((?:\s+\S.*\n)*)', content)
    if m:
        block = m.group(1)
        dm = re.search(r'default_mode:\s*(lite|full|ultra)', block)
        if dm:
            print(dm.group(1))
        else:
            print('ultra')
    else:
        print('ultra')
except Exception:
    print('ultra')
" 2>/dev/null)" || _caveman_default="ultra"
      else
        # Fallback: grep-based parsing
        _caveman_enabled="$(grep -A5 'caveman:' ".claude/forge-config.md" 2>/dev/null | grep 'enabled:' | head -1 | grep -o 'true\|false' || echo "false")"
        _caveman_default="$(grep -A5 'caveman:' ".claude/forge-config.md" 2>/dev/null | grep 'default_mode:' | head -1 | grep -oE 'lite|full|ultra' || echo "ultra")"
      fi
    fi

    if [[ "$_caveman_enabled" == "true" ]]; then
      mkdir -p ".forge" 2>/dev/null
      printf '%s' "${_caveman_default:-ultra}" > ".forge/caveman-mode"
      _caveman_mode="${_caveman_default:-ultra}"
    fi
  fi

  # --- Emit caveman compression instructions ---
  if [[ -n "$_caveman_mode" && "$_caveman_mode" != "off" ]]; then
    case "$_caveman_mode" in
      lite)
        cat <<'RULES'
[forge] OUTPUT COMPRESSION -- LITE MODE

Drop: filler (just/really/basically/simply), hedging (perhaps/might/you could consider), pleasantries (sure/certainly/I'd be happy to), restated context (as you mentioned), transition phrases (moving on to/now let's look at).
Keep: articles (a/an/the), full sentences, technical detail, code blocks, error messages verbatim.

Exceptions: Security warnings (SEC-* CRITICAL), irreversible action confirmations, AskUserQuestion content, escalation messages, and error diagnostics (BUILD_FAILURE/TEST_FAILURE/LINT_FAILURE destined for user) always use full verbosity.
RULES
        ;;
      full)
        cat <<'RULES'
[forge] OUTPUT COMPRESSION -- FULL (CAVEMAN) MODE

Drop: articles (a/an/the), filler (just/really/basically/simply), pleasantries (sure/certainly/I'd be happy to), hedging (perhaps/might/you could consider), restated context (as you mentioned/based on the requirement), transition phrases (moving on to/now let's look at).
Keep: technical terms exact, code blocks unchanged, error messages verbatim, file paths, line numbers, finding categories, severity levels.
Pattern: [subject] [action] [reason]. [next step].

Example:
  BEFORE: "I've analyzed the authentication middleware and I believe there might be a potential issue with how the session tokens are being validated."
  AFTER: "Auth middleware: session token validation skips expiry check. Fix: add isExpired() guard before verify()."

Exceptions: Security warnings (SEC-* CRITICAL), irreversible action confirmations, AskUserQuestion content, escalation messages, and error diagnostics (BUILD_FAILURE/TEST_FAILURE/LINT_FAILURE destined for user) always use full verbosity.
RULES
        ;;
      ultra)
        cat <<'RULES'
[forge] OUTPUT COMPRESSION -- ULTRA (CAVEMAN) MODE

Abbreviate: DB, auth, req/res, impl, config, fn, var, dep, pkg.
Arrows: cause -> effect. No conjunctions.
No articles. No filler. Fragments only.
Keep: code exact, technical terms exact, numbers exact.

Example:
  BEFORE: "Review done. Score 75 (CONCERNS). 2 CRITICAL, 3 WARNING."
  AFTER: "Rev: 75/CONCERNS. 2C 3W."

Exceptions: SEC-* CRITICAL, irreversible actions, AskUserQuestion, escalations, error diagnostics -> full verbosity.
RULES
        ;;
    esac
  fi

  # --- Statusline badge ---
  if [[ -n "$_caveman_mode" && "$_caveman_mode" != "off" ]]; then
    case "$_caveman_mode" in
      lite)  _badge="CAVEMAN:LITE" ;;
      full)  _badge="CAVEMAN" ;;
      ultra) _badge="CAVEMAN:ULTRA" ;;
    esac
    # Attempt statusline emission. Graceful degradation if unsupported.
    echo "[STATUS: ${_badge}]" 2>/dev/null || true
  fi

  # --- Pipeline status display ---
  if [[ -f ".forge/state.json" ]]; then
    _py=""
    command -v python3 &>/dev/null && _py="python3"
    [[ -z "$_py" ]] && command -v python &>/dev/null && _py="python"

    if [[ -n "$_py" ]]; then
      "$_py" -c "
import json, os, sys
try:
    from datetime import datetime, timezone
    _utc = timezone.utc
except ImportError:
    from datetime import datetime
    _utc = None

try:
    with open('.forge/state.json') as f:
        s = json.load(f)
except (IOError, json.JSONDecodeError, ValueError):
    sys.exit(0)

stage = s.get('story_state', 'UNKNOWN')
mode = s.get('mode', 'standard')
scores = s.get('score_history', [])
last_score = scores[-1] if scores else 'N/A'

# File modification time as last activity indicator
try:
    mtime = os.path.getmtime('.forge/state.json')
    if _utc:
        last_active = datetime.fromtimestamp(mtime, tz=_utc).strftime('%Y-%m-%d %H:%M UTC')
    else:
        last_active = datetime.utcfromtimestamp(mtime).strftime('%Y-%m-%d %H:%M UTC')
except Exception:
    last_active = 'unknown'

print('[forge] Pipeline: state={0} mode={1} score={2} last_active={3}'.format(
    stage, mode, last_score, last_active))
" 2>/dev/null || true
    fi
  fi

  # --- Unacknowledged alerts ---
  if [[ -f ".forge/alerts.json" ]]; then
    _py=""
    command -v python3 &>/dev/null && _py="python3"
    [[ -z "$_py" ]] && command -v python &>/dev/null && _py="python"

    if [[ -n "$_py" ]]; then
      "$_py" -c "
import json, sys

try:
    with open('.forge/alerts.json') as f:
        data = json.load(f)
except (IOError, json.JSONDecodeError, ValueError):
    sys.exit(0)

alerts = data.get('alerts', [])
unresolved = [a for a in alerts if not a.get('resolved', False)]
if unresolved:
    print('[forge] {0} unacknowledged alert(s):'.format(len(unresolved)))
    for a in unresolved[:3]:
        atype = a.get('type', 'UNKNOWN')
        msg = a.get('message', '')[:80]
        print('  [{0}] {1}'.format(atype, msg))
    if len(unresolved) > 3:
        print('  ... and {0} more'.format(len(unresolved) - 3))
" 2>/dev/null || true
    fi
  fi
) || true

exit 0
