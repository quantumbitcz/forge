#!/usr/bin/env bats
# Skill-consolidation structural guards (post-B12).
# Locks in the consolidated 3-skill surface and forbids the 28 retired names.

load ../lib/module-lists.bash

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "skill count is exactly MIN_SKILLS (3)" {
  actual=$(ls -d "$PLUGIN_ROOT"/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
  [ "$actual" -eq 3 ]
}

@test "the three expected skills exist with SKILL.md" {
  # Source of truth: EXPECTED_SKILL_NAMES from tests/lib/module-lists.bash
  for name in "${EXPECTED_SKILL_NAMES[@]}"; do
    [ -f "$PLUGIN_ROOT/skills/$name/SKILL.md" ] || \
      { echo "MISSING: skills/$name/SKILL.md"; return 1; }
  done
}

@test "no retired skill directory exists" {
  retired=(
    forge-abort forge-automation forge-bootstrap forge-commit
    forge-compress forge-config forge-deploy forge-docs-generate
    forge-fix forge-graph forge-handoff forge-help forge-history
    forge-init forge-insights forge-migration forge-playbook-refine
    forge-playbooks forge-profile forge-recover forge-review forge-run
    forge-security-audit forge-shape forge-sprint forge-status
    forge-tour forge-verify
  )
  for name in "${retired[@]}"; do
    [ ! -e "$PLUGIN_ROOT/skills/$name" ] || \
      { echo "STILL PRESENT: skills/$name"; return 1; }
  done
}

@test "/forge has 11 subcommand sections" {
  count=$(grep -c '^### Subcommand: ' "$PLUGIN_ROOT/skills/forge/SKILL.md")
  [ "$count" -eq 11 ]
}

@test "/forge-admin has 9 subcommand sections" {
  count=$(grep -c '^### Subcommand: ' "$PLUGIN_ROOT/skills/forge-admin/SKILL.md")
  [ "$count" -eq 9 ]
}

@test "/forge-ask has 6 subcommand sections (incl default)" {
  count=$(grep -c '^### Subcommand: ' "$PLUGIN_ROOT/skills/forge-ask/SKILL.md")
  [ "$count" -eq 6 ]
}

@test "/forge frontmatter description matches spec §1" {
  grep -q 'Universal entry for the forge pipeline' "$PLUGIN_ROOT/skills/forge/SKILL.md"
  grep -q 'Auto-bootstraps on first run' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "/forge-admin frontmatter description matches spec §1" {
  grep -q 'Manage forge state and configuration' "$PLUGIN_ROOT/skills/forge-admin/SKILL.md"
}

@test "/forge-ask frontmatter description matches spec §1" {
  grep -q 'Query forge state, codebase knowledge' "$PLUGIN_ROOT/skills/forge-ask/SKILL.md"
}

@test "/forge-ask allowed-tools is read-only (no Write, no Edit)" {
  ! grep -E "^allowed-tools:.*\bWrite\b" "$PLUGIN_ROOT/skills/forge-ask/SKILL.md"
  ! grep -E "^allowed-tools:.*\bEdit\b" "$PLUGIN_ROOT/skills/forge-ask/SKILL.md"
}

@test "/forge-admin graph query enforces read-only Cypher" {
  grep -qE 'CREATE \| MERGE \| DELETE \| SET \| REMOVE \| DROP' "$PLUGIN_ROOT/skills/forge-admin/SKILL.md"
}

@test "callsite allowlist file exists" {
  [ -f "$PLUGIN_ROOT/tests/structural/skill-references-allowlist.txt" ]
}

@test "no retired skill name appears outside the allowlist (AC-S005)" {
  cd "$PLUGIN_ROOT"
  # Path-collision-safe matching:
  #   HEAD: the leading `/` must be a slash-command prefix, not a path
  #         separator. Require it to follow start-of-line, whitespace, or a
  #         delimiting punctuation char (` `\``,`(`,`,`,`,`,`...) — never an
  #         identifier or path char.
  #   TAIL: the retired name must NOT be followed by `-`, `.`, `/`, or another
  #         word character (which would make it a longer identifier or
  #         filesystem path). `\b` alone is insufficient because `-` is a word
  #         boundary in POSIX regex, so `/forge-config\b` would falsely match
  #         `/forge-config-schema.json`. The negative-class-or-EOL tail forces
  #         a true terminator.
  local HEAD='(^|[^a-zA-Z0-9._/-])'
  local TAIL='([^a-zA-Z0-9._/-]|$)'
  stragglers=$(grep -rnE "${HEAD}/forge-init$TAIL|${HEAD}/forge-run$TAIL|${HEAD}/forge-fix$TAIL|${HEAD}/forge-shape$TAIL|${HEAD}/forge-sprint$TAIL|${HEAD}/forge-review$TAIL|${HEAD}/forge-verify$TAIL|${HEAD}/forge-deploy$TAIL|${HEAD}/forge-commit$TAIL|${HEAD}/forge-migration$TAIL|${HEAD}/forge-bootstrap$TAIL|${HEAD}/forge-docs-generate$TAIL|${HEAD}/forge-security-audit$TAIL|${HEAD}/forge-status$TAIL|${HEAD}/forge-history$TAIL|${HEAD}/forge-insights$TAIL|${HEAD}/forge-profile$TAIL|${HEAD}/forge-tour$TAIL|${HEAD}/forge-help$TAIL|${HEAD}/forge-recover$TAIL|${HEAD}/forge-abort$TAIL|${HEAD}/forge-config$TAIL|${HEAD}/forge-handoff$TAIL|${HEAD}/forge-automation$TAIL|${HEAD}/forge-playbooks$TAIL|${HEAD}/forge-playbook-refine$TAIL|${HEAD}/forge-compress$TAIL|${HEAD}/forge-graph$TAIL" . 2>/dev/null \
    --include='*.md' --include='*.json' --include='*.py' --include='*.yml' --include='*.yaml' --include='*.bats' --include='*.sh' \
    | awk -F: '{print $1}' \
    | sort -u \
    | sed 's|^\./||' \
    | while read -r path; do
        if ! grep -qFx "$path" tests/structural/skill-references-allowlist.txt; then
          echo "$path"
        fi
      done)
  if [ -n "$stragglers" ]; then
    echo "Stragglers (not in allowlist):"
    echo "$stragglers"
    return 1
  fi
}
