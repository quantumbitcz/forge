#!/usr/bin/env bash
# tracking-ops.sh — Kanban ticket CRUD operations for forge tracking.
# Source this file to use the functions below.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/tracking-ops.sh"
#
# All functions follow the same convention:
#   - First argument is tracking_dir (absolute path to .forge/tracking/)
#   - Return values are printed to stdout
#   - Errors print to stderr and return non-zero

set -euo pipefail

# Source platform helpers for OS detection and portable utilities.
# Resolve relative to this script's location so it works when sourced from
# any directory.
_TRACKING_OPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../platform.sh
source "${_TRACKING_OPS_DIR}/../platform.sh"

# ── Status directory names ────────────────────────────────────────────────────

# shellcheck disable=SC1010  # 'done' is an array element, not the loop keyword
readonly TRACKING_STATUSES=(backlog in-progress review "done")

# ── Portable in-place sed ─────────────────────────────────────────────────────
#
# BSD sed (macOS) requires an explicit empty string: sed -i ''
# GNU sed (Linux) does not accept -i '' — it needs just: sed -i
# We use FORGE_OS (set by platform.sh) to pick the right form.

portable_sed_i() {
  if [[ "${FORGE_OS:-}" == "darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Escape a string for safe use as a sed replacement value.
# Handles: backslash, pipe (our delimiter), and ampersand.
_sed_escape_replacement() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

# ── slugify <title> [max_len] ─────────────────────────────────────────────────
#
# Convert a human-readable title into a URL/filename-safe kebab-case slug.
#   1. Lowercase
#   2. Replace runs of non-alphanumeric characters with a single hyphen
#   3. Strip leading/trailing hyphens
#   4. Truncate to max_len (default 40), stripping a trailing partial word
#
# Prints the slug to stdout.

slugify() {
  local title="${1:?slugify requires a title}"
  local max_len="${2:-40}"

  local slug
  # Lowercase — use tr for portability (bash 3.2 on macOS does not support ${var,,})
  slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')"
  # Replace any sequence of characters that is NOT a-z or 0-9 with a hyphen.
  # Use -E (extended regex) so + works on both BSD sed (macOS) and GNU sed (Linux).
  slug="$(printf '%s' "$slug" | sed -E 's/[^a-z0-9]+/-/g')"
  # Strip leading/trailing hyphens
  slug="${slug#-}"
  slug="${slug%-}"

  # Truncate at max_len, avoiding a split in the middle of a word segment
  if (( ${#slug} > max_len )); then
    slug="${slug:0:$max_len}"
    # Strip trailing partial word (remove everything after the last hyphen if present)
    if [[ "$slug" == *-* ]]; then
      slug="${slug%-*}"
    fi
  fi

  # Final safety: strip any remaining trailing hyphen
  slug="${slug%-}"

  printf '%s' "$slug"
}

# ── iso_now ───────────────────────────────────────────────────────────────────
#
# Print the current UTC timestamp in ISO 8601 format: YYYY-MM-DDThh:mm:ssZ

iso_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# ── init_counter <tracking_dir> [prefix] ─────────────────────────────────────
#
# Create counter.json in tracking_dir with {"next":1,"prefix":"<PREFIX>"}.
# Does nothing if counter.json already exists.
# Default prefix: FG

init_counter() {
  local tracking_dir="${1:?init_counter requires tracking_dir}"
  local prefix="${2:-FG}"

  local counter_file="${tracking_dir}/counter.json"
  if [[ -f "$counter_file" ]]; then
    return 0
  fi

  mkdir -p "$tracking_dir"
  printf '{"next":1,"prefix":"%s"}\n' "$prefix" > "$counter_file"
}

# ── next_id <tracking_dir> ────────────────────────────────────────────────────
#
# Read counter.json, format as {PREFIX}-{NNN} (3-digit zero-padded for < 1000,
# no padding for >= 1000), increment the counter, and print the ID to stdout.

next_id() {
  local tracking_dir="${1:?next_id requires tracking_dir}"
  local counter_file="${tracking_dir}/counter.json"

  if [[ ! -f "$counter_file" ]]; then
    echo "next_id: counter.json not found in ${tracking_dir}" >&2
    return 1
  fi

  # Parse with python (via FORGE_PYTHON from platform.sh)
  local prefix next
  prefix="$("$FORGE_PYTHON" -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['prefix'])" "$counter_file")"
  next="$("$FORGE_PYTHON" -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['next'])" "$counter_file")"

  # Format: zero-pad to 3 digits for 1-999, no padding for 1000+
  local formatted_num
  if (( next < 1000 )); then
    formatted_num="$(printf '%03d' "$next")"
  else
    formatted_num="$next"
  fi

  local ticket_id="${prefix}-${formatted_num}"

  # Increment counter atomically (write new JSON)
  local new_next=$(( next + 1 ))
  "$FORGE_PYTHON" -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
d['next'] = int(sys.argv[2])
with open(sys.argv[1], 'w') as f:
    json.dump(d, f)
    f.write('\n')
" "$counter_file" "$new_next"

  printf '%s' "$ticket_id"
}

# ── create_ticket <tracking_dir> <title> <type> <priority> [target_status] ───
#
# Create a new ticket file in the given status directory (default: backlog).
# Prints the new ticket ID to stdout.
#
# Arguments:
#   tracking_dir   — path to .forge/tracking/
#   title          — human-readable title
#   type           — feature | bugfix | refactor | chore
#   priority       — critical | high | medium | low
#   target_status  — backlog (default) | in-progress | review | done

create_ticket() {
  local tracking_dir="${1:?create_ticket requires tracking_dir}"
  local title="${2:?create_ticket requires title}"
  local type="${3:?create_ticket requires type}"
  local priority="${4:?create_ticket requires priority}"
  local target_status="${5:-backlog}"

  local status_dir="${tracking_dir}/${target_status}"
  if [[ ! -d "$status_dir" ]]; then
    echo "create_ticket: unknown status '${target_status}'" >&2
    return 1
  fi

  local ticket_id
  ticket_id="$(next_id "$tracking_dir")"

  local slug
  slug="$(slugify "$title")"

  local filename="${ticket_id}-${slug}.md"
  local filepath="${status_dir}/${filename}"
  local now
  now="$(iso_now)"

  # Escape double quotes in title for safe YAML embedding
  local safe_title="${title//\"/\\\"}"
  cat > "$filepath" <<TICKET
---
id: ${ticket_id}
title: "${safe_title}"
type: ${type}
status: ${target_status}
priority: ${priority}
branch: ""
created: "${now}"
updated: "${now}"
linear_id: ""
spec: ""
pr: ""
---

## Description

<!-- Describe what needs to be done. -->

## Acceptance Criteria

- [ ] (define criteria)

## Stories

- [ ] (define sub-tasks)

## Activity Log

- ${now} — created (${target_status})
TICKET

  printf '%s' "$ticket_id"
}

# ── find_ticket <tracking_dir> <ticket_id> ────────────────────────────────────
#
# Search all status directories for a ticket with the given ID.
# Prints the absolute path to stdout, or exits with status 1 if not found.

find_ticket() {
  local tracking_dir="${1:?find_ticket requires tracking_dir}"
  local ticket_id="${2:?find_ticket requires ticket_id}"

  local st_dir st_name
  for st_name in "${TRACKING_STATUSES[@]}"; do
    st_dir="${tracking_dir}/${st_name}"
    [[ -d "$st_dir" ]] || continue
    local f
    for f in "${st_dir}/${ticket_id}"-*.md "${st_dir}/${ticket_id}.md"; do
      [[ -f "$f" ]] && printf '%s' "$f" && return 0
    done
  done

  echo "find_ticket: ticket '${ticket_id}' not found in ${tracking_dir}" >&2
  return 1
}

# ── move_ticket <tracking_dir> <ticket_id> <new_status> ──────────────────────
#
# Move a ticket file to the new status directory.
# Updates the `status` and `updated` frontmatter fields.
# Appends a line to the Activity Log section.

move_ticket() {
  local tracking_dir="${1:?move_ticket requires tracking_dir}"
  local ticket_id="${2:?move_ticket requires ticket_id}"
  local new_status="${3:?move_ticket requires new_status}"

  local new_dir="${tracking_dir}/${new_status}"
  if [[ ! -d "$new_dir" ]]; then
    echo "move_ticket: unknown status '${new_status}'" >&2
    return 1
  fi

  local current_path
  current_path="$(find_ticket "$tracking_dir" "$ticket_id")"

  local filename
  filename="$(basename "$current_path")"
  local new_path="${new_dir}/${filename}"

  local now
  now="$(iso_now)"

  # Update status field in frontmatter
  local safe_status
  safe_status="$(_sed_escape_replacement "$new_status")"
  portable_sed_i "s|^status: .*|status: ${safe_status}|" "$current_path"
  # Update updated field in frontmatter
  portable_sed_i "s|^updated: .*|updated: \"${now}\"|" "$current_path"

  # Append to Activity Log section
  printf '\n- %s — moved to %s\n' "$now" "$new_status" >> "$current_path"

  # Move file to new status dir
  mv "$current_path" "$new_path"
}

# ── update_ticket_field <tracking_dir> <ticket_id> <field> <value> ────────────
#
# Update a single frontmatter field in the ticket file.
# Handles fields with quoted values (branch, created, updated, linear_id, spec, pr)
# and unquoted values (id, title, type, status, priority).

update_ticket_field() {
  local tracking_dir="${1:?update_ticket_field requires tracking_dir}"
  local ticket_id="${2:?update_ticket_field requires ticket_id}"
  local field="${3:?update_ticket_field requires field}"
  local value="${4:-}"  # allow empty value

  local ticket_path
  ticket_path="$(find_ticket "$tracking_dir" "$ticket_id")"

  # Determine whether this field uses quoted values in the frontmatter
  local quoted_fields=("branch" "created" "updated" "linear_id" "spec" "pr")
  local use_quotes=0
  local qf
  for qf in "${quoted_fields[@]}"; do
    if [[ "$field" == "$qf" ]]; then
      use_quotes=1
      break
    fi
  done

  local safe_value
  safe_value="$(_sed_escape_replacement "$value")"
  if (( use_quotes )); then
    portable_sed_i "s|^${field}: .*|${field}: \"${safe_value}\"|" "$ticket_path"
  else
    portable_sed_i "s|^${field}: .*|${field}: ${safe_value}|" "$ticket_path"
  fi

  # Also update the `updated` timestamp
  local now
  now="$(iso_now)"
  portable_sed_i "s|^updated: .*|updated: \"${now}\"|" "$ticket_path"
}

# ── generate_board <tracking_dir> ────────────────────────────────────────────
#
# Scan all status directories and generate board.md — a markdown table
# sorted by status order (backlog → in-progress → review → done) then by ID.

generate_board() {
  local tracking_dir="${1:?generate_board requires tracking_dir}"

  local board_file="${tracking_dir}/board.md"
  local now
  now="$(iso_now)"

  # Parse all frontmatter fields from a ticket file using python (via FORGE_PYTHON).
  # Usage: _parse_ticket_field <file> <field>
  # Strips surrounding quotes for quoted fields.
  _parse_ticket_field() {
    local _file="$1" _field="$2"
    "$FORGE_PYTHON" -c "
import sys
lines = open(sys.argv[1]).readlines()
in_fm = False
field = sys.argv[2] + ':'
for line in lines:
    if line.strip() == '---':
        in_fm = not in_fm
        continue
    if in_fm and line.startswith(field):
        val = line.split(':', 1)[1].strip().strip('\"')
        print(val)
        break
" "$_file" "$_field" 2>/dev/null || true
  }

  {
    printf '# Kanban Board\n\n'
    printf '_Generated: %s_\n\n' "$now"
    printf '| ID | Title | Type | Priority | Status | Branch | PR |\n'
    printf '|----|-------|------|----------|--------|--------|----|'

    local col_status
    for col_status in "${TRACKING_STATUSES[@]}"; do
      local col_dir="${tracking_dir}/${col_status}"
      [[ -d "$col_dir" ]] || continue

      # Iterate sorted ticket files; nullglob-style: skip if no matches
      local ticket_file
      while IFS= read -r ticket_file; do
        [[ -f "$ticket_file" ]] || continue

        local t_id t_title t_type t_priority t_status t_branch t_pr
        t_id="$(_parse_ticket_field     "$ticket_file" "id")"
        t_title="$(_parse_ticket_field  "$ticket_file" "title")"
        t_type="$(_parse_ticket_field   "$ticket_file" "type")"
        t_priority="$(_parse_ticket_field "$ticket_file" "priority")"
        t_status="$(_parse_ticket_field "$ticket_file" "status")"
        t_branch="$(_parse_ticket_field "$ticket_file" "branch")"
        t_pr="$(_parse_ticket_field     "$ticket_file" "pr")"

        printf '\n| %s | %s | %s | %s | %s | %s | %s |' \
          "${t_id}" "${t_title}" "${t_type}" "${t_priority}" \
          "${t_status}" "${t_branch}" "${t_pr}"
      done < <(find "$col_dir" -maxdepth 1 -name '*.md' | sort)
    done

    printf '\n'
  } > "$board_file"
}
