#!/usr/bin/env bash
# PostToolUse hook: fires file_changed automation trigger on Edit/Write.
# Always exits 0 — never blocks the pipeline. Sub-millisecond no-op when
# .forge/ does not exist or no automations are configured.

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

{
  # Quick exit: no forge project context
  [ ! -d ".forge" ] && exit 0

  # Extract file_path from TOOL_INPUT (same JSON-then-regex as engine.sh)
  _file=""
  _py_cmd="python3"
  command -v python3 &>/dev/null || _py_cmd="python"
  _file="$( echo "${TOOL_INPUT:-}" | "$_py_cmd" -c "import json,sys; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null )" || true
  if [ -z "$_file" ]; then
    _file="$( echo "${TOOL_INPUT:-}" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"$//' )" || true
  fi

  [ -z "$_file" ] && exit 0

  # Locate the automation trigger script
  _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _trigger="${_script_dir}/automation-trigger.sh"
  [ ! -x "$_trigger" ] && exit 0

  # Fire the trigger (best-effort, background, never block)
  "$_trigger" --trigger file_changed --payload "{\"file_path\": \"$_file\"}" 2>/dev/null || true

} 2>/dev/null

exit 0
