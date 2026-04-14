#!/usr/bin/env python3
"""Module-aware import resolution for build-code-graph.sh

Standalone entry point for the import resolution algorithm.
Can be invoked directly or imported as a library.

Usage:
    python3 resolve_imports_with_boundaries.py <db_path> [boundary_map_path]
"""
import json, sqlite3, sys, os


def resolve_imports(db_path, boundary_map_path=None):
    """Replace heuristic cross-file edges with module-aware resolution."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    # Load boundary map if available
    boundaries = None
    if boundary_map_path and os.path.exists(boundary_map_path):
        with open(boundary_map_path) as f:
            boundaries = json.load(f)

    # Get all imports
    imports = conn.execute("""
        SELECT imp.id, imp.name, imp.file_path, imp.language,
               src.id as src_file_id
        FROM nodes imp
        JOIN nodes src ON src.kind='File' AND src.file_path = imp.file_path
        WHERE imp.kind='Import'
    """).fetchall()

    # Build file index
    file_nodes = {}
    for row in conn.execute("SELECT id, name, file_path FROM nodes WHERE kind='File'"):
        file_nodes[row["file_path"]] = row["id"]

    # Build basename index for heuristic fallback
    basename_to_paths = {}
    for fp in file_nodes:
        bn = os.path.basename(fp)
        basename_to_paths.setdefault(bn, []).append(fp)

    resolved = 0
    heuristic = 0
    unresolved = 0

    for imp in imports:
        confidence, target_file_id = resolve_single_import(
            conn, imp, boundaries, file_nodes, basename_to_paths
        )
        if target_file_id:
            props = json.dumps({"confidence": confidence})
            conn.execute("""
                INSERT OR IGNORE INTO edges (edge_type, source_id, target_id, properties)
                VALUES ('IMPORTS', ?, ?, ?)
            """, (imp['src_file_id'], target_file_id, props))
            if confidence in ('resolved', 'module-inferred'):
                resolved += 1
            else:
                heuristic += 1
        else:
            unresolved += 1

    conn.commit()
    conn.close()

    # Output metrics
    print(json.dumps({
        "resolved": resolved,
        "heuristic": heuristic,
        "unresolved": unresolved
    }))


def resolve_single_import(conn, imp, boundaries, file_nodes, basename_to_paths):
    """Resolve a single import to a target file with confidence."""
    import_name = imp['name']
    source_file = imp['file_path']
    language = (imp['language'] or '').lower()

    candidates = generate_candidates(import_name, language)

    if boundaries:
        # Step 1: Find source module
        source_module = find_module_for_file(source_file, boundaries)

        if source_module:
            # Step 2: Try same-module resolution
            target = try_resolve_in_dirs(
                file_nodes, candidates, source_module.get('source_dirs', [])
            )
            if target:
                return ('resolved', target)

            # Step 3: Try declared dependency modules
            module_by_name = {m['name']: m for m in boundaries.get('modules', [])}
            for dep_name in source_module.get('depends_on', []):
                dep_module = module_by_name.get(dep_name)
                if dep_module:
                    target = try_resolve_in_dirs(
                        file_nodes, candidates, dep_module.get('source_dirs', [])
                    )
                    if target:
                        return ('resolved', target)

            # Step 4: Try any module (undeclared dependency)
            for mod in boundaries.get('modules', []):
                if mod['name'] == source_module.get('name'):
                    continue
                target = try_resolve_in_dirs(
                    file_nodes, candidates, mod.get('source_dirs', [])
                )
                if target:
                    return ('module-inferred', target)

    # Step 5: Heuristic fallback (basename matching)
    target = try_heuristic_resolve(
        file_nodes, basename_to_paths, import_name, source_file, language
    )
    if target:
        return ('heuristic', target)

    return (None, None)


def find_module_for_file(file_path, boundaries):
    for module in boundaries.get('modules', []):
        for src_dir in module.get('source_dirs', []) + module.get('test_dirs', []):
            if file_path.startswith(src_dir + '/') or file_path == src_dir:
                return module
    return None


def try_resolve_in_dirs(file_nodes, candidates, dirs):
    for candidate in candidates:
        for d in dirs:
            full_path = d + '/' + candidate if not candidate.startswith(d) else candidate
            if full_path in file_nodes:
                return file_nodes[full_path]
    return None


def generate_candidates(import_name, language):
    """Generate file path candidates from import name."""
    candidates = []

    if language in ('java', 'kotlin', 'scala'):
        path_base = import_name.replace('.', '/')
        for ext in ['.java', '.kt', '.scala']:
            candidates.append(path_base + ext)
        parts = import_name.rsplit('.', 1)
        if len(parts) == 2:
            for ext in ['.java', '.kt', '.scala']:
                candidates.append(parts[1] + ext)

    elif language == 'python':
        path_base = import_name.replace('.', '/')
        candidates.append(path_base + '.py')
        candidates.append(path_base + '/__init__.py')

    elif language == 'go':
        parts = import_name.split('/')
        if len(parts) >= 3:
            local_parts = parts[3:] if len(parts) > 3 else parts[-1:]
            candidates.append('/'.join(local_parts) + '/')

    elif language == 'rust':
        cleaned = import_name.replace('crate::', '').replace('::', '/')
        candidates.append('src/' + cleaned + '.rs')
        candidates.append('src/' + cleaned + '/mod.rs')

    elif language in ('typescript', 'javascript', 'tsx'):
        cleaned = import_name.lstrip('./').lstrip('@')
        for ext in ['.ts', '.tsx', '.js', '.jsx']:
            candidates.append(cleaned + ext)
        candidates.append(cleaned + '/index.ts')
        candidates.append(cleaned + '/index.js')

    elif language in ('c_sharp', 'csharp'):
        parts = import_name.split('.')
        for i in range(len(parts)):
            candidates.append('/'.join(parts[i:]) + '.cs')

    elif language == 'ruby':
        candidates.append(import_name.replace('::', '/') + '.rb')

    elif language in ('c', 'cpp'):
        candidates.append(import_name)

    else:
        candidates.append(import_name.replace('.', '/'))

    return candidates


def try_heuristic_resolve(file_nodes, basename_to_paths, import_name, source_file, language):
    """Basename-based heuristic matching as final fallback."""
    last_segment = import_name.rsplit('.', 1)[-1].rsplit('::', 1)[-1]
    extensions = [
        '.java', '.kt', '.py', '.go', '.rs', '.ts', '.tsx', '.js',
        '.cs', '.rb', '.scala', '.swift', '.cpp', '.c', '.h',
        '.php', '.dart', '.ex', '.exs'
    ]
    for ext in extensions:
        bn = last_segment + ext
        if bn in basename_to_paths:
            for fp in basename_to_paths[bn]:
                if fp != source_file:
                    return file_nodes[fp]
    return None


if __name__ == '__main__':
    db_path = sys.argv[1]
    boundary_path = sys.argv[2] if len(sys.argv) > 2 else None
    resolve_imports(db_path, boundary_path)
