# Helper to generate TOOL_INPUT JSON for hook testing

make_edit_input() {
  local file_path="${1:?file_path required}"
  local old_string="${2:-old}"
  local new_string="${3:-new}"
  printf '{"file_path":"%s","old_string":"%s","new_string":"%s"}' "$file_path" "$old_string" "$new_string"
}

make_write_input() {
  local file_path="${1:?file_path required}"
  local content="${2:-content}"
  printf '{"file_path":"%s","content":"%s"}' "$file_path" "$content"
}
