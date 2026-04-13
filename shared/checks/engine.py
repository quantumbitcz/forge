#!/usr/bin/env python3
"""Check engine entry point -- language detection, caching, Layer 1+2 dispatch.

Replaces the bash 4.0+ requirement of engine.sh for the common case.
Falls back gracefully on all errors (exit 0 -- never blocks pipeline).
"""

import sys
import os
import json
import subprocess
from pathlib import Path


def main():
    args = parse_args(sys.argv[1:])
    project_root = args.get('project_root', '')
    files_changed = args.get('files_changed', [])

    # In hook mode, also check TOOL_INPUT env var for file path (compat with engine.sh)
    if args['mode'] == 'hook' and not files_changed:
        tool_input = os.environ.get('TOOL_INPUT', '')
        if tool_input:
            try:
                ti = json.loads(tool_input)
                fp = ti.get('file_path', '')
                if fp:
                    files_changed = [fp]
            except (json.JSONDecodeError, TypeError):
                pass

    if not files_changed:
        sys.exit(0)

    # Hook mode: check for engine lock (concurrent run prevention)
    if args['mode'] == 'hook':
        forge_dir_env = os.environ.get('FORGE_DIR', '.forge')
        lock_dir = os.path.join(forge_dir_env, '.engine.lock.d')
        if os.path.isdir(lock_dir):
            # Another instance is running; exit silently
            sys.exit(0)
        try:
            os.makedirs(lock_dir, exist_ok=False)
            _engine_lock_dir = lock_dir
        except (OSError, FileExistsError):
            sys.exit(0)
    else:
        _engine_lock_dir = None

    try:
        _run_files(files_changed, args, project_root)
    finally:
        if _engine_lock_dir and os.path.isdir(_engine_lock_dir):
            try:
                os.rmdir(_engine_lock_dir)
            except OSError:
                pass


def _run_files(files_changed, args, project_root):
    for filepath in files_changed:
        # Skip nonexistent files
        if not os.path.isfile(filepath):
            continue
        # Skip generated sources
        if 'build/generated-sources' in filepath:
            continue

        language = detect_language(filepath)
        if not language:
            continue

        # Auto-detect project root via git if not provided
        effective_root = project_root
        if not effective_root:
            effective_root = _detect_project_root(filepath)
        forge_dir = os.path.join(effective_root, '.forge') if effective_root else ''

        module = detect_module(filepath, forge_dir) if forge_dir else None
        overrides = load_overrides(module, forge_dir) if forge_dir else {}

        if args['mode'] == 'hook':
            # Layer 1 only (fast patterns)
            run_layer1(filepath, language, overrides, effective_root or os.getcwd())
            # Learned rules (auto-promoted from retrospective)
            _run_learned_rules(filepath, language, effective_root or os.getcwd())
        elif args['mode'] in ('verify', 'review'):
            # Layer 1 + Layer 2 (linters)
            run_layer1(filepath, language, overrides, effective_root or os.getcwd())
            # Learned rules (auto-promoted from retrospective)
            _run_learned_rules(filepath, language, effective_root or os.getcwd())
            run_layer2(filepath, language, overrides, effective_root or os.getcwd())


def _detect_project_root(filepath):
    """Detect project root via git rev-parse --show-toplevel."""
    try:
        dirpath = os.path.dirname(os.path.abspath(filepath))
        result = subprocess.run(
            ['git', '-C', dirpath, 'rev-parse', '--show-toplevel'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, OSError):
        pass
    return ''


def detect_language(filepath):
    """Map file extension to language."""
    ext_map = {
        '.kt': 'kotlin', '.kts': 'kotlin', '.java': 'java',
        '.ts': 'typescript', '.tsx': 'typescript',
        '.js': 'javascript', '.jsx': 'javascript',
        '.py': 'python', '.go': 'go', '.rs': 'rust',
        '.swift': 'swift', '.c': 'c', '.h': 'c', '.cpp': 'cpp',
        '.cs': 'csharp', '.rb': 'ruby', '.php': 'php',
        '.dart': 'dart', '.ex': 'elixir', '.exs': 'elixir',
        '.scala': 'scala',
        '.vue': 'vue', '.svelte': 'svelte',
    }
    ext = Path(filepath).suffix.lower()
    return ext_map.get(ext)


def detect_module(filepath, forge_dir):
    """Detect module from component cache (text format: prefix=component per line)."""
    cache_path = os.path.join(forge_dir, '.component-cache')
    if os.path.isfile(cache_path):
        try:
            with open(cache_path) as f:
                for line in f:
                    line = line.strip()
                    if '=' in line:
                        prefix, comp = line.split('=', 1)
                        if filepath.startswith(prefix) or os.path.basename(filepath).startswith(prefix):
                            return comp
                        break  # first match wins (consistency with engine.sh)
        except (IOError, ValueError):
            pass
    return None


def load_overrides(module, forge_dir):
    """Load rules-override.json for the detected module."""
    if not module:
        return {}
    plugin_root = os.environ.get('CLAUDE_PLUGIN_ROOT', '')
    override_path = os.path.join(
        plugin_root, 'modules', 'frameworks', module, 'rules-override.json'
    )
    if os.path.isfile(override_path):
        try:
            with open(override_path) as f:
                return json.load(f)
        except (json.JSONDecodeError, KeyError):
            pass
    return {}


def run_layer1(filepath, language, overrides, project_root):
    """Run fast pattern checks (Layer 1)."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    patterns_dir = os.path.join(script_dir, 'layer-1-fast', 'patterns')
    pattern_file = os.path.join(patterns_dir, f'{language}.json')
    runner = os.path.join(script_dir, 'layer-1-fast', 'run-patterns.sh')
    if os.path.isfile(pattern_file) and os.path.isfile(runner):
        try:
            # Build command with optional override file
            cmd = [runner, filepath, pattern_file]
            override_file = _find_override(filepath, project_root)
            if override_file:
                cmd.append(override_file)
            result = subprocess.run(
                cmd, timeout=5, capture_output=True, text=True
            )
            if result.stdout:
                sys.stdout.write(result.stdout)
            if result.stderr:
                sys.stderr.write(result.stderr)
        except (subprocess.TimeoutExpired, OSError):
            pass


def _find_override(filepath, project_root):
    """Find the appropriate rules-override.json for a file."""
    plugin_root = os.environ.get('CLAUDE_PLUGIN_ROOT', '')
    if not project_root:
        return ''

    # Try component cache first
    cache_file = os.path.join(project_root, '.forge', '.component-cache')
    component = ''
    if os.path.isfile(cache_file):
        try:
            with open(cache_file) as f:
                for line in f:
                    line = line.strip()
                    if '=' in line:
                        prefix, comp = line.split('=', 1)
                        rel = os.path.relpath(filepath, project_root) if filepath.startswith(project_root) else filepath
                        if rel.startswith(prefix) or rel == prefix:
                            component = comp
                            break  # first match wins (consistency with engine.sh)
        except (IOError, ValueError):
            pass

    # Try detect_module if no component from cache
    if not component:
        forge_dir = os.path.join(project_root, '.forge')
        component = detect_module(filepath, forge_dir) or ''

    # Try module cache
    if not component:
        module_cache = os.path.join(project_root, '.forge', '.module-cache')
        if os.path.isfile(module_cache):
            try:
                with open(module_cache) as f:
                    component = f.read().strip()
            except IOError:
                pass

    if component and plugin_root:
        # Check per-component cached rules first
        rules_cache = os.path.join(project_root, '.forge', f'.rules-cache-{component}.json')
        if os.path.isfile(rules_cache):
            return rules_cache
        # Then framework's rules-override.json
        override = os.path.join(plugin_root, 'modules', 'frameworks', component, 'rules-override.json')
        if os.path.isfile(override):
            return override

    return ''


def _run_learned_rules(filepath, language, project_root):
    """Run learned rules (auto-promoted from retrospective) as additional Layer 1 pass."""
    plugin_root = os.environ.get('CLAUDE_PLUGIN_ROOT', '')
    if not plugin_root:
        return
    learned_rules = os.path.join(plugin_root, 'shared', 'checks', 'learned-rules-override.json')
    if not os.path.isfile(learned_rules):
        return
    script_dir = os.path.dirname(os.path.abspath(__file__))
    patterns_dir = os.path.join(script_dir, 'layer-1-fast', 'patterns')
    pattern_file = os.path.join(patterns_dir, f'{language}.json')
    runner = os.path.join(script_dir, 'layer-1-fast', 'run-patterns.sh')
    if os.path.isfile(pattern_file) and os.path.isfile(runner):
        try:
            result = subprocess.run(
                [runner, filepath, pattern_file, learned_rules],
                timeout=5, capture_output=True, text=True
            )
            if result.stdout:
                sys.stdout.write(result.stdout)
            if result.stderr:
                sys.stderr.write(result.stderr)
        except (subprocess.TimeoutExpired, OSError):
            pass


def run_layer2(filepath, language, overrides, project_root):
    """Run linter adapters (Layer 2)."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    runner = os.path.join(script_dir, 'layer-2-linter', 'run-linter.sh')
    severity_map = os.path.join(script_dir, 'layer-2-linter', 'config', 'severity-map.json')
    if os.path.isfile(runner) and os.access(runner, os.X_OK):
        try:
            result = subprocess.run(
                [runner, language, project_root, filepath, severity_map],
                timeout=30, capture_output=True, text=True
            )
            if result.stdout:
                sys.stdout.write(result.stdout)
            if result.stderr:
                sys.stderr.write(result.stderr)
        except (subprocess.TimeoutExpired, OSError):
            pass


def parse_args(argv):
    """Parse --hook, --verify, --review, --project-root, --files-changed."""
    args = {'mode': 'hook', 'project_root': '', 'files_changed': []}
    i = 0
    while i < len(argv):
        if argv[i] == '--hook':
            args['mode'] = 'hook'
        elif argv[i] == '--verify':
            args['mode'] = 'verify'
        elif argv[i] == '--review':
            args['mode'] = 'review'
        elif argv[i] == '--project-root' and i + 1 < len(argv):
            i += 1
            args['project_root'] = argv[i]
        elif argv[i] == '--files-changed':
            # Consume all following args until next --flag or end
            i += 1
            while i < len(argv) and not argv[i].startswith('--'):
                args['files_changed'].append(argv[i])
                i += 1
            continue  # Don't increment i again
        i += 1
    return args


if __name__ == '__main__':
    try:
        main()
    except Exception:
        sys.exit(0)  # Never block pipeline
