# F23: Feature Flag Management Integration

## Status
DRAFT — 2026-04-13 (Forward-Looking)

## Problem Statement

Feature flags are foundational to modern deployment practices — they enable trunk-based development, canary releases, A/B testing, and progressive rollouts. Yet Forge has no modules, conventions, or quality checks for feature flag systems. This creates several gaps:

1. **Stale flags:** Feature flags that have been fully rolled out remain in the codebase indefinitely. Dead code branches guarded by permanently-true flags accumulate technical debt. No forge agent detects these.
2. **Untested flag paths:** Code guarded by feature flags often has only the flag-on path tested. The flag-off path (fallback behavior) goes untested until an incident disables the flag in production. Forge's test reviewers do not check for flag-path coverage.
3. **Naming inconsistency:** Teams adopt ad-hoc flag naming conventions (`enable_foo`, `FF_BAR`, `feature.baz.enabled`, `use-new-checkout`). Without convention enforcement, flag discovery and lifecycle management become chaotic.
4. **Hardcoded toggles:** Developers use boolean literals or environment variables as ad-hoc feature flags instead of a proper flag service. These are invisible to flag management tools and cannot be remotely toggled.
5. **Deployment blind spots:** Forge's `/deploy` skill executes deployment commands but has no awareness of feature flag state. Deploying code with a flag set to "off" in production is a no-op that wastes a release cycle.

Competitive validation: LaunchDarkly, Unleash, and Split provide SDKs and dashboards but no IDE-integrated convention enforcement. Piranha (Uber, open-sourced 2022) automates stale flag cleanup but is a standalone tool, not pipeline-integrated. No existing tool combines flag lifecycle management with autonomous code review and deployment verification.

## Proposed Solution

Add a `modules/feature-flags/` module layer with general conventions and provider-specific sub-modules for LaunchDarkly, Unleash, Split, and custom (homegrown) flag systems. L1 check engine patterns detect stale flags, untested flag paths, hardcoded toggles, and naming violations. The implementer is convention-aware when working behind feature flags. The deploy skill gains flag-state verification before and after deployment.

## Detailed Design

### Architecture

```
modules/
  feature-flags/
    conventions.md              # General feature flag best practices
    rules-override.json         # Provider-agnostic L1 patterns
    COMPOSITION.md              # Composition rules
    launchdarkly/
      conventions.md            # LaunchDarkly SDK patterns, targeting rules
      rules-override.json       # LaunchDarkly-specific L1 patterns
      known-deprecations.json   # LaunchDarkly SDK deprecations (v2 schema)
    unleash/
      conventions.md            # Unleash toggle types, strategies, variants
      rules-override.json       # Unleash-specific L1 patterns
    split/
      conventions.md            # Split treatments, traffic allocation
      rules-override.json       # Split-specific L1 patterns
    custom/
      conventions.md            # Homegrown flag system conventions
      rules-override.json       # Custom flag L1 patterns (configurable prefix)
```

**Composition order:** Feature flag modules compose at the same level as other crosscutting modules. Most-specific wins: `feature-flags/launchdarkly > feature-flags > language > code-quality`.

### Schema / Data Model

#### New Finding Categories

Added to `shared/checks/category-registry.json`:

```json
{
  "FLAG-STALE": {
    "description": "Stale feature flag — flag fully rolled out but code branches still present",
    "agents": ["fg-410-code-reviewer"],
    "wildcard": false,
    "priority": 5,
    "affinity": ["fg-410-code-reviewer"]
  },
  "FLAG-UNTESTED": {
    "description": "Feature-flagged code path without tests for both flag states",
    "agents": ["fg-410-code-reviewer"],
    "wildcard": false,
    "priority": 3,
    "affinity": ["fg-410-code-reviewer"]
  },
  "FLAG-HARDCODED": {
    "description": "Hardcoded boolean toggle that should be a feature flag",
    "agents": ["fg-410-code-reviewer"],
    "wildcard": false,
    "priority": 6,
    "affinity": ["fg-410-code-reviewer"]
  },
  "FLAG-CLEANUP": {
    "description": "Feature flag eligible for cleanup (fully rolled out, no rollback risk)",
    "agents": ["fg-410-code-reviewer"],
    "wildcard": false,
    "priority": 6,
    "affinity": ["fg-410-code-reviewer"]
  },
  "FLAG-NAMING": {
    "description": "Feature flag naming convention violation",
    "agents": ["fg-410-code-reviewer"],
    "wildcard": false,
    "priority": 5,
    "affinity": ["fg-410-code-reviewer"]
  }
}
```

#### Severity Mapping

| Finding | Default Severity | Rationale |
|---|---|---|
| `FLAG-STALE` | WARNING | Tech debt, not an immediate risk. Accumulation escalates (3+ stale flags = CRITICAL per APPROACH escalation rule). |
| `FLAG-UNTESTED` | WARNING | Missing test coverage for fallback path is a latent risk. |
| `FLAG-HARDCODED` | INFO | Advisory — not all boolean literals should be flags. |
| `FLAG-CLEANUP` | INFO | Informational — suggests cleanup opportunity. |
| `FLAG-NAMING` | INFO | Convention violation, not a functional issue. |

#### L1 Pattern Rules (Representative)

**Provider-agnostic (`modules/feature-flags/rules-override.json`):**

```json
{
  "rules": [
    {
      "id": "FLAG-HARDCODED-001",
      "pattern": "(?:if|when)\\s*\\(\\s*(?:true|false)\\s*\\)",
      "scope": "line",
      "message": "Hardcoded boolean in conditional. If this guards a feature, use a feature flag service instead.",
      "severity": "INFO",
      "category": "FLAG-HARDCODED",
      "languages": ["kotlin", "java", "typescript", "swift", "dart", "csharp", "scala"]
    },
    {
      "id": "FLAG-HARDCODED-002",
      "pattern": "if\\s+(?:True|False)\\s*:",
      "scope": "line",
      "message": "Hardcoded boolean in conditional. If this guards a feature, use a feature flag service instead.",
      "severity": "INFO",
      "category": "FLAG-HARDCODED",
      "languages": ["python"]
    }
  ]
}
```

**LaunchDarkly (`modules/feature-flags/launchdarkly/rules-override.json`):**

```json
{
  "rules": [
    {
      "id": "FLAG-NAMING-LD-001",
      "pattern": "variation\\(\\s*['\"]([^'\"]+)['\"]",
      "check": "naming_convention",
      "naming_pattern": "^[a-z][a-z0-9]*(-[a-z0-9]+)*$",
      "message": "LaunchDarkly flag key does not follow kebab-case convention.",
      "severity": "INFO",
      "category": "FLAG-NAMING",
      "languages": ["typescript", "java", "kotlin", "python", "go", "ruby", "csharp"]
    },
    {
      "id": "FLAG-UNTESTED-LD-001",
      "pattern": "(?:variation|boolVariation|stringVariation)\\(",
      "scope": "file",
      "check": "test_coverage",
      "message": "LaunchDarkly flag evaluation found. Ensure tests cover both flag-on and flag-off paths.",
      "severity": "WARNING",
      "category": "FLAG-UNTESTED",
      "languages": ["typescript", "java", "kotlin", "python", "go", "ruby", "csharp"]
    }
  ]
}
```

**Unleash (`modules/feature-flags/unleash/rules-override.json`):**

```json
{
  "rules": [
    {
      "id": "FLAG-NAMING-UL-001",
      "pattern": "isEnabled\\(\\s*['\"]([^'\"]+)['\"]",
      "check": "naming_convention",
      "naming_pattern": "^[a-z][a-z0-9]*(\\.[a-z0-9]+)*$",
      "message": "Unleash toggle name does not follow dot-separated convention.",
      "severity": "INFO",
      "category": "FLAG-NAMING",
      "languages": ["typescript", "java", "kotlin", "python", "go", "ruby"]
    }
  ]
}
```

#### Auto-Detection Signals

| Signal File / Pattern | Module Loaded | Confidence |
|---|---|---|
| `launchdarkly-` in package.json / `com.launchdarkly` in build.gradle | `feature-flags/launchdarkly` | HIGH |
| `unleash-client` in package.json / `unleash` in requirements.txt | `feature-flags/unleash` | HIGH |
| `@splitsoftware/splitio` in package.json / `splitio` in requirements.txt | `feature-flags/split` | HIGH |
| Custom flag config file (configurable path in `forge.local.md`) | `feature-flags/custom` | MEDIUM |
| No flag SDK detected but `feature_flags.enabled: true` in config | `feature-flags` (generic only) | LOW |

### Configuration

In `forge.local.md` (per-project):

```yaml
components:
  language: typescript
  framework: react
  testing: vitest
  feature_flags: launchdarkly   # launchdarkly | unleash | split | custom

feature_flags:
  naming_convention: "^[a-z][a-z0-9]*(-[a-z0-9]+)*$"  # Override default naming pattern
  stale_threshold_days: 30       # Flags older than this with 100% rollout → FLAG-STALE
  custom_flag_pattern: "FeatureFlag\\."  # Pattern to detect custom flag system usage
  flag_config_path: "config/flags.json"  # Path to flag configuration file (for stale detection)
```

In `forge-config.md` (plugin-wide defaults):

```yaml
feature_flags:
  enabled: true                   # Master toggle
  auto_detect: true               # Detect flag provider from dependencies
  provider: auto                  # auto | launchdarkly | unleash | split | custom
  stale_threshold_days: 30        # Days before a fully-rolled-out flag is stale
  naming_convention: ""           # Empty = use provider default
  test_both_paths: true           # Require tests for both flag-on and flag-off
  deploy_flag_check: true         # Verify flag state during /deploy
  hardcoded_detection: true       # Detect hardcoded boolean toggles
```

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `feature_flags.enabled` | boolean | `true` | -- | Master toggle for feature flag module |
| `feature_flags.auto_detect` | boolean | `true` | -- | Auto-detect flag provider from dependencies |
| `feature_flags.provider` | string | `auto` | `auto`, `launchdarkly`, `unleash`, `split`, `custom` | Flag provider selection |
| `feature_flags.stale_threshold_days` | integer | `30` | 7-365 | Days before a fully-rolled-out flag is flagged as stale |
| `feature_flags.naming_convention` | string | `""` | Valid regex | Custom naming pattern. Empty = provider default. |
| `feature_flags.test_both_paths` | boolean | `true` | -- | Require tests covering both flag states |
| `feature_flags.deploy_flag_check` | boolean | `true` | -- | Verify flag state during deployment |
| `feature_flags.hardcoded_detection` | boolean | `true` | -- | Detect hardcoded boolean toggles |

### Data Flow

#### PREFLIGHT (Auto-Detection + Convention Loading)

1. Orchestrator scans dependency manifests for flag SDK references
2. Load provider-specific module (or generic module if no provider detected)
3. Record detected provider in `state.json.detected_modules.feature_flags`
4. Load `rules-override.json` from both generic and provider-specific modules

#### PLANNING (Flag-Aware Planning)

1. Planner (fg-200) receives feature flag conventions from loaded modules
2. When the requirement mentions "behind a flag" or "feature toggle":
   a. Plan includes creating/using a feature flag
   b. Plan includes tests for both flag-on and flag-off paths
   c. Plan includes flag cleanup task (optional, tracked as FLAG-CLEANUP)

#### IMPLEMENTING (Flag-Aware Implementation)

1. Implementer (fg-300) follows conventions when creating feature-flagged code:
   - Uses correct SDK patterns for the detected provider
   - Follows naming convention from config
   - Implements both code paths (flag-on = new behavior, flag-off = existing behavior)
2. Test bootstrapper (fg-150) generates test stubs covering both flag states

#### REVIEWING (Flag-Specific Findings)

1. Code reviewer (fg-410) applies FLAG-* findings from loaded rules
2. Stale flag detection:
   a. If `flag_config_path` is configured, read the flag configuration file
   b. Cross-reference flag keys in code with flag config
   c. Flags at 100% rollout for > `stale_threshold_days` → FLAG-STALE
   d. Flags referenced in code but absent from config → FLAG-STALE (possibly removed from service)
3. Test coverage check:
   a. For each flag evaluation in production code, search test files for matching flag key
   b. Verify tests exist for both `true` and `false` returns
   c. Missing coverage → FLAG-UNTESTED

#### SHIPPING (Deploy Flag Check)

When `deploy_flag_check: true` and `/deploy` is invoked:

1. Before deployment: read flag state from flag service (if CLI available)
   - LaunchDarkly: `ld flag-status list` or API call
   - Unleash: `unleash-cli flags` or API call
   - Split: `split flags list` or API call
2. Verify that flags referenced in the deployed code exist in the flag service
3. Warn if new code references flags that are currently "off" in the target environment:
   ```
   WARNING: Flag "new-checkout-flow" is OFF in production.
   The deployed code will not execute the new checkout path until this flag is enabled.
   ```
4. After deployment: optionally verify flag state has not changed (prevents mid-deploy flag toggles)

### Integration Points

| Agent / System | Integration | Change Required |
|---|---|---|
| `fg-100-orchestrator` | Auto-detect feature flag provider at PREFLIGHT. Load conventions. | Add detection logic to PREFLIGHT module loading. |
| `fg-200-planner` | Include flag conventions in plan context. Ensure plans for flagged features include both paths and cleanup. | No agent change — conventions loaded via standard composition. |
| `fg-300-implementer` | Follow flag SDK patterns and naming conventions. Implement both flag paths. | No agent change — conventions loaded via standard composition. |
| `fg-150-test-bootstrapper` | Generate test stubs for both flag-on and flag-off paths when flags are detected. | Add flag-aware test stub generation heuristic. |
| `fg-410-code-reviewer` | Apply `FLAG-*` findings from loaded rules. Cross-reference flag config for staleness. | No agent change — rules loaded via standard check engine. |
| `fg-500-test-gate` | Verify flag-path test coverage (both states tested). | Add coverage check for flag evaluations. |
| `/deploy` skill | Pre-deploy flag state verification. Post-deploy flag state confirmation. | Add flag check section to deploy SKILL.md. |
| `shared/checks/engine.sh` | Load `rules-override.json` from `feature-flags/` modules. | Standard module loading — no engine changes needed. |
| `shared/checks/category-registry.json` | Add `FLAG-STALE`, `FLAG-UNTESTED`, `FLAG-HARDCODED`, `FLAG-CLEANUP`, `FLAG-NAMING` categories. | Registry update. |

### Error Handling

| Failure Mode | Behavior | Degradation |
|---|---|---|
| Flag SDK not detected (false negative) | User can explicitly set `feature_flags:` in `forge.local.md` | Manual configuration available |
| Flag config file not found | Skip stale flag detection. Log INFO. | Stale detection disabled, other checks continue. |
| Flag service CLI not installed | Skip deploy flag check. Log INFO: "Flag CLI not available, skipping deploy flag verification." | Convention checks still run (pattern-based). |
| Flag service API unreachable | Skip deploy flag check. Log WARNING. | Same as CLI unavailable. |
| Naming convention regex invalid | Log WARNING, use provider default. | Falls back to provider default pattern. |
| Custom flag pattern too broad | Excessive false positives for FLAG-HARDCODED. | User tunes `custom_flag_pattern` in config. |

## Performance Characteristics

### Module Loading

| Module | Convention File Size | Rules Count | Load Time Impact |
|---|---|---|---|
| feature-flags (generic) | ~250 lines | 5-8 rules | <10ms |
| launchdarkly | ~200 lines | 8-12 rules | <10ms |
| unleash | ~150 lines | 6-10 rules | <10ms |
| split | ~150 lines | 6-10 rules | <10ms |
| custom | ~100 lines | 3-5 rules | <10ms |

### Stale Flag Detection

| Project Size | Flag References | Scan Time |
|---|---|---|
| Small (50 files) | 5-20 flags | <200ms |
| Medium (500 files) | 20-100 flags | 1-3s |
| Large (5,000 files) | 50-500 flags | 5-15s |

Stale flag detection requires cross-referencing code references with a flag configuration file. The scan is bounded by the number of unique flag keys, not the total codebase size.

### Token Impact

Feature flag conventions add 150-300 tokens to the convention stack. Minimal impact relative to existing stacks.

## Testing Approach

### Structural Tests

1. **Module structure:** Each sub-module directory contains `conventions.md` and `rules-override.json`
2. **Rules schema:** All `rules-override.json` files validate against the existing rules schema
3. **Category codes:** All rules reference valid categories from `category-registry.json`

### Unit Tests (`tests/unit/feature-flags.bats`)

1. **Auto-detection:** Place LaunchDarkly SDK in package.json, verify detection
2. **FLAG-HARDCODED:** Apply rules to a file with `if (true)`, verify INFO finding
3. **FLAG-NAMING:** Apply LaunchDarkly rules to a file with `variation("BAD_NAME")`, verify finding
4. **FLAG-UNTESTED:** Apply rules to a flagged file without corresponding test coverage, verify WARNING
5. **FLAG-STALE:** Provide a flag config with a 100%-rolled-out flag, reference in code, verify WARNING
6. **Scoring integration:** Verify `FLAG-*` findings correctly deduct points using standard formula

### Scenario Tests

1. **LaunchDarkly project:** Run `/forge-run --dry-run` on a React + LaunchDarkly project. Verify auto-detection, convention loading, and flag-specific findings.
2. **Deploy flag check:** Configure a mock flag CLI. Run `/deploy --dry-run staging`. Verify flag state warning is produced.
3. **Stale cleanup:** Project with a flag at 100% rollout for 45 days. Verify FLAG-STALE finding and cleanup suggestion.

## Acceptance Criteria

1. `modules/feature-flags/` contains generic conventions and provider-specific sub-modules for LaunchDarkly, Unleash, Split, and custom
2. Auto-detection at PREFLIGHT correctly identifies flag providers from dependency manifests
3. L1 patterns detect hardcoded toggles, naming violations, and untested flag paths
4. Stale flag detection cross-references code with flag configuration files
5. `FLAG-STALE`, `FLAG-UNTESTED`, `FLAG-HARDCODED`, `FLAG-CLEANUP`, `FLAG-NAMING` categories are registered in `category-registry.json`
6. The implementer follows flag conventions when creating feature-flagged code
7. `/deploy` skill verifies flag state before deployment when `deploy_flag_check: true`
8. All findings integrate with the standard scoring formula
9. `./tests/validate-plugin.sh` passes with new modules added
10. Stale flag detection runs in under 15 seconds on a 5,000-file project

## Migration Path

1. **v2.0.0:** Ship feature flag modules. Auto-detection enabled by default.
2. **v2.0.0:** Add `feature_flags:` section to `forge-config-template.md` for web frameworks (react, angular, vue, svelte, nextjs, sveltekit).
3. **v2.0.0:** Add `FLAG-*` categories to `category-registry.json`.
4. **v2.0.0:** Update `/deploy` SKILL.md with flag verification section.
5. **v2.1.0 (future):** Add OpenFeature (CNCF) module as provider-agnostic standard.
6. **v2.1.0 (future):** Add Piranha-style automated stale flag cleanup as an optional implementer action.
7. **No breaking changes:** Existing projects without feature flag SDKs experience zero behavioral change.

## Dependencies

**Depends on:**
- Check engine (`shared/checks/engine.sh`) — loads `rules-override.json` from module directories
- Module composition system (`modules/COMPOSITION.md`) — determines convention loading order
- `/deploy` skill — integration point for flag state verification

**Depended on by:**
- F24 (Deployment Strategies): canary deployments benefit from feature flag awareness (canary can use flags instead of traffic splitting)
