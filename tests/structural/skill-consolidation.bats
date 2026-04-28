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
  for name in forge forge-admin forge-ask; do
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
  stragglers=$(grep -rn '/forge-init\b\|/forge-run\b\|/forge-fix\b\|/forge-shape\b\|/forge-sprint\b\|/forge-review\b\|/forge-verify\b\|/forge-deploy\b\|/forge-commit\b\|/forge-migration\b\|/forge-bootstrap\b\|/forge-docs-generate\b\|/forge-security-audit\b\|/forge-status\b\|/forge-history\b\|/forge-insights\b\|/forge-profile\b\|/forge-tour\b\|/forge-help\b\|/forge-recover\b\|/forge-abort\b\|/forge-config\b\|/forge-handoff\b\|/forge-automation\b\|/forge-playbooks\b\|/forge-playbook-refine\b\|/forge-compress\b\|/forge-graph\b' . 2>/dev/null \
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
