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


def load_or_reinit(path, story_id='', requirement='', mode='standard', dry_run=False):
    """Load state.json or auto-reset if not v2.0.0 (no migration shim per feedback_no_backcompat)."""
    import pathlib
    p = pathlib.Path(path)
    if not p.exists():
        s = create_initial_state(story_id, requirement, mode, dry_run)
        p.write_text(json.dumps(s, indent=2))
        return s
    try:
        s = json.loads(p.read_text(encoding='utf-8'))
    except Exception:
        s = create_initial_state(story_id, requirement, mode, dry_run)
        p.write_text(json.dumps(s, indent=2))
        return s
    if s.get('version') != STATE_SCHEMA_VERSION:
        # Per feedback_no_backcompat: no migration shim; start fresh.
        s = create_initial_state(story_id, requirement, mode, dry_run)
        p.write_text(json.dumps(s, indent=2))
    return s


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
