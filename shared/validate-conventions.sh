#!/usr/bin/env bash
# Validates that all convention stack references in forge.local.md resolve to
# existing files in the plugin's modules/ directory.
#
# Usage: validate-conventions.sh <forge-local-path> <plugin-root>
# Exit 0 = valid, Exit 1 = missing references (listed on stderr)
# Exit 2 = usage error
set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: validate-conventions.sh <forge-local-path> <plugin-root>" >&2
  exit 2
fi

FORGE_LOCAL="$1"
PLUGIN_ROOT="$2"

if [[ ! -f "$FORGE_LOCAL" ]]; then
  echo "ERROR: forge.local.md not found: $FORGE_LOCAL" >&2
  exit 2
fi

if [[ ! -d "$PLUGIN_ROOT/modules" ]]; then
  echo "ERROR: plugin root does not contain modules/: $PLUGIN_ROOT" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Parse YAML frontmatter using python3
# Extracts component definitions (or flat config) and validates references.
# ---------------------------------------------------------------------------
errors=$(python3 -c "
import sys, os, re

forge_local_path = sys.argv[1]
plugin_root = sys.argv[2]

# Read file and extract YAML frontmatter
with open(forge_local_path, 'r') as f:
    content = f.read()

# Extract frontmatter between --- delimiters
match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if not match:
    # No frontmatter = nothing to validate
    sys.exit(0)

frontmatter = match.group(1)

# Minimal YAML parser for the flat key-value and components: structure
# We only need framework, language, testing, variant, and crosscutting layers
import json

try:
    import yaml
    config = yaml.safe_load(frontmatter) or {}
except ImportError:
    # Fallback: simple line-by-line parser for flat and indented YAML
    config = {}
    current_section = None
    current_component = None
    indent_stack = []

    for line in frontmatter.split('\n'):
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue

        # Detect indentation level
        indent = len(line) - len(line.lstrip())

        if ':' not in stripped:
            continue

        key, _, value = stripped.partition(':')
        key = key.strip()
        value = value.strip()

        if key == 'components' and not value:
            current_section = 'components'
            config['components'] = {}
            indent_stack = [indent]
            continue

        if current_section == 'components':
            if indent <= indent_stack[0]:
                # Back to top level
                current_section = None
                current_component = None
                config[key] = value
                continue

            if not value and current_component is None or (len(indent_stack) == 1 and indent > indent_stack[0]):
                if not value:
                    current_component = key
                    config['components'][key] = {}
                    if len(indent_stack) < 2:
                        indent_stack.append(indent)
                    continue

            if current_component and indent > indent_stack[-1]:
                config['components'][current_component][key] = value
                continue
            elif not value:
                current_component = key
                config['components'][key] = {}
                continue
            else:
                if current_component:
                    config['components'][current_component][key] = value
                continue
        else:
            config[key] = value

errors = []

# Crosscutting layer names and their module directories
CROSSCUTTING_LAYERS = {
    'database': 'databases',
    'persistence': 'persistence',
    'migrations': 'migrations',
    'api_protocol': 'api-protocols',
    'messaging': 'messaging',
    'caching': 'caching',
    'search': 'search',
    'storage': 'storage',
    'auth': 'auth',
    'observability': 'observability',
}

def validate_component(name, comp):
    fw = comp.get('framework', '').strip()
    lang = comp.get('language', '').strip()
    testing = comp.get('testing', '').strip()
    variant = comp.get('variant', '').strip()

    # Framework check
    if fw and fw != 'null':
        fw_path = os.path.join(plugin_root, 'modules', 'frameworks', fw, 'conventions.md')
        if not os.path.isfile(fw_path):
            errors.append(f'[{name}] framework \"{fw}\": {fw_path} not found')

    # Language check
    if lang and lang != 'null':
        lang_path = os.path.join(plugin_root, 'modules', 'languages', lang + '.md')
        if not os.path.isfile(lang_path):
            errors.append(f'[{name}] language \"{lang}\": {lang_path} not found')

    # Testing check
    if testing:
        test_path = os.path.join(plugin_root, 'modules', 'testing', testing + '.md')
        if not os.path.isfile(test_path):
            errors.append(f'[{name}] testing \"{testing}\": {test_path} not found')

    # Variant check (requires framework)
    if variant and fw:
        variant_path = os.path.join(plugin_root, 'modules', 'frameworks', fw, 'variants', variant + '.md')
        if not os.path.isfile(variant_path):
            errors.append(f'[{name}] variant \"{variant}\": {variant_path} not found')

    # Crosscutting layers
    for layer_key, module_dir in CROSSCUTTING_LAYERS.items():
        layer_val = comp.get(layer_key, '').strip()
        if not layer_val:
            continue
        # Check framework binding first, then generic module
        found = False
        if fw and fw != 'null':
            binding_path = os.path.join(plugin_root, 'modules', 'frameworks', fw, layer_key, layer_val + '.md')
            if os.path.isfile(binding_path):
                found = True
            # Also check the persistence/ subdirectory name variant
            binding_path2 = os.path.join(plugin_root, 'modules', 'frameworks', fw, module_dir, layer_val + '.md')
            if os.path.isfile(binding_path2):
                found = True
        # Generic module fallback
        generic_path = os.path.join(plugin_root, 'modules', module_dir, layer_val + '.md')
        if os.path.isfile(generic_path):
            found = True
        if not found:
            errors.append(f'[{name}] {layer_key} \"{layer_val}\": no framework binding or generic module found')

components = config.get('components')
if isinstance(components, dict) and len(components) > 0:
    for comp_name, comp_data in components.items():
        if isinstance(comp_data, dict):
            validate_component(comp_name, comp_data)
else:
    # Flat config: treat top-level keys as a single component
    validate_component('default', config)

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
" "$FORGE_LOCAL" "$PLUGIN_ROOT" 2>&1)

exit_code=$?

if [[ $exit_code -eq 1 ]]; then
  echo "Convention validation failed:" >&2
  echo "$errors" >&2
  exit 1
elif [[ $exit_code -ne 0 ]]; then
  echo "Convention validation error:" >&2
  echo "$errors" >&2
  exit 2
fi

exit 0
