# Forge Rename (v1.0.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the dev-pipeline plugin to forge — all files, references, agents, skills, hooks, tests, docs, marketplace — and remove all backward compatibility code. Clean break.

**Architecture:** Systematic find-and-replace organized by layer (plugin manifest → agents → skills → hooks → shared contracts → modules → tests → docs). Each task targets one logical group. Agent files are renamed on disk and their YAML frontmatter `name:` updated. Skills directories are renamed. All `.pipeline/` paths become `.forge/`. All `pl-` prefixes become `fg-`. Version reset to 1.0.0.

**Tech Stack:** Bash (file operations), markdown, JSON, YAML frontmatter, bats (tests)

**Spec:** `docs/superpowers/specs/2026-04-02-forge-redesign-design.md` — Sections 2 and 3

---

## File Structure

### Files to rename (on disk)

**21 agent files:**
```
agents/pl-010-shaper.md           → agents/fg-010-shaper.md
agents/pl-050-project-bootstrapper.md → agents/fg-050-project-bootstrapper.md
agents/pl-100-orchestrator.md     → agents/fg-100-orchestrator.md
agents/pl-130-docs-discoverer.md  → agents/fg-130-docs-discoverer.md
agents/pl-140-deprecation-refresh.md → agents/fg-140-deprecation-refresh.md
agents/pl-150-test-bootstrapper.md → agents/fg-150-test-bootstrapper.md
agents/pl-160-migration-planner.md → agents/fg-160-migration-planner.md
agents/pl-200-planner.md          → agents/fg-200-planner.md
agents/pl-210-validator.md        → agents/fg-210-validator.md
agents/pl-250-contract-validator.md → agents/fg-250-contract-validator.md
agents/pl-300-implementer.md      → agents/fg-300-implementer.md
agents/pl-310-scaffolder.md       → agents/fg-310-scaffolder.md
agents/pl-320-frontend-polisher.md → agents/fg-320-frontend-polisher.md
agents/pl-350-docs-generator.md   → agents/fg-350-docs-generator.md
agents/pl-400-quality-gate.md     → agents/fg-400-quality-gate.md
agents/pl-500-test-gate.md        → agents/fg-500-test-gate.md
agents/pl-600-pr-builder.md       → agents/fg-600-pr-builder.md
agents/pl-650-preview-validator.md → agents/fg-650-preview-validator.md
agents/pl-700-retrospective.md    → agents/fg-700-retrospective.md
agents/pl-710-feedback-capture.md → agents/fg-710-feedback-capture.md
agents/pl-720-recap.md            → agents/fg-720-recap.md
```

**7 skill directories:**
```
skills/pipeline-run/       → skills/forge-run/
skills/pipeline-init/      → skills/forge-init/
skills/pipeline-status/    → skills/forge-status/
skills/pipeline-reset/     → skills/forge-reset/
skills/pipeline-rollback/  → skills/forge-rollback/
skills/pipeline-history/   → skills/forge-history/
skills/pipeline-shape/     → skills/forge-shape/
```

**1 hook script:**
```
hooks/pipeline-checkpoint.sh → hooks/forge-checkpoint.sh
```

### Files to delete

```
tests/fixtures/state/v1.0.0-valid.json
tests/fixtures/state/v1.0.0-malformed.json
```

### Files to modify (content replacement — not renamed)

**Plugin manifest:** `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
**Hooks:** `hooks/hooks.json`
**Shared contracts:** All files in `shared/` (~48 files)
**Module templates:** 42 framework template files (21 × `local-template.md` + 21 × `pipeline-config-template.md`)
**Tests:** All `.bats` files + helper scripts (~45 files)
**Docs:** `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `.gitignore`
**Review agents:** 11 review agent files (contain `pl-` references in body text)

---

## Task 1: Rename Plugin Manifest & Marketplace

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Update plugin.json**

Replace the entire content of `.claude-plugin/plugin.json`:

```json
{
  "name": "forge",
  "version": "1.0.0",
  "description": "Autonomous 10-stage development pipeline with multi-language support, self-healing recovery, and generalized code quality checks",
  "author": {
    "name": "QuantumBit s.r.o.",
    "url": "https://github.com/quantumbitcz"
  },
  "repository": "https://github.com/quantumbitcz/forge",
  "homepage": "https://github.com/quantumbitcz/forge",
  "license": "Proprietary",
  "keywords": [
    "forge", "pipeline", "tdd", "code-review", "quality-gate", "linear",
    "kotlin", "typescript", "python", "go", "rust", "swift", "java", "c",
    "cpp", "csharp", "dart", "elixir", "php", "ruby", "scala",
    "documentation", "graph", "migration", "testing",
    "bootstrap", "code-quality", "crosscutting", "knowledge-graph"
  ],
  "category": "development"
}
```

- [ ] **Step 2: Update marketplace.json**

Replace the entire content of `.claude-plugin/marketplace.json`:

```json
{
  "name": "quantumbitcz",
  "owner": {
    "name": "QuantumBit s.r.o.",
    "url": "https://github.com/quantumbitcz"
  },
  "metadata": {
    "description": "Autonomous development pipeline with multi-language support",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "forge",
      "description": "10-stage autonomous development pipeline: Preflight, Explore, Plan, Validate, Implement (TDD), Verify, Review, Docs, Ship, Learn. 21 frameworks, 15 languages, 15 crosscutting layers, knowledge graph. Migration and bootstrap modes. Self-healing recovery and generalized code quality checks.",
      "source": "./",
      "strict": false
    }
  ]
}
```

- [ ] **Step 3: Verify JSON validity**

Run:
```bash
jq . .claude-plugin/plugin.json && jq . .claude-plugin/marketplace.json
```
Expected: Both files parse without errors. `plugin.json` shows `"name": "forge"`, `"version": "1.0.0"`. `marketplace.json` shows `"name": "forge"` in plugins array.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "refactor(plugin): rename dev-pipeline to forge in manifests"
```

---

## Task 2: Rename Agent Files on Disk + Update Frontmatter

**Files:**
- Rename: All 21 `agents/pl-*.md` → `agents/fg-*.md`
- Modify: YAML frontmatter `name:` field in each renamed file

- [ ] **Step 1: Rename all 21 agent files**

Run:
```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for f in agents/pl-*.md; do
  newname="agents/fg-${f#agents/pl-}"
  git mv "$f" "$newname"
done
```

- [ ] **Step 2: Update YAML frontmatter `name:` in each renamed file**

For each of the 21 renamed files, the `name:` field in YAML frontmatter must change from `pl-NNN-xxx` to `fg-NNN-xxx`. Run:

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for f in agents/fg-*.md; do
  old_name=$(basename "$f" .md | sed 's/^fg-/pl-/')
  new_name=$(basename "$f" .md)
  sed -i '' "s/^name: ${old_name}$/name: ${new_name}/" "$f"
done
```

- [ ] **Step 3: Replace all `pl-` agent references inside agent files**

Every agent body references other agents by `pl-NNN-xxx` name. Replace all occurrences across all agent files:

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
# Replace pl-NNN patterns in all agent files (both fg- and non-prefixed review agents)
for f in agents/*.md; do
  sed -i '' \
    -e 's/pl-010-shaper/fg-010-shaper/g' \
    -e 's/pl-050-project-bootstrapper/fg-050-project-bootstrapper/g' \
    -e 's/pl-100-orchestrator/fg-100-orchestrator/g' \
    -e 's/pl-130-docs-discoverer/fg-130-docs-discoverer/g' \
    -e 's/pl-140-deprecation-refresh/fg-140-deprecation-refresh/g' \
    -e 's/pl-150-test-bootstrapper/fg-150-test-bootstrapper/g' \
    -e 's/pl-160-migration-planner/fg-160-migration-planner/g' \
    -e 's/pl-200-planner/fg-200-planner/g' \
    -e 's/pl-210-validator/fg-210-validator/g' \
    -e 's/pl-250-contract-validator/fg-250-contract-validator/g' \
    -e 's/pl-300-implementer/fg-300-implementer/g' \
    -e 's/pl-310-scaffolder/fg-310-scaffolder/g' \
    -e 's/pl-320-frontend-polisher/fg-320-frontend-polisher/g' \
    -e 's/pl-350-docs-generator/fg-350-docs-generator/g' \
    -e 's/pl-400-quality-gate/fg-400-quality-gate/g' \
    -e 's/pl-500-test-gate/fg-500-test-gate/g' \
    -e 's/pl-600-pr-builder/fg-600-pr-builder/g' \
    -e 's/pl-650-preview-validator/fg-650-preview-validator/g' \
    -e 's/pl-700-retrospective/fg-700-retrospective/g' \
    -e 's/pl-710-feedback-capture/fg-710-feedback-capture/g' \
    -e 's/pl-720-recap/fg-720-recap/g' \
    "$f"
done
```

- [ ] **Step 4: Replace `.pipeline/` with `.forge/` in all agent files**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for f in agents/*.md; do
  sed -i '' 's/\.pipeline\//\.forge\//g' "$f"
  sed -i '' 's/`\.pipeline`/`\.forge`/g' "$f"
  sed -i '' 's/`\.pipeline\/`/`\.forge\/`/g' "$f"
done
```

- [ ] **Step 5: Replace `dev-pipeline` with `forge` in all agent files**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for f in agents/*.md; do
  sed -i '' 's/dev-pipeline\.local\.md/forge.local.md/g' "$f"
  sed -i '' 's/dev-pipeline/forge/g' "$f"
  sed -i '' 's/pipeline-config\.md/forge-config.md/g' "$f"
  sed -i '' 's/pipeline-log\.md/forge-log.md/g' "$f"
  sed -i '' 's/pipeline-neo4j/forge-neo4j/g' "$f"
done
```

- [ ] **Step 6: Replace pipeline skill references in all agent files**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for f in agents/*.md; do
  sed -i '' \
    -e 's/\/pipeline-run/\/forge-run/g' \
    -e 's/\/pipeline-init/\/forge-init/g' \
    -e 's/\/pipeline-status/\/forge-status/g' \
    -e 's/\/pipeline-reset/\/forge-reset/g' \
    -e 's/\/pipeline-rollback/\/forge-rollback/g' \
    -e 's/\/pipeline-history/\/forge-history/g' \
    -e 's/\/pipeline-shape/\/forge-shape/g' \
    -e 's/pipeline-checkpoint/forge-checkpoint/g' \
    "$f"
done
```

- [ ] **Step 7: Verify no remaining `pl-` agent references in agent files**

Run:
```bash
grep -rn "pl-[0-9]\{3\}" agents/
```
Expected: Zero matches. If any remain, fix them manually.

- [ ] **Step 8: Verify all frontmatter `name:` fields match filenames**

Run:
```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for f in agents/*.md; do
  fname=$(basename "$f" .md)
  name_field=$(grep "^name:" "$f" | head -1 | sed 's/name: *//')
  if [ "$fname" != "$name_field" ]; then
    echo "MISMATCH: file=$fname frontmatter=$name_field"
  fi
done
```
Expected: Zero mismatches.

- [ ] **Step 9: Commit**

```bash
git add agents/
git commit -m "refactor(agents): rename pl- prefix to fg- across all 21 agents"
```

---

## Task 3: Rename Skill Directories + Update Skill Content

**Files:**
- Rename: 7 skill directories `skills/pipeline-*` → `skills/forge-*`
- Modify: YAML frontmatter + body text in each SKILL.md
- Modify: 11 non-renamed skills (update internal references)

- [ ] **Step 1: Rename 7 skill directories**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
git mv skills/pipeline-run skills/forge-run
git mv skills/pipeline-init skills/forge-init
git mv skills/pipeline-status skills/forge-status
git mv skills/pipeline-reset skills/forge-reset
git mv skills/pipeline-rollback skills/forge-rollback
git mv skills/pipeline-history skills/forge-history
git mv skills/pipeline-shape skills/forge-shape
```

- [ ] **Step 2: Update frontmatter `name:` in each renamed SKILL.md**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
sed -i '' 's/^name: pipeline-run$/name: forge-run/' skills/forge-run/SKILL.md
sed -i '' 's/^name: pipeline-init$/name: forge-init/' skills/forge-init/SKILL.md
sed -i '' 's/^name: pipeline-status$/name: forge-status/' skills/forge-status/SKILL.md
sed -i '' 's/^name: pipeline-reset$/name: forge-reset/' skills/forge-reset/SKILL.md
sed -i '' 's/^name: pipeline-rollback$/name: forge-rollback/' skills/forge-rollback/SKILL.md
sed -i '' 's/^name: pipeline-history$/name: forge-history/' skills/forge-history/SKILL.md
sed -i '' 's/^name: pipeline-shape$/name: forge-shape/' skills/forge-shape/SKILL.md
```

- [ ] **Step 3: Replace all `pl-`, `.pipeline/`, `dev-pipeline`, and skill name references in ALL skill files**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for f in skills/*/SKILL.md; do
  # Agent references
  sed -i '' \
    -e 's/pl-010-shaper/fg-010-shaper/g' \
    -e 's/pl-050-project-bootstrapper/fg-050-project-bootstrapper/g' \
    -e 's/pl-100-orchestrator/fg-100-orchestrator/g' \
    -e 's/pl-130-docs-discoverer/fg-130-docs-discoverer/g' \
    -e 's/pl-140-deprecation-refresh/fg-140-deprecation-refresh/g' \
    -e 's/pl-150-test-bootstrapper/fg-150-test-bootstrapper/g' \
    -e 's/pl-160-migration-planner/fg-160-migration-planner/g' \
    -e 's/pl-200-planner/fg-200-planner/g' \
    -e 's/pl-210-validator/fg-210-validator/g' \
    -e 's/pl-250-contract-validator/fg-250-contract-validator/g' \
    -e 's/pl-300-implementer/fg-300-implementer/g' \
    -e 's/pl-310-scaffolder/fg-310-scaffolder/g' \
    -e 's/pl-320-frontend-polisher/fg-320-frontend-polisher/g' \
    -e 's/pl-350-docs-generator/fg-350-docs-generator/g' \
    -e 's/pl-400-quality-gate/fg-400-quality-gate/g' \
    -e 's/pl-500-test-gate/fg-500-test-gate/g' \
    -e 's/pl-600-pr-builder/fg-600-pr-builder/g' \
    -e 's/pl-650-preview-validator/fg-650-preview-validator/g' \
    -e 's/pl-700-retrospective/fg-700-retrospective/g' \
    -e 's/pl-710-feedback-capture/fg-710-feedback-capture/g' \
    -e 's/pl-720-recap/fg-720-recap/g' \
    "$f"
  # Directory and config references
  sed -i '' \
    -e 's/\.pipeline\//\.forge\//g' \
    -e 's/`\.pipeline`/`\.forge`/g' \
    -e 's/`\.pipeline\/`/`\.forge\/`/g' \
    -e 's/dev-pipeline\.local\.md/forge.local.md/g' \
    -e 's/dev-pipeline/forge/g' \
    -e 's/pipeline-config\.md/forge-config.md/g' \
    -e 's/pipeline-log\.md/forge-log.md/g' \
    -e 's/pipeline-neo4j/forge-neo4j/g' \
    -e 's/\/pipeline-run/\/forge-run/g' \
    -e 's/\/pipeline-init/\/forge-init/g' \
    -e 's/\/pipeline-status/\/forge-status/g' \
    -e 's/\/pipeline-reset/\/forge-reset/g' \
    -e 's/\/pipeline-rollback/\/forge-rollback/g' \
    -e 's/\/pipeline-history/\/forge-history/g' \
    -e 's/\/pipeline-shape/\/forge-shape/g' \
    -e 's/pipeline-checkpoint/forge-checkpoint/g' \
    "$f"
done
```

- [ ] **Step 4: Verify no remaining old references in skill files**

```bash
grep -rn "pl-[0-9]\{3\}\|dev-pipeline\|\.pipeline\/" skills/
```
Expected: Zero matches (except possibly inside the forge-redesign spec reference which is fine).

- [ ] **Step 5: Commit**

```bash
git add skills/
git commit -m "refactor(skills): rename pipeline-* skills to forge-*"
```

---

## Task 4: Rename Hook Script + Update hooks.json

**Files:**
- Rename: `hooks/pipeline-checkpoint.sh` → `hooks/forge-checkpoint.sh`
- Modify: `hooks/hooks.json`
- Modify: `hooks/forge-checkpoint.sh` (internal references)
- Modify: `hooks/feedback-capture.sh` (internal references)

- [ ] **Step 1: Rename the checkpoint hook script**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
git mv hooks/pipeline-checkpoint.sh hooks/forge-checkpoint.sh
```

- [ ] **Step 2: Update hooks.json to reference new script name**

In `hooks/hooks.json`, replace `pipeline-checkpoint.sh` with `forge-checkpoint.sh`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --hook",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Skill",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/forge-checkpoint.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/feedback-capture.sh",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Update `.pipeline/` references in both hook scripts**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for f in hooks/forge-checkpoint.sh hooks/feedback-capture.sh; do
  sed -i '' \
    -e 's/\.pipeline\//\.forge\//g' \
    -e 's/dev-pipeline/forge/g' \
    -e 's/pipeline-config\.md/forge-config.md/g' \
    -e 's/pipeline-log\.md/forge-log.md/g' \
    "$f"
done
```

- [ ] **Step 4: Verify hooks.json is valid JSON**

```bash
jq . hooks/hooks.json
```
Expected: Parses without error. Shows `forge-checkpoint.sh` reference.

- [ ] **Step 5: Verify no remaining old references in hooks/**

```bash
grep -rn "pipeline" hooks/
```
Expected: Zero matches.

- [ ] **Step 6: Commit**

```bash
git add hooks/
git commit -m "refactor(hooks): rename pipeline-checkpoint to forge-checkpoint"
```

---

## Task 5: Update Shared Contracts

**Files:**
- Modify: All ~48 files in `shared/` (contracts, scripts, checks, graph, recovery, learnings)

- [ ] **Step 1: Replace all references in shared/ files**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline

# Find all text files in shared/ (exclude binary/git)
find shared/ -type f \( -name "*.md" -o -name "*.sh" -o -name "*.json" -o -name "*.cypher" -o -name "*.bash" \) | while read f; do
  sed -i '' \
    -e 's/pl-010-shaper/fg-010-shaper/g' \
    -e 's/pl-050-project-bootstrapper/fg-050-project-bootstrapper/g' \
    -e 's/pl-100-orchestrator/fg-100-orchestrator/g' \
    -e 's/pl-130-docs-discoverer/fg-130-docs-discoverer/g' \
    -e 's/pl-140-deprecation-refresh/fg-140-deprecation-refresh/g' \
    -e 's/pl-150-test-bootstrapper/fg-150-test-bootstrapper/g' \
    -e 's/pl-160-migration-planner/fg-160-migration-planner/g' \
    -e 's/pl-200-planner/fg-200-planner/g' \
    -e 's/pl-210-validator/fg-210-validator/g' \
    -e 's/pl-250-contract-validator/fg-250-contract-validator/g' \
    -e 's/pl-300-implementer/fg-300-implementer/g' \
    -e 's/pl-310-scaffolder/fg-310-scaffolder/g' \
    -e 's/pl-320-frontend-polisher/fg-320-frontend-polisher/g' \
    -e 's/pl-350-docs-generator/fg-350-docs-generator/g' \
    -e 's/pl-400-quality-gate/fg-400-quality-gate/g' \
    -e 's/pl-500-test-gate/fg-500-test-gate/g' \
    -e 's/pl-600-pr-builder/fg-600-pr-builder/g' \
    -e 's/pl-650-preview-validator/fg-650-preview-validator/g' \
    -e 's/pl-700-retrospective/fg-700-retrospective/g' \
    -e 's/pl-710-feedback-capture/fg-710-feedback-capture/g' \
    -e 's/pl-720-recap/fg-720-recap/g' \
    -e 's/\.pipeline\//\.forge\//g' \
    -e 's/`\.pipeline`/`\.forge`/g' \
    -e 's/`\.pipeline\/`/`\.forge\/`/g' \
    -e 's/"\.pipeline"/"\.forge"/g' \
    -e 's/dev-pipeline\.local\.md/forge.local.md/g' \
    -e 's/dev-pipeline/forge/g' \
    -e 's/pipeline-config\.md/forge-config.md/g' \
    -e 's/pipeline-log\.md/forge-log.md/g' \
    -e 's/pipeline-neo4j/forge-neo4j/g' \
    -e 's/\/pipeline-run/\/forge-run/g' \
    -e 's/\/pipeline-init/\/forge-init/g' \
    -e 's/\/pipeline-status/\/forge-status/g' \
    -e 's/\/pipeline-reset/\/forge-reset/g' \
    -e 's/\/pipeline-rollback/\/forge-rollback/g' \
    -e 's/\/pipeline-history/\/forge-history/g' \
    -e 's/\/pipeline-shape/\/forge-shape/g' \
    -e 's/pipeline-checkpoint/forge-checkpoint/g' \
    "$f"
done
```

- [ ] **Step 2: Verify no remaining old references**

```bash
grep -rn "pl-[0-9]\{3\}\|dev-pipeline\|\.pipeline\/" shared/ | grep -v "\.git"
```
Expected: Zero matches. Some "pipeline" references in generic text (like "development pipeline") are fine — only `dev-pipeline`, `.pipeline/`, `pl-NNN` patterns must be gone.

- [ ] **Step 3: Verify shell scripts still have correct shebang and are executable**

```bash
for f in shared/checks/engine.sh shared/checks/test-engine.sh shared/discovery/discover-projects.sh shared/graph/build-project-graph.sh shared/graph/enrich-symbols.sh shared/graph/generate-seed.sh shared/graph/incremental-update.sh shared/recovery/health-checks/dependency-check.sh shared/recovery/health-checks/pre-stage-health.sh shared/platform.sh; do
  if [ -f "$f" ]; then
    head -1 "$f" | grep -q "#!/usr/bin/env bash" || echo "MISSING SHEBANG: $f"
    [ -x "$f" ] || echo "NOT EXECUTABLE: $f"
  fi
done
```
Expected: No warnings.

- [ ] **Step 4: Commit**

```bash
git add shared/
git commit -m "refactor(shared): update .pipeline/ references to .forge/"
```

---

## Task 6: Update Module Templates

**Files:**
- Modify: 21 `modules/frameworks/*/local-template.md`
- Modify: 21 `modules/frameworks/*/pipeline-config-template.md` (also rename these files)
- Modify: Any other module files with references

- [ ] **Step 1: Rename pipeline-config-template.md files to forge-config-template.md**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for d in modules/frameworks/*/; do
  if [ -f "${d}pipeline-config-template.md" ]; then
    git mv "${d}pipeline-config-template.md" "${d}forge-config-template.md"
  fi
done
```

- [ ] **Step 2: Replace references in all module files**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
find modules/ -type f -name "*.md" | while read f; do
  sed -i '' \
    -e 's/\.pipeline\//\.forge\//g' \
    -e 's/dev-pipeline\.local\.md/forge.local.md/g' \
    -e 's/dev-pipeline/forge/g' \
    -e 's/pipeline-config\.md/forge-config.md/g' \
    -e 's/pipeline-config-template\.md/forge-config-template.md/g' \
    -e 's/pipeline-log\.md/forge-log.md/g' \
    -e 's/pipeline-neo4j/forge-neo4j/g' \
    -e 's/\/pipeline-run/\/forge-run/g' \
    -e 's/\/pipeline-init/\/forge-init/g' \
    -e 's/\/pipeline-reset/\/forge-reset/g' \
    -e 's/pl-100-orchestrator/fg-100-orchestrator/g' \
    -e 's/pl-200-planner/fg-200-planner/g' \
    -e 's/pl-300-implementer/fg-300-implementer/g' \
    -e 's/pl-400-quality-gate/fg-400-quality-gate/g' \
    -e 's/pl-500-test-gate/fg-500-test-gate/g' \
    -e 's/pl-600-pr-builder/fg-600-pr-builder/g' \
    "$f"
done
```

- [ ] **Step 3: Replace references in module JSON files**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
find modules/ -type f -name "*.json" | while read f; do
  sed -i '' \
    -e 's/dev-pipeline/forge/g' \
    -e 's/\.pipeline\//\.forge\//g' \
    "$f"
done
```

- [ ] **Step 4: Verify no remaining old references in modules/**

```bash
grep -rn "dev-pipeline\|\.pipeline\/" modules/ | head -20
```
Expected: Zero matches.

- [ ] **Step 5: Commit**

```bash
git add modules/
git commit -m "refactor(modules): update all framework templates to forge naming"
```

---

## Task 7: Remove Backward Compatibility Code

**Files:**
- Modify: `shared/state-schema.md`
- Modify: `shared/recovery/recovery-engine.md`
- Modify: `shared/recovery/strategies/state-reconstruction.md`
- Delete: `tests/fixtures/state/v1.0.0-valid.json`
- Delete: `tests/fixtures/state/v1.0.0-malformed.json`

- [ ] **Step 1: Read current state-schema.md to identify all compat sections**

Read the full file. Identify and remove:
- All "clean break from v1.x" language
- All "v2.0.0" version references → replace with "v1.0.0" (fresh)
- The `recovery_applied` field definition
- All "old state files are incompatible" warnings
- All "(v1.1.0)" version labels

The schema `"version"` field value should be `"1.0.0"`.

- [ ] **Step 2: Update state-schema.md**

This requires manual editing (not simple sed) because the sections are complex. Read the file, then use Edit tool to:
1. Change all `"version": "2.0.0"` to `"version": "1.0.0"`
2. Remove the `recovery_applied` field and its documentation
3. Remove all "clean break" paragraphs
4. Remove all version history notes
5. Remove backward compatibility notes about `conventions_hash`
6. Update any "v2.0.0" references to "v1.0.0"

- [ ] **Step 3: Update recovery-engine.md**

Remove the "Backward Compatibility" subsection that documents `recovery_applied` as a derived view. The field no longer exists.

- [ ] **Step 4: Update state-reconstruction.md**

Remove the version incompatibility check paragraphs. Simplify to: "If `version` is missing or doesn't match current schema version, reinitialize state."

- [ ] **Step 5: Delete old test fixtures**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
git rm tests/fixtures/state/v1.0.0-valid.json
git rm tests/fixtures/state/v1.0.0-malformed.json
```

- [ ] **Step 6: Update test fixture v2.0.0-valid.json → rename and update version**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
# Rename to v1.0.0
git mv tests/fixtures/state/v2.0.0-valid.json tests/fixtures/state/v1.0.0-valid.json
# Update version field and remove recovery_applied
jq '.version = "1.0.0" | del(.recovery_applied)' tests/fixtures/state/v1.0.0-valid.json > tmp.json && mv tmp.json tests/fixtures/state/v1.0.0-valid.json
# Also update .pipeline references to .forge
sed -i '' 's/\.pipeline/\.forge/g' tests/fixtures/state/v1.0.0-valid.json
```

- [ ] **Step 7: Verify state fixture is valid JSON**

```bash
jq . tests/fixtures/state/v1.0.0-valid.json | head -5
```
Expected: Shows `"version": "1.0.0"`, no `recovery_applied` field.

- [ ] **Step 8: Commit**

```bash
git add shared/state-schema.md shared/recovery/ tests/fixtures/state/
git commit -m "refactor(schema): remove backward compat, reset to v1.0.0"
```

---

## Task 8: Update Tests

**Files:**
- Modify: All `.bats` files in `tests/unit/`, `tests/contract/`, `tests/scenario/`
- Modify: `tests/helpers/test-helpers.bash`
- Modify: `tests/lib/module-lists.bash`
- Modify: `tests/validate-plugin.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: Replace all references in test files**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline

# All .bats files + .bash helpers + .sh scripts in tests/
find tests/ -type f \( -name "*.bats" -o -name "*.bash" -o -name "*.sh" \) | while read f; do
  sed -i '' \
    -e 's/pl-010-shaper/fg-010-shaper/g' \
    -e 's/pl-050-project-bootstrapper/fg-050-project-bootstrapper/g' \
    -e 's/pl-100-orchestrator/fg-100-orchestrator/g' \
    -e 's/pl-130-docs-discoverer/fg-130-docs-discoverer/g' \
    -e 's/pl-140-deprecation-refresh/fg-140-deprecation-refresh/g' \
    -e 's/pl-150-test-bootstrapper/fg-150-test-bootstrapper/g' \
    -e 's/pl-160-migration-planner/fg-160-migration-planner/g' \
    -e 's/pl-200-planner/fg-200-planner/g' \
    -e 's/pl-210-validator/fg-210-validator/g' \
    -e 's/pl-250-contract-validator/fg-250-contract-validator/g' \
    -e 's/pl-300-implementer/fg-300-implementer/g' \
    -e 's/pl-310-scaffolder/fg-310-scaffolder/g' \
    -e 's/pl-320-frontend-polisher/fg-320-frontend-polisher/g' \
    -e 's/pl-350-docs-generator/fg-350-docs-generator/g' \
    -e 's/pl-400-quality-gate/fg-400-quality-gate/g' \
    -e 's/pl-500-test-gate/fg-500-test-gate/g' \
    -e 's/pl-600-pr-builder/fg-600-pr-builder/g' \
    -e 's/pl-650-preview-validator/fg-650-preview-validator/g' \
    -e 's/pl-700-retrospective/fg-700-retrospective/g' \
    -e 's/pl-710-feedback-capture/fg-710-feedback-capture/g' \
    -e 's/pl-720-recap/fg-720-recap/g' \
    -e 's/\.pipeline\//\.forge\//g' \
    -e 's/"\.pipeline"/"\.forge"/g' \
    -e 's/dev-pipeline\.local\.md/forge.local.md/g' \
    -e 's/dev-pipeline/forge/g' \
    -e 's/pipeline-config\.md/forge-config.md/g' \
    -e 's/pipeline-config-template\.md/forge-config-template.md/g' \
    -e 's/pipeline-log\.md/forge-log.md/g' \
    -e 's/pipeline-neo4j/forge-neo4j/g' \
    -e 's/\/pipeline-run/\/forge-run/g' \
    -e 's/\/pipeline-init/\/forge-init/g' \
    -e 's/\/pipeline-reset/\/forge-reset/g' \
    -e 's/\/pipeline-status/\/forge-status/g' \
    -e 's/\/pipeline-rollback/\/forge-rollback/g' \
    -e 's/\/pipeline-history/\/forge-history/g' \
    -e 's/\/pipeline-shape/\/forge-shape/g' \
    -e 's/pipeline-checkpoint/forge-checkpoint/g' \
    "$f"
done
```

- [ ] **Step 2: Update test-helpers.bash state template**

Read `tests/helpers/test-helpers.bash`, find the base state JSON template, and:
1. Change `"version": "2.0.0"` to `"version": "1.0.0"`
2. Remove `"recovery_applied": []`
3. Change any `.pipeline` paths to `.forge`

- [ ] **Step 3: Update state-schema.bats — remove v1.0.0 clean break test**

Read `tests/contract/state-schema.bats`, find and remove the test:
```bash
@test "state-schema: v1.0.0 clean break and pipeline-reset documented" {
```
Also update any test that checks for `v2.0.0` to check for `v1.0.0`.

- [ ] **Step 4: Update JSON fixtures in tests/**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
find tests/ -type f -name "*.json" | while read f; do
  sed -i '' \
    -e 's/dev-pipeline/forge/g' \
    -e 's/\.pipeline/\.forge/g' \
    "$f"
done
```

- [ ] **Step 5: Verify no remaining old references in tests/**

```bash
grep -rn "pl-[0-9]\{3\}\|dev-pipeline\|\.pipeline\/" tests/ | grep -v "\.git" | grep -v "bats-core" | head -20
```
Expected: Zero matches (excluding bats-core submodule).

- [ ] **Step 6: Run structural tests to verify**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
./tests/validate-plugin.sh
```
Expected: All 39 checks pass.

- [ ] **Step 7: Run full test suite**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
./tests/run-all.sh
```
Expected: All tests pass. If failures, fix them before committing.

- [ ] **Step 8: Commit**

```bash
git add tests/
git commit -m "refactor(tests): update assertions for forge naming"
```

---

## Task 9: Update .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Update .gitignore**

Replace `.pipeline/` with `.forge/`:

```
# Forge state (local only, never committed)
.forge/

# Worktrees
.worktrees/

# OS
.DS_Store

# Editor
.idea/
.vscode/
*.swp
*.swo

# Claude local overrides
.claude.local.md
.claude/settings.local.json
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "refactor: update .gitignore from .pipeline/ to .forge/"
```

---

## Task 10: Rewrite CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read current CLAUDE.md fully**

Read the entire file to understand all sections that reference dev-pipeline, .pipeline, pl- agents, and pipeline-* skills.

- [ ] **Step 2: Full rewrite of CLAUDE.md**

This is the largest single file change. Apply ALL of the following replacements throughout the entire file:

1. `dev-pipeline` → `forge` (everywhere, including "What this is" section)
2. `.pipeline/` → `.forge/` (everywhere)
3. All `pl-NNN-name` → `fg-NNN-name` (in agent listings, key entry points, conventions)
4. All `/pipeline-*` → `/forge-*` (skill references)
5. `pipeline-config.md` → `forge-config.md`
6. `pipeline-log.md` → `forge-log.md`
7. `dev-pipeline.local.md` → `forge.local.md`
8. `pipeline-neo4j` → `forge-neo4j`
9. `pipeline-checkpoint.sh` → `forge-checkpoint.sh`
10. `pipeline-config-template.md` → `forge-config-template.md`
11. Version `v1.4.0` → `v1.0.0`
12. State schema `v2.0.0` → `v1.0.0`
13. Remove ALL backward compatibility language:
    - "v2.0.0 is a clean break from v1.x"
    - "v1.0.0 was a clean break from pre-1.0"
    - "v1.1.0 was an additive extension"
    - "old state files are incompatible; use /pipeline-reset to clear them"
    - "Breaking state schema changes (like the v1.0.0 and v2.0.0 clean breaks)"
14. Remove `recovery_applied` from state schema description
15. Update marketplace install: `/plugin marketplace add quantumbitcz/forge`

- [ ] **Step 3: Verify no remaining old references**

```bash
grep -n "dev-pipeline\|\.pipeline\|pl-[0-9]\{3\}" CLAUDE.md | head -20
```
Expected: Zero matches.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: rewrite CLAUDE.md for forge branding"
```

---

## Task 11: Update README.md, CONTRIBUTING.md, SECURITY.md

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Modify: `SECURITY.md`

- [ ] **Step 1: Read all three files**

Read each file fully to understand scope of changes.

- [ ] **Step 2: Apply replacements to all three files**

For each file, apply the same replacement set as CLAUDE.md (step 2 of Task 10). Additionally in CONTRIBUTING.md:
- Remove the entire state schema versioning history section
- Replace with simple "State schema v1.0.0" reference
- Remove all "Breaking changes from vX.Y.Z" language

- [ ] **Step 3: Verify**

```bash
grep -n "dev-pipeline\|\.pipeline\|pl-[0-9]\{3\}" README.md CONTRIBUTING.md SECURITY.md
```
Expected: Zero matches.

- [ ] **Step 4: Commit**

```bash
git add README.md CONTRIBUTING.md SECURITY.md
git commit -m "docs: update CONTRIBUTING.md, README.md, SECURITY.md for forge"
```

---

## Task 12: Final Verification

- [ ] **Step 1: Global scan for any remaining old references**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
grep -rn "dev-pipeline" --include="*.md" --include="*.json" --include="*.sh" --include="*.bash" --include="*.bats" --include="*.yml" --include="*.yaml" --include="*.cypher" . | grep -v "\.git/" | grep -v "forge-redesign" | grep -v "convergence-engine" | head -30
```
Expected: Zero matches (excluding the design spec which documents the rename itself and any other spec/plan docs).

- [ ] **Step 2: Scan for remaining pl- agent references**

```bash
grep -rn "pl-[0-9]\{3\}" --include="*.md" --include="*.json" --include="*.sh" --include="*.bash" --include="*.bats" . | grep -v "\.git/" | grep -v "forge-redesign" | grep -v "convergence-engine" | head -30
```
Expected: Zero matches.

- [ ] **Step 3: Scan for remaining .pipeline/ references**

```bash
grep -rn "\.pipeline/" --include="*.md" --include="*.json" --include="*.sh" --include="*.bash" --include="*.bats" --include="*.yml" --include="*.cypher" . | grep -v "\.git/" | grep -v "forge-redesign" | grep -v "convergence-engine" | head -30
```
Expected: Zero matches.

- [ ] **Step 4: Verify all agent frontmatter names match filenames**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for f in agents/*.md; do
  fname=$(basename "$f" .md)
  name_field=$(grep "^name:" "$f" | head -1 | sed 's/name: *//')
  if [ "$fname" != "$name_field" ]; then
    echo "MISMATCH: file=$fname frontmatter=$name_field"
  fi
done
```
Expected: Zero mismatches.

- [ ] **Step 5: Verify all skill frontmatter names match directory names**

```bash
cd /Users/denissajnar/IdeaProjects/dev-pipeline
for d in skills/*/; do
  dirname=$(basename "$d")
  if [ -f "${d}SKILL.md" ]; then
    name_field=$(grep "^name:" "${d}SKILL.md" | head -1 | sed 's/name: *//')
    if [ "$dirname" != "$name_field" ]; then
      echo "MISMATCH: dir=$dirname frontmatter=$name_field"
    fi
  fi
done
```
Expected: Zero mismatches.

- [ ] **Step 6: Run structural validation**

```bash
./tests/validate-plugin.sh
```
Expected: All 39 checks pass.

- [ ] **Step 7: Run full test suite**

```bash
./tests/run-all.sh
```
Expected: All tests pass.

- [ ] **Step 8: Verify version numbers**

```bash
jq '.version' .claude-plugin/plugin.json
jq '.metadata.version' .claude-plugin/marketplace.json
```
Expected: Both return `"1.0.0"`.

- [ ] **Step 9: If all checks pass, tag the release**

Do NOT push or tag without user confirmation. Report results and ask user if they want to tag v1.0.0.
