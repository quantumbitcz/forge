#!/usr/bin/env bash
set -euo pipefail

# validate-config.sh — PREFLIGHT config validation for forge.local.md
# Exit 0 = PASS, Exit 1 = ERROR, Exit 2 = WARNING only
# Usage: validate-config.sh <path-to-forge-local.md>

CONFIG_FILE="${1:?Usage: validate-config.sh <path-to-forge-local.md>}"

[[ -f "$CONFIG_FILE" ]] || { echo "ERROR: File not found: $CONFIG_FILE"; exit 1; }

# Extract YAML block from markdown
yaml_content=$(sed -n '/^```yaml/,/^```$/p' "$CONFIG_FILE" | sed '1d;$d')

[[ -z "$yaml_content" ]] && { echo "ERROR: No \`\`\`yaml block found in $CONFIG_FILE"; exit 1; }

# Use Python for reliable YAML parsing and validation
python3 << 'PYEOF' "$yaml_content"
import sys, json

# Read YAML content from argument
yaml_text = sys.argv[1]

# Try yaml import, fall back to simple parsing
try:
    import yaml
    config = yaml.safe_load(yaml_text)
except ImportError:
    # Simple key-value parser for basic YAML
    config = {"components": {}}
    current_section = None
    for line in yaml_text.strip().split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.endswith(":") and not line.startswith(" "):
            current_section = stripped[:-1]
            if current_section not in config:
                config[current_section] = {}
        elif ":" in stripped and current_section:
            key, val = stripped.split(":", 1)
            val = val.strip()
            if val == "null" or val == "~":
                val = None
            config[current_section][key.strip()] = val

errors = []
warnings = []
checks = 0

components = config.get("components", {})

# --- Phase 1: Enum validation ---
VALID_LANGUAGES = {"kotlin","java","typescript","python","go","rust","swift","c","csharp","ruby","php","dart","elixir","scala","cpp",None}
VALID_FRAMEWORKS = {"spring","react","fastapi","axum","swiftui","vapor","express","sveltekit","k8s","embedded","go-stdlib","aspnet","django","nextjs","gin","jetpack-compose","kotlin-multiplatform","angular","nestjs","vue","svelte",None}
VALID_TESTING = {"kotest","junit5","vitest","jest","pytest","go-testing","xctest","rust-test","xunit-nunit","testcontainers","playwright","cypress","cucumber","k6","detox","rspec","phpunit","exunit","scalatest",None}

def fuzzy_suggest(val, valid_set):
    """Simple Levenshtein-based suggestion."""
    if val is None:
        return None
    best, best_dist = None, 999
    for v in valid_set:
        if v is None:
            continue
        d = sum(1 for a, b in zip(val, v) if a != b) + abs(len(val) - len(v))
        if d < best_dist:
            best, best_dist = v, d
    return best if best_dist <= 2 else None

lang = components.get("language")
fw = components.get("framework")
test = components.get("testing")

checks += 1
if lang not in VALID_LANGUAGES:
    suggestion = fuzzy_suggest(lang, VALID_LANGUAGES)
    msg = f'components.language "{lang}" is not valid'
    if suggestion:
        msg += f' (did you mean "{suggestion}"?)'
    errors.append(msg)

checks += 1
if fw not in VALID_FRAMEWORKS:
    suggestion = fuzzy_suggest(fw, VALID_FRAMEWORKS)
    msg = f'components.framework "{fw}" is not valid'
    if suggestion:
        msg += f' (did you mean "{suggestion}"?)'
    errors.append(msg)

checks += 1
if test not in VALID_TESTING:
    suggestion = fuzzy_suggest(test, VALID_TESTING)
    msg = f'components.testing "{test}" is not valid'
    if suggestion:
        msg += f' (did you mean "{suggestion}"?)'
    errors.append(msg)

# --- Phase 2: Cross-field validation ---
LEGAL_COMBOS = {
    "spring": {"kotlin","java"},
    "react": {"typescript"}, "nextjs": {"typescript"}, "angular": {"typescript"},
    "vue": {"typescript"}, "svelte": {"typescript"}, "sveltekit": {"typescript"},
    "express": {"typescript"}, "nestjs": {"typescript"},
    "fastapi": {"python"}, "django": {"python"},
    "axum": {"rust"},
    "gin": {"go"}, "go-stdlib": {"go"},
    "swiftui": {"swift"}, "vapor": {"swift"},
    "jetpack-compose": {"kotlin"}, "kotlin-multiplatform": {"kotlin"},
    "aspnet": {"csharp"},
    "embedded": {"c","rust","cpp"},
    "k8s": {None},
}

checks += 1
if fw in LEGAL_COMBOS and lang not in LEGAL_COMBOS[fw]:
    valid_langs = ", ".join(str(l) for l in sorted(LEGAL_COMBOS[fw], key=str))
    errors.append(f'framework "{fw}" is not compatible with language "{lang}" (valid: {valid_langs})')

# --- Phase 3: PREFLIGHT constraint validation ---
scoring = config.get("scoring", {})
convergence = config.get("convergence", {})

if scoring:
    checks += 1
    cw = scoring.get("critical_weight")
    if cw is not None:
        try:
            if int(cw) < 10:
                errors.append(f"scoring.critical_weight ({cw}) must be >= 10")
        except (ValueError, TypeError):
            pass

    checks += 1
    pt = scoring.get("pass_threshold")
    if pt is not None:
        try:
            if int(pt) < 60 or int(pt) > 100:
                errors.append(f"scoring.pass_threshold ({pt}) must be 60-100")
        except (ValueError, TypeError):
            pass

    checks += 1
    ww = scoring.get("warning_weight")
    if ww is not None:
        try:
            if int(ww) < 1:
                errors.append(f"scoring.warning_weight ({ww}) must be >= 1")
        except (ValueError, TypeError):
            pass

    checks += 1
    ot = scoring.get("oscillation_tolerance")
    if ot is not None:
        try:
            if int(ot) < 0 or int(ot) > 20:
                errors.append(f"scoring.oscillation_tolerance ({ot}) must be 0-20")
        except (ValueError, TypeError):
            pass

if convergence:
    checks += 1
    mi = convergence.get("max_iterations")
    if mi is not None:
        try:
            if int(mi) < 3 or int(mi) > 20:
                errors.append(f"convergence.max_iterations ({mi}) must be 3-20")
        except (ValueError, TypeError):
            pass

    checks += 1
    pp = convergence.get("plateau_patience")
    if pp is not None:
        try:
            if int(pp) < 1 or int(pp) > 5:
                errors.append(f"convergence.plateau_patience ({pp}) must be 1-5")
        except (ValueError, TypeError):
            pass

    checks += 1
    pt2 = convergence.get("plateau_threshold")
    if pt2 is not None:
        try:
            if int(pt2) < 0 or int(pt2) > 10:
                errors.append(f"convergence.plateau_threshold ({pt2}) must be 0-10")
        except (ValueError, TypeError):
            pass

# --- Output ---
if errors:
    for e in errors:
        print(f"ERROR: {e}")
    sys.exit(1)
elif warnings:
    for w in warnings:
        print(f"WARNING: {w}")
    print(f"WARNING: {len(warnings)} warning(s), {checks} checks passed")
    sys.exit(2)
else:
    print(f"PASS: {checks} checks passed")
    sys.exit(0)
PYEOF
