#!/usr/bin/env python3
"""State schema migration: applies sequential migrations to bring state.json up to date."""
import datetime
import json
import sys

CURRENT_VERSION = '1.6.0'


def migrate_1_5_0_to_1_6_0(state):
    """Add fields introduced in v1.6.0.

    This is the single migration for all v2.7.0 changes.
    All new fields across all phases are added here.
    """
    # Circuit breaker tracking (Phase 4)
    recovery = state.setdefault('recovery', {})
    recovery.setdefault('circuit_breakers', {})

    # Planning critic counter (Phase 5)
    state.setdefault('critic_revisions', 0)

    # Schema migration history (capped at 20 entries)
    history = state.setdefault('schema_version_history', [])
    history.append({
        'from': '1.5.0',
        'to': '1.6.0',
        'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
    })
    if len(history) > 20:
        state['schema_version_history'] = history[-20:]

    state['version'] = '1.6.0'
    return state


MIGRATIONS = {
    '1.5.0': migrate_1_5_0_to_1_6_0,
}


def migrate(state):
    """Apply all needed migrations to reach CURRENT_VERSION."""
    version = state.get('version', '1.5.0')
    if version == CURRENT_VERSION:
        return state
    while version != CURRENT_VERSION:
        if version not in MIGRATIONS:
            print(f"ERROR: No migration path from {version}", file=sys.stderr)
            sys.exit(2)
        state = MIGRATIONS[version](state)
        version = state['version']
    return state


if __name__ == '__main__':
    try:
        state = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    result = migrate(state)
    print(json.dumps(result, indent=2))
