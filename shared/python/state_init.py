#!/usr/bin/env python3
"""Create the initial v2.0.0 forge pipeline state object.

Interface:
    state_init.py <story_id> <requirement> <mode> <dry_run>

Output: JSON to stdout (complete v2.0.0 state object)
Exit codes: 0 = success, 1 = invalid args
"""
import json
import sys

VALID_MODES = (
    'standard',
    'bugfix',
    'migration',
    'bootstrap',
    'testing',
    'refactor',
    'performance',
)


def create_initial_state(story_id, requirement, mode, dry_run):
    """Return the full v2.0.0 state dict."""
    return {
        'version': '2.0.0',
        '_seq': 0,
        'complete': False,
        'story_id': story_id,
        'requirement': requirement,
        'domain_area': '',
        'risk_level': '',
        'previous_state': '',
        'story_state': 'PREFLIGHT',
        'active_component': '',
        'components': {},
        'quality_cycles': 0,
        'test_cycles': 0,
        'verify_fix_count': 0,
        'validation_retries': 0,
        'total_retries': 0,
        'total_retries_max': 10,
        'stage_timestamps': {},
        'last_commit_sha': '',
        'preempt_items_applied': [],
        'preempt_items_status': {},
        'feedback_classification': '',
        'previous_feedback_classification': '',
        'feedback_loop_count': 0,
        'score_history': [],
        'convergence': {
            'phase': 'correctness',
            'phase_iterations': 0,
            'total_iterations': 0,
            'plateau_count': 0,
            'last_score_delta': 0,
            'convergence_state': 'IMPROVING',
            'phase_history': [],
            'safety_gate_passed': False,
            'safety_gate_failures': 0,
            'unfixable_findings': [],
            'diminishing_count': 0,
            'unfixable_info_count': 0,
        },
        'integrations': {
            'linear': {'available': False, 'team': ''},
            'playwright': {'available': False},
            'slack': {'available': False},
            'figma': {'available': False},
            'excalidraw': {'available': False},
            'context7': {'available': False},
            'neo4j': {'available': False, 'last_build_sha': '', 'node_count': 0},
        },
        'linear': {'epic_id': '', 'story_ids': [], 'task_ids': {}},
        'linear_sync': {'in_sync': True, 'failed_operations': []},
        'modules': [],
        'cost': {'wall_time_seconds': 0, 'stages_completed': 0, 'stage_times': {}},
        'recovery_budget': {'total_weight': 0.0, 'max_weight': 5.5, 'applications': []},
        'recovery': {
            'total_failures': 0,
            'total_recoveries': 0,
            'degraded_capabilities': [],
            'failures': [],
            'budget_warning_issued': False,
            'circuit_breakers': {},
        },
        'scout_improvements': 0,
        'evidence_refresh_count': 0,
        'conventions_hash': '',
        'conventions_section_hashes': {},
        'detected_versions': {},
        'check_engine_skipped': 0,
        'mode': mode,
        'dry_run': dry_run,
        'autonomous': False,
        'shallow_clone': False,
        'cross_repo': {},
        'spec': None,
        'ticket_id': None,
        'branch_name': '',
        'tracking_dir': None,
        'documentation': {},
        'bugfix': None,
        'graph': {'last_update_stage': -1, 'last_update_files': [], 'stale': False},
        'plan_judge_loops': 0,
        'impl_judge_loops': {},
        'judge_verdicts': [],
        'current_plan_sha': None,
        'schema_version_history': [],
    }


STATE_SCHEMA_VERSION = '2.0.0'


def _atomic_write(path, data):
    """Write JSON atomically: write to .tmp then os.replace.

    os.replace is atomic on POSIX and on Windows (Python 3.3+). Crash between
    the two operations leaves either the old file intact or a stray .tmp the
    next writer overwrites.
    """
    import os
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(data, indent=2), encoding='utf-8')
    os.replace(tmp, path)


def _acquire_lock(forge_dir):
    """Acquire .forge/.lock under fcntl.flock (POSIX) or skip (Windows).

    Returns the lock file handle (caller must close to release) or None when
    locking is unavailable. We use a non-blocking acquire and busy-wait once,
    matching the 24h stale-timeout policy documented in CLAUDE.md (the timeout
    itself is enforced elsewhere; here we only serialize concurrent writers
    in-process / across processes that respect flock).
    """
    import sys
    import time
    lock_path = forge_dir / '.lock'
    try:
        fh = lock_path.open('a+')
    except OSError:
        return None
    if sys.platform == 'win32':
        # No fcntl on Windows; rely on file-existence check at the caller.
        # We still hold the handle so the file is visible.
        return fh
    try:
        import fcntl
    except ImportError:
        return fh
    deadline = time.monotonic() + 5.0
    while True:
        try:
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fh
        except OSError:
            if time.monotonic() >= deadline:
                fh.close()
                return None
            time.sleep(0.05)


def _release_lock(fh):
    if fh is None:
        return
    try:
        import sys
        if sys.platform != 'win32':
            try:
                import fcntl
                fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
            except (ImportError, OSError):
                pass
    finally:
        try:
            fh.close()
        except OSError:
            pass


def _record_reinit(forge_dir, reason, old_version):
    """Best-effort failure_log entry for a state reinit. Never raises.

    Locates `hooks/_py/failure_log.py` relative to this file (plugin layout)
    so the call works from any project where state_init.py is invoked as a
    module under shared/python/.
    """
    try:
        import sys
        import pathlib
        plugin_root = pathlib.Path(__file__).resolve().parent.parent.parent
        sys.path.insert(0, str(plugin_root / 'hooks' / '_py'))
        from failure_log import record_failure  # type: ignore
        record_failure(
            hook_name='state_init.load_or_reinit',
            matcher=reason,
            exit_code=0,
            stderr_excerpt=f'reinit from version={old_version!r} to {STATE_SCHEMA_VERSION}',
            duration_ms=0,
            cwd=str(forge_dir.parent),
        )
    except Exception:
        pass


def load_or_reinit(path, story_id='', requirement='', mode='standard', dry_run=False):
    """Load state.json or auto-reset if not v2.0.0 (no migration shim per feedback_no_backcompat).

    Concurrency-safe: acquires .forge/.lock (fcntl.flock on POSIX) and writes
    via .tmp + os.replace to avoid two concurrent processes both detecting a
    stale version and overwriting each other.
    """
    import pathlib
    p = pathlib.Path(path)
    forge_dir = p.parent
    try:
        forge_dir.mkdir(parents=True, exist_ok=True)
    except OSError:
        pass
    lock = _acquire_lock(forge_dir)
    try:
        if not p.exists():
            s = create_initial_state(story_id, requirement, mode, dry_run)
            _atomic_write(p, s)
            return s
        try:
            s = json.loads(p.read_text(encoding='utf-8'))
        except Exception:
            old_version = None
            try:
                # Best-effort backup of corrupt file before overwriting.
                backup = forge_dir / 'state.v1.bak'
                backup.write_bytes(p.read_bytes())
            except OSError:
                pass
            _record_reinit(forge_dir, 'corrupt_json', old_version)
            s = create_initial_state(story_id, requirement, mode, dry_run)
            _atomic_write(p, s)
            return s
        if s.get('version') != STATE_SCHEMA_VERSION:
            old_version = s.get('version')
            try:
                backup = forge_dir / 'state.v1.bak'
                backup.write_text(json.dumps(s, indent=2), encoding='utf-8')
            except OSError:
                pass
            _record_reinit(forge_dir, 'version_mismatch', old_version)
            s = create_initial_state(story_id, requirement, mode, dry_run)
            _atomic_write(p, s)
        return s
    finally:
        _release_lock(lock)


if __name__ == '__main__':
    if len(sys.argv) != 5:
        print(
            f"Usage: {sys.argv[0]} <story_id> <requirement> <mode> <dry_run>",
            file=sys.stderr,
        )
        sys.exit(1)

    story_id = sys.argv[1]
    requirement = sys.argv[2]
    mode = sys.argv[3]
    dry_run_str = sys.argv[4]

    if mode not in VALID_MODES:
        print(
            f"ERROR: invalid mode '{mode}'. Must be one of: {', '.join(VALID_MODES)}",
            file=sys.stderr,
        )
        sys.exit(1)

    dry_run = dry_run_str == 'true'

    state = create_initial_state(story_id, requirement, mode, dry_run)
    print(json.dumps(state, indent=2))
