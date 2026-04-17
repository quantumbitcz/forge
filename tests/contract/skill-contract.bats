#!/usr/bin/env bats

# Skill contract assertions — enforces shared/skill-contract.md

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PLUGIN_ROOT
}

@test "every SKILL.md description starts with [read-only] or [writes]" {
  local bad=0
  for skill_md in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    local desc
    desc=$(awk '/^description:/{sub(/^description: *"?/, ""); sub(/"?$/, ""); print; exit}' "$skill_md")
    if [[ ! "$desc" =~ ^\[read-only\] ]] && [[ ! "$desc" =~ ^\[writes\] ]]; then
      echo "BAD prefix: $skill_md → $desc"
      ((bad++))
    fi
  done
  [ "$bad" -eq 0 ]
}

@test "every SKILL.md has a ## Flags section" {
  for skill_md in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    grep -q "^## Flags" "$skill_md" || { echo "Missing Flags: $skill_md"; return 1; }
  done
}

@test "every SKILL.md has a ## Exit codes section or reference" {
  for skill_md in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    grep -qE "^## Exit codes|See shared/skill-contract.md" "$skill_md" \
      || { echo "Missing Exit codes: $skill_md"; return 1; }
  done
}

@test "every SKILL.md lists --help in Flags" {
  for skill_md in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    awk '/^## Flags/{flag=1; next} /^## /{flag=0} flag' "$skill_md" \
      | grep -q -- "--help" || { echo "Missing --help: $skill_md"; return 1; }
  done
}

@test "writes skills list --dry-run in Flags" {
  # Writes skills per shared/skill-contract.md §4
  local writes=(forge-abort forge-automation forge-bootstrap forge-commit \
                forge-compress forge-config forge-deep-health forge-deploy \
                forge-docs-generate forge-fix forge-graph-init forge-graph-rebuild \
                forge-init forge-migration forge-playbook-refine forge-recover \
                forge-review forge-run forge-shape forge-sprint)
  for s in "${writes[@]}"; do
    local f="$PLUGIN_ROOT/skills/$s/SKILL.md"
    [ -f "$f" ] || { echo "Missing skill: $s"; return 1; }
    awk '/^## Flags/{flag=1; next} /^## /{flag=0} flag' "$f" \
      | grep -q -- "--dry-run" || { echo "Missing --dry-run in $s"; return 1; }
  done
}

@test "read-only skills list --json in Flags" {
  local readonly_skills=(forge-ask forge-codebase-health forge-config-validate \
                         forge-graph-debug forge-graph-query forge-graph-status \
                         forge-help forge-history forge-insights forge-playbooks \
                         forge-profile forge-security-audit forge-status \
                         forge-tour forge-verify)
  for s in "${readonly_skills[@]}"; do
    local f="$PLUGIN_ROOT/skills/$s/SKILL.md"
    [ -f "$f" ] || { echo "Missing skill: $s"; return 1; }
    awk '/^## Flags/{flag=1; next} /^## /{flag=0} flag' "$f" \
      | grep -q -- "--json" || { echo "Missing --json in $s"; return 1; }
  done
}

@test "exactly 35 skill directories exist" {
  local count
  count=$(find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$count" -eq 35 ]
}

@test "no dangling references to deleted skills" {
  local deleted=(forge-diagnose forge-repair-state forge-reset forge-resume \
                 forge-rollback forge-caveman forge-compression-help)
  local bad=0
  for name in "${deleted[@]}"; do
    local hits
    # Exempt:
    #   - DEPRECATIONS.md, CHANGELOG.md — migration history
    #   - skills/forge-recover/SKILL.md, skills/forge-compress/SKILL.md — legitimately
    #     document the /old-skill → /new-skill migration tables
    #   - tests/contract/skill-contract.bats — this file lists the deleted names as
    #     a negative-check array
    hits=$(grep -rln "/$name[^a-z-]" \
             "$PLUGIN_ROOT/README.md" "$PLUGIN_ROOT/CLAUDE.md" \
             "$PLUGIN_ROOT/shared" "$PLUGIN_ROOT/skills" \
             "$PLUGIN_ROOT/tests" "$PLUGIN_ROOT/hooks" 2>/dev/null \
           | grep -v "DEPRECATIONS.md" \
           | grep -v "CHANGELOG.md" \
           | grep -v "skills/forge-recover/SKILL.md" \
           | grep -v "skills/forge-compress/SKILL.md" \
           | grep -v "tests/contract/skill-contract.bats" || true)
    if [ -n "$hits" ]; then
      echo "Dangling reference to /$name in:"
      echo "$hits"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}
