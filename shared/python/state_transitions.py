#!/usr/bin/env python3
"""Forge state-machine transition engine.

Reads state JSON from stdin (avoids ARG_MAX).
Takes <event> <guards_json> <forge_dir> as argv.

Output (stdout): JSON with new_state, row_id, description, counters_changed,
                 previous_state, updated_state.
Exit 0 = transition found, Exit 1 = no match.
"""
import datetime
import json
import os
import sys

SCORE_EPSILON = 0.001


def score_gt(a, b):
    """a > b with epsilon tolerance."""
    return float(a) - float(b) > SCORE_EPSILON


def score_le(a, b):
    """a <= b with epsilon tolerance."""
    return float(a) - float(b) <= SCORE_EPSILON


def score_gte(a, b):
    """a >= b with epsilon tolerance (inclusive boundary)."""
    return float(a) - float(b) >= -SCORE_EPSILON


def score_eq(a, b):
    """a == b with epsilon tolerance."""
    return abs(float(a) - float(b)) < SCORE_EPSILON


# Risk level ordering for comparisons
RISK_ORDER = {'NONE': 0, 'LOW': 1, 'MEDIUM': 2, 'HIGH': 3, 'CRITICAL': 4}


def risk_le(a, b):
    """Return True if risk level a <= risk level b."""
    return RISK_ORDER.get(a, 99) <= RISK_ORDER.get(b, 99)


def make_guard_accessor(guards, state):
    """Return a function g(key, default) that checks guards first, then state."""
    def g(key, default=None):
        if key in guards:
            return guards[key]
        # Check dotted paths in state
        parts = key.split('.')
        obj = state
        for p in parts:
            if isinstance(obj, dict) and p in obj:
                obj = obj[p]
            else:
                return default
        return obj
    return g


def build_table(g, state, conv, conv_phase):
    """Build the complete transition table (57 normal + 9 error rows).

    Each entry: (current_state, event, guard_fn, next_state, row_id,
                 description, counter_changes, convergence_changes)
    """
    table = [
        # === PREFLIGHT ===
        # Row 1: PREFLIGHT + preflight_complete + dry_run=false -> EXPLORING
        ('PREFLIGHT', 'preflight_complete',
         lambda: g('dry_run', state.get('dry_run', False)) == False,
         'EXPLORING', '1', 'preflight_complete (dry_run=false)',
         {}, {}),
        # Row 2: PREFLIGHT + preflight_complete + dry_run=true -> EXPLORING
        ('PREFLIGHT', 'preflight_complete',
         lambda: g('dry_run', state.get('dry_run', False)) == True,
         'EXPLORING', '2', 'preflight_complete (dry_run=true)',
         {}, {}),
        # Row 3: PREFLIGHT + interrupted_run_detected + checkpoint_valid
        ('PREFLIGHT', 'interrupted_run_detected',
         lambda: g('checkpoint_valid', False) == True and g('no_git_drift', False) == True,
         '_RESUME_', '3', 'interrupted_run_detected (checkpoint valid, no drift)',
         {}, {}),
        # Row 4: PREFLIGHT + interrupted_run_detected + git_drift
        ('PREFLIGHT', 'interrupted_run_detected',
         lambda: g('git_drift_detected', False) == True,
         'PREFLIGHT', '4', 'interrupted_run_detected (git drift)',
         {}, {}),

        # === EXPLORING ===
        # Row 5: EXPLORING + explore_complete + scope < threshold -> PLANNING
        ('EXPLORING', 'explore_complete',
         lambda: int(g('scope', 0)) < int(g('decomposition_threshold', 3)),
         'PLANNING', '5', 'explore_complete (scope < threshold)',
         {}, {}),
        # Row 6: EXPLORING + explore_complete + scope >= threshold -> DECOMPOSED
        ('EXPLORING', 'explore_complete',
         lambda: int(g('scope', 0)) >= int(g('decomposition_threshold', 3)),
         'DECOMPOSED', '6', 'explore_complete (scope >= threshold)',
         {}, {}),
        # Row 7: EXPLORING + explore_timeout -> PLANNING
        ('EXPLORING', 'explore_timeout',
         lambda: True,
         'PLANNING', '7', 'explore_timeout',
         {}, {}),
        # Row 8: EXPLORING + explore_failure -> PLANNING
        ('EXPLORING', 'explore_failure',
         lambda: True,
         'PLANNING', '8', 'explore_failure',
         {}, {}),

        # === PLANNING ===
        # Row 9: PLANNING + plan_complete -> VALIDATING
        ('PLANNING', 'plan_complete',
         lambda: True,
         'VALIDATING', '9', 'plan_complete',
         {}, {}),

        # === VALIDATING ===
        # D1: VALIDATING + validate_complete + dry_run=true -> COMPLETE
        ('VALIDATING', 'validate_complete',
         lambda: g('dry_run', state.get('dry_run', False)) == True,
         'COMPLETE', 'D1', 'validate_complete (dry_run)',
         {}, {}),
        # Row 10: VALIDATING + verdict_GO + risk <= auto_proceed -> IMPLEMENTING
        ('VALIDATING', 'verdict_GO',
         lambda: risk_le(str(g('risk', 'LOW')), str(g('auto_proceed_risk', 'MEDIUM'))),
         'IMPLEMENTING', '10', 'verdict_GO (risk <= auto_proceed)',
         {}, {}),
        # Row 11: VALIDATING + verdict_GO + risk > auto_proceed -> VALIDATING (user gate)
        ('VALIDATING', 'verdict_GO',
         lambda: not risk_le(str(g('risk', 'LOW')), str(g('auto_proceed_risk', 'MEDIUM'))),
         'VALIDATING', '11', 'verdict_GO (risk > auto_proceed, user gate)',
         {}, {}),
        # Row 12: VALIDATING + user_approve_plan -> IMPLEMENTING
        ('VALIDATING', 'user_approve_plan',
         lambda: True,
         'IMPLEMENTING', '12', 'user_approve_plan',
         {}, {}),
        # Row 13: VALIDATING + user_revise_plan -> PLANNING
        ('VALIDATING', 'user_revise_plan',
         lambda: True,
         'PLANNING', '13', 'user_revise_plan',
         {}, {}),
        # Row 14: VALIDATING + verdict_REVISE + retries < max -> PLANNING
        ('VALIDATING', 'verdict_REVISE',
         lambda: int(g('validation_retries', state.get('validation_retries', 0))) < int(g('max_validation_retries', 3)),
         'PLANNING', '14', 'verdict_REVISE (retries < max)',
         {'validation_retries': '+1', 'total_retries': '+1'}, {}),
        # Row 15: VALIDATING + verdict_REVISE + retries >= max -> ESCALATED
        ('VALIDATING', 'verdict_REVISE',
         lambda: int(g('validation_retries', state.get('validation_retries', 0))) >= int(g('max_validation_retries', 3)),
         'ESCALATED', '15', 'verdict_REVISE (retries >= max)',
         {'validation_retries': '+1', 'total_retries': '+1'}, {}),
        # Row 16: VALIDATING + verdict_NOGO -> ESCALATED
        ('VALIDATING', 'verdict_NOGO',
         lambda: True,
         'ESCALATED', '16', 'verdict_NOGO',
         {}, {}),
        # Row 17: VALIDATING + contract_breaking + consumer_tasks -> IMPLEMENTING
        ('VALIDATING', 'contract_breaking',
         lambda: g('consumer_tasks_in_plan', False) == True,
         'IMPLEMENTING', '17', 'contract_breaking (consumer tasks in plan)',
         {}, {}),
        # Row 18: VALIDATING + contract_breaking + no consumer -> PLANNING
        ('VALIDATING', 'contract_breaking',
         lambda: g('consumer_tasks_in_plan', False) != True,
         'PLANNING', '18', 'contract_breaking (no consumer tasks)',
         {'validation_retries': '+1'}, {}),

        # === IMPLEMENTING ===
        # Row 19: IMPLEMENTING + implement_complete + at_least_one_passed -> VERIFYING
        ('IMPLEMENTING', 'implement_complete',
         lambda: g('at_least_one_task_passed', False) == True,
         'VERIFYING', '19', 'implement_complete (at least one passed)',
         {}, {}),
        # Row 21: IMPLEMENTING + implement_complete + all_failed -> ESCALATED
        ('IMPLEMENTING', 'implement_complete',
         lambda: g('all_tasks_failed', g('at_least_one_task_passed', True) != True) == True,
         'ESCALATED', '21', 'implement_complete (all tasks failed)',
         {}, {}),

        # === VERIFYING ===
        # Row 22: VERIFYING + phase_a_failure + within limits -> IMPLEMENTING
        ('VERIFYING', 'phase_a_failure',
         lambda: (int(g('verify_fix_count', state.get('verify_fix_count', 0))) < int(g('max_fix_loops', 3))
                  and int(g('total_iterations', conv.get('total_iterations', 0))) < int(g('max_iterations', 8))),
         'IMPLEMENTING', '22', 'phase_a_failure (within limits)',
         {'verify_fix_count': '+1', 'convergence.total_iterations': '+1', 'total_retries': '+1'}, {}),
        # Row 23: VERIFYING + phase_a_failure + limits reached -> ESCALATED
        ('VERIFYING', 'phase_a_failure',
         lambda: (int(g('verify_fix_count', state.get('verify_fix_count', 0))) >= int(g('max_fix_loops', 3))
                  or int(g('total_iterations', conv.get('total_iterations', 0))) >= int(g('max_iterations', 8))),
         'ESCALATED', '23', 'phase_a_failure (limits reached)',
         {}, {}),
        # Row 24: VERIFYING + tests_fail + within limits -> IMPLEMENTING
        ('VERIFYING', 'tests_fail',
         lambda: (int(g('phase_iterations', conv.get('phase_iterations', 0))) < int(g('max_test_cycles', 5))
                  and int(g('total_iterations', conv.get('total_iterations', 0))) < int(g('max_iterations', 8))),
         'IMPLEMENTING', '24', 'tests_fail (within limits)',
         {'convergence.phase_iterations': '+1', 'convergence.total_iterations': '+1', 'total_retries': '+1'}, {}),
        # Row 25: VERIFYING + tests_fail + limits reached -> ESCALATED
        ('VERIFYING', 'tests_fail',
         lambda: (int(g('phase_iterations', conv.get('phase_iterations', 0))) >= int(g('max_test_cycles', 5))
                  or int(g('total_iterations', conv.get('total_iterations', 0))) >= int(g('max_iterations', 8))),
         'ESCALATED', '25', 'tests_fail (limits reached)',
         {}, {}),
        # Row 26: VERIFYING + verify_pass + phase=correctness -> REVIEWING
        ('VERIFYING', 'verify_pass',
         lambda: g('convergence.phase', conv_phase) == 'correctness',
         'REVIEWING', '26', 'verify_pass (correctness -> perfection)',
         {}, {'phase': 'perfection', 'phase_iterations': 0}),
        # Row 27: VERIFYING + verify_pass + phase=safety_gate -> DOCUMENTING
        ('VERIFYING', 'verify_pass',
         lambda: g('convergence.phase', conv_phase) == 'safety_gate',
         'DOCUMENTING', '27', 'verify_pass (safety_gate -> docs)',
         {}, {'safety_gate_passed': True}),
        # Row 28: VERIFYING + safety_gate_fail + failures < 2 -> IMPLEMENTING
        ('VERIFYING', 'safety_gate_fail',
         lambda: int(g('safety_gate_failures', conv.get('safety_gate_failures', 0))) < 2,
         'IMPLEMENTING', '28', 'safety_gate_fail (< 2)',
         {'convergence.total_iterations': '+1'},
         {'phase': 'correctness', 'phase_iterations': 0, 'plateau_count': 0,
          'last_score_delta': 0, 'convergence_state': 'IMPROVING', 'safety_gate_failures': '+1'}),
        # Row 29: VERIFYING + safety_gate_fail + failures >= 2 -> ESCALATED
        ('VERIFYING', 'safety_gate_fail',
         lambda: int(g('safety_gate_failures', conv.get('safety_gate_failures', 0))) >= 2,
         'ESCALATED', '29', 'safety_gate_fail (>= 2, oscillation)',
         {}, {}),

        # === REVIEWING ===
        # Row 30: REVIEWING + score_target_reached -> VERIFYING
        ('REVIEWING', 'score_target_reached',
         lambda: True,
         'VERIFYING', '30', 'score_target_reached',
         {}, {'phase': 'safety_gate'}),
        # Row 31: REVIEWING + score_improving + within iterations -> IMPLEMENTING
        ('REVIEWING', 'score_improving',
         lambda: int(g('total_iterations', conv.get('total_iterations', 0))) < int(g('max_iterations', 8)),
         'IMPLEMENTING', '31', 'score_improving (within iterations)',
         {'convergence.phase_iterations': '+1', 'convergence.total_iterations': '+1',
          'quality_cycles': '+1', 'total_retries': '+1'},
         {'plateau_count': 0}),
        # Row 32: REVIEWING + score_improving + iterations exhausted -> ESCALATED
        ('REVIEWING', 'score_improving',
         lambda: int(g('total_iterations', conv.get('total_iterations', 0))) >= int(g('max_iterations', 8)),
         'ESCALATED', '32', 'score_improving (iterations exhausted)',
         {}, {}),
        # Row 33: REVIEWING + score_plateau + phase_iterations >= 2 + patience reached + score >= pass -> VERIFYING (safety_gate)
        ('REVIEWING', 'score_plateau',
         lambda: (int(g('phase_iterations', conv.get('phase_iterations', 0))) >= 2
                  and int(g('plateau_count', conv.get('plateau_count', 0))) >= int(g('plateau_patience', 3))
                  and int(g('score', 0)) >= int(g('pass_threshold', 80))),
         'VERIFYING', '33', 'score_plateau (patience reached, score >= pass)',
         {}, {'phase': 'safety_gate'}),
        # Row 34: REVIEWING + score_plateau + phase_iterations >= 2 + patience reached + concerns range -> ESCALATED
        ('REVIEWING', 'score_plateau',
         lambda: (int(g('phase_iterations', conv.get('phase_iterations', 0))) >= 2
                  and int(g('plateau_count', conv.get('plateau_count', 0))) >= int(g('plateau_patience', 3))
                  and int(g('score', 0)) >= int(g('concerns_threshold', 60))
                  and int(g('score', 0)) < int(g('pass_threshold', 80))),
         'ESCALATED', '34', 'score_plateau (patience reached, concerns range)',
         {}, {}),
        # Row 35: REVIEWING + score_plateau + phase_iterations >= 2 + patience reached + score < concerns -> ESCALATED
        ('REVIEWING', 'score_plateau',
         lambda: (int(g('phase_iterations', conv.get('phase_iterations', 0))) >= 2
                  and int(g('plateau_count', conv.get('plateau_count', 0))) >= int(g('plateau_patience', 3))
                  and int(g('score', 0)) < int(g('concerns_threshold', 60))),
         'ESCALATED', '35', 'score_plateau (patience reached, score < concerns)',
         {}, {}),
        # Row 36: REVIEWING + score_plateau + phase_iterations >= 2 + within patience + within iterations -> IMPLEMENTING
        ('REVIEWING', 'score_plateau',
         lambda: (int(g('phase_iterations', conv.get('phase_iterations', 0))) >= 2
                  and int(g('plateau_count', conv.get('plateau_count', 0))) < int(g('plateau_patience', 3))
                  and int(g('total_iterations', conv.get('total_iterations', 0))) < int(g('max_iterations', 8))),
         'IMPLEMENTING', '36', 'score_plateau (within patience)',
         {'convergence.plateau_count': '+1', 'convergence.phase_iterations': '+1',
          'convergence.total_iterations': '+1', 'total_retries': '+1'}, {}),
        # Row 36a: REVIEWING + score_plateau + phase_iterations < 2 (baseline exempt) -> IMPLEMENTING
        ('REVIEWING', 'score_plateau',
         lambda: (int(g('phase_iterations', conv.get('phase_iterations', 0))) < 2),
         'IMPLEMENTING', '36a', 'score_plateau (first 2 cycles exempt, establishing baseline)',
         {'convergence.phase_iterations': '+1', 'convergence.plateau_count': '=0',
          'convergence.total_iterations': '+1', 'total_retries': '+1'}, {}),
        # Row 51: REVIEWING + score_plateau + within patience + iteration cap reached -> ESCALATED
        ('REVIEWING', 'score_plateau',
         lambda: (int(g('phase_iterations', conv.get('phase_iterations', 0))) >= 2
                  and int(g('plateau_count', conv.get('plateau_count', 0))) < int(g('plateau_patience', 3))
                  and int(g('total_iterations', conv.get('total_iterations', 0))) >= int(g('max_iterations', 8))),
         'ESCALATED', '51', 'score_plateau (within patience + iteration cap reached)',
         {}, {}),
        # Row 37: REVIEWING + score_regressing + beyond tolerance -> ESCALATED
        ('REVIEWING', 'score_regressing',
         lambda: score_gte(abs(float(g('delta', 0))), int(g('oscillation_tolerance', state.get('oscillation_tolerance', 5)))),
         'ESCALATED', '37', 'score_regressing (beyond tolerance)',
         {}, {'convergence_state': 'REGRESSING'}),

        # === DOCUMENTING ===
        # Row 38: DOCUMENTING + docs_complete -> SHIPPING
        ('DOCUMENTING', 'docs_complete',
         lambda: True,
         'SHIPPING', '38', 'docs_complete',
         {}, {}),
        # Row 39: DOCUMENTING + docs_failure -> SHIPPING
        ('DOCUMENTING', 'docs_failure',
         lambda: True,
         'SHIPPING', '39', 'docs_failure',
         {}, {}),

        # === SHIPPING ===
        # Row 40: SHIPPING + evidence_SHIP + fresh -> SHIPPING (PR creation)
        ('SHIPPING', 'evidence_SHIP',
         lambda: g('evidence_fresh', True) == True,
         'SHIPPING', '40', 'evidence_SHIP (fresh)',
         {}, {}),
        # Row 41: SHIPPING + evidence_SHIP + stale + refresh_count < 3 -> SHIPPING (re-verify)
        ('SHIPPING', 'evidence_SHIP',
         lambda: g('evidence_fresh', True) != True and int(g('evidence_refresh_count', state.get('evidence_refresh_count', 0))) < 3,
         'SHIPPING', '41', 'evidence_SHIP (stale, re-verify)',
         {'evidence_refresh_count': '+1'}, {}),
        # Row 52: SHIPPING + evidence_SHIP + stale + refresh_count >= 3 -> ESCALATED (loop cap)
        ('SHIPPING', 'evidence_SHIP',
         lambda: g('evidence_fresh', True) != True and int(g('evidence_refresh_count', state.get('evidence_refresh_count', 0))) >= 3,
         'ESCALATED', '52', 'evidence_SHIP (stale, refresh loop cap)',
         {}, {}),
        # Row 42: SHIPPING + evidence_BLOCK + build/lint/tests -> IMPLEMENTING
        ('SHIPPING', 'evidence_BLOCK',
         lambda: g('block_reason', '') in ('build', 'lint', 'tests'),
         'IMPLEMENTING', '42', 'evidence_BLOCK (build/lint/tests)',
         {}, {'phase': 'correctness'}),
        # Row 43: SHIPPING + evidence_BLOCK + review/score -> IMPLEMENTING
        ('SHIPPING', 'evidence_BLOCK',
         lambda: g('block_reason', '') in ('review', 'score'),
         'IMPLEMENTING', '43', 'evidence_BLOCK (review/score)',
         {}, {'phase': 'perfection'}),
        # Row 44: SHIPPING + pr_created -> SHIPPING (user gate)
        ('SHIPPING', 'pr_created',
         lambda: True,
         'SHIPPING', '44', 'pr_created (user gate)',
         {}, {}),
        # Row 45: SHIPPING + user_approve_pr -> LEARNING
        ('SHIPPING', 'user_approve_pr',
         lambda: True,
         'LEARNING', '45', 'user_approve_pr',
         {}, {}),
        # Row 46: SHIPPING + pr_rejected + implementation -> IMPLEMENTING
        ('SHIPPING', 'pr_rejected',
         lambda: g('feedback_classification', state.get('feedback_classification', '')) == 'implementation',
         'IMPLEMENTING', '46', 'pr_rejected (implementation)',
         {'total_retries': '+1'}, {'quality_cycles': '=0', 'test_cycles': '=0'}),
        # Row 47: SHIPPING + pr_rejected + design -> PLANNING
        ('SHIPPING', 'pr_rejected',
         lambda: g('feedback_classification', state.get('feedback_classification', '')) == 'design',
         'PLANNING', '47', 'pr_rejected (design)',
         {'total_retries': '+1'},
         {'quality_cycles': '=0', 'test_cycles': '=0', 'verify_fix_count': '=0', 'validation_retries': '=0'}),
        # Row 48: SHIPPING + feedback_loop_detected + count >= 2 -> ESCALATED
        ('SHIPPING', 'feedback_loop_detected',
         lambda: int(g('feedback_loop_count', state.get('feedback_loop_count', 0))) >= 2,
         'ESCALATED', '48', 'feedback_loop_detected (count >= 2)',
         {}, {}),

        # === LEARNING ===
        # Row 49: LEARNING + retrospective_complete -> COMPLETE
        ('LEARNING', 'retrospective_complete',
         lambda: True,
         'COMPLETE', '49', 'retrospective_complete',
         {}, {}),

        # === Row 50: Diminishing returns ===
        ('REVIEWING', 'score_diminishing',
         lambda: int(g('diminishing_count', conv.get('diminishing_count', 0))) >= 2 and int(g('score', 0)) >= int(g('pass_threshold', 80)),
         'VERIFYING', '50', 'score_diminishing (count >= 2, score >= pass)',
         {}, {'phase': 'safety_gate'}),
    ]

    # Error transitions (from ANY state) -- checked first for priority
    error_table = [
        # E1: ANY + budget_exhausted -> ESCALATED
        ('ANY', 'budget_exhausted',
         lambda: int(g('total_retries', state.get('total_retries', 0))) >= int(g('total_retries_max', state.get('total_retries_max', 10))),
         'ESCALATED', 'E1', 'budget_exhausted',
         {}, {}),
        # E2: ANY + recovery_budget_exhausted -> ESCALATED
        ('ANY', 'recovery_budget_exhausted',
         lambda: True,
         'ESCALATED', 'E2', 'recovery_budget_exhausted',
         {}, {}),
        # E3: ANY + circuit_breaker_open -> ESCALATED
        ('ANY', 'circuit_breaker_open',
         lambda: True,
         'ESCALATED', 'E3', 'circuit_breaker_open',
         {}, {}),
        # E4: ANY + unrecoverable_error -> ESCALATED
        ('ANY', 'unrecoverable_error',
         lambda: True,
         'ESCALATED', 'E4', 'unrecoverable_error',
         {}, {}),
        # E5: ANY (ESCALATED) + user_continue -> previous state
        ('ANY', 'user_continue',
         lambda: True,
         '_PREVIOUS_', 'E5', 'user_continue (resume from escalation)',
         {}, {}),
        # E6: ANY (ESCALATED) + user_abort -> ABORTED
        ('ANY', 'user_abort',
         lambda: True,
         'ABORTED', 'E6', 'user_abort',
         {}, {}),
        # E7: ANY (ESCALATED) + user_reshape -> PLANNING
        ('ANY', 'user_reshape',
         lambda: True,
         'PLANNING', 'E7', 'user_reshape',
         {}, {}),
        # E9: ANY (not COMPLETE, not ABORTED) + user_abort_direct -> ABORTED
        ('ANY', 'user_abort_direct',
         lambda: state.get('story_state', '') not in ('COMPLETE', 'ABORTED'),
         'ABORTED', 'E9', 'user_abort_direct (from /forge-abort)',
         {}, {}),
        # E8: ANY + token_budget_exhausted -> ESCALATED
        ('ANY', 'token_budget_exhausted',
         lambda: int(g('estimated_total', state.get('tokens', {}).get('estimated_total', 0))) >= int(g('budget_ceiling', state.get('tokens', {}).get('budget_ceiling', 0))) and int(g('budget_ceiling', state.get('tokens', {}).get('budget_ceiling', 0))) > 0,
         'ESCALATED', 'E8', 'token_budget_exhausted',
         {}, {}),
        # R1 (time-travel): ANY + recovery_op_rewind -> REWINDING (pseudo-state)
        # REWINDING is transient: story_state is NOT persisted as REWINDING.
        # The orchestrator brackets the CAS rewind op with StateTransitionEvent
        # pairs for audit; the actual commit/abort resolves via R2/R3 below.
        ('ANY', 'recovery_op_rewind',
         lambda: True,
         'REWINDING', 'R1', 'recovery_op_rewind (enter REWINDING pseudo-state)',
         {}, {}),
        # R2 (time-travel): REWINDING + rewind_commit_success -> target story_state
        # Resolved programmatically by the orchestrator (next_state depends on
        # the captured checkpoint's story_state); _PREVIOUS_ is a safe fallback
        # when the CAS-restored state.json already carries the target value.
        ('REWINDING', 'rewind_commit_success',
         lambda: True,
         '_PREVIOUS_', 'R2', 'rewind_commit_success (CAS restore OK, story_state set from checkpoint)',
         {}, {}),
        # R3 (time-travel): REWINDING + rewind_abort -> prior story_state
        # Exit 5 (dirty) / 6 (unknown id) / 7 (tx collision) surfaced via
        # AskUserQuestion by the orchestrator.
        ('REWINDING', 'rewind_abort',
         lambda: True,
         '_PREVIOUS_', 'R3', 'rewind_abort (CAS restore failed, zero side effects)',
         {}, {}),
    ]

    return table, error_table


def match_transition(event, state, guards):
    """Find and return the first matching transition row, or None."""
    current = state['story_state']
    conv = state.get('convergence', {})
    conv_phase = conv.get('phase', 'correctness')
    g = make_guard_accessor(guards, state)

    table, error_table = build_table(g, state, conv, conv_phase)

    # Check error transitions first (they match ANY state)
    for row in error_table:
        r_state, r_event, r_guard, r_next, r_id, r_desc, r_counters, r_conv = row
        if r_event == event:
            try:
                if r_guard():
                    return row
            except (ValueError, TypeError, KeyError):
                continue

    # Check normal transitions
    for row in table:
        r_state, r_event, r_guard, r_next, r_id, r_desc, r_counters, r_conv = row
        if r_state == current and r_event == event:
            try:
                if r_guard():
                    return row
            except (ValueError, TypeError, KeyError):
                continue

    return None


def apply_changes(matched, state, guards, forge_dir):
    """Apply counter/convergence changes and return the result dict."""
    current = state['story_state']
    conv = state.get('convergence', {})
    r_state, r_event, r_guard, r_next, r_id, r_desc, r_counters, r_conv = matched

    # Resolve special next_state values
    new_state = r_next
    if new_state == '_PREVIOUS_':
        new_state = state.get('previous_state', current)
    elif new_state == '_RESUME_':
        new_state = state.get('resume_state', current)

    # Apply counter changes
    counters_changed = {}
    for key, change in r_counters.items():
        parts = key.split('.')
        if len(parts) == 2 and parts[0] == 'convergence':
            field = parts[1]
            old_val = conv.get(field, 0)
            if change == '+1':
                new_val = old_val + 1
            elif change == '=0':
                new_val = 0
            else:
                new_val = int(change)
            state['convergence'][field] = new_val
            counters_changed[field] = new_val
        else:
            old_val = state.get(key, 0)
            if change == '+1':
                new_val = old_val + 1
            elif change == '=0':
                new_val = 0
            else:
                new_val = int(change)
            state[key] = new_val
            counters_changed[key] = new_val

    # Apply convergence changes
    for key, change in r_conv.items():
        # Handle top-level state fields referenced in convergence_changes
        if key in ('quality_cycles', 'test_cycles', 'verify_fix_count', 'validation_retries'):
            if change == '=0':
                state[key] = 0
                counters_changed[key] = 0
            elif change == '+1':
                state[key] = state.get(key, 0) + 1
                counters_changed[key] = state[key]
            continue
        # Handle convergence sub-fields
        if isinstance(change, str) and change == '+1':
            old = conv.get(key, 0)
            state['convergence'][key] = old + 1
            counters_changed[key] = old + 1
        elif isinstance(change, str) and change == '=0':
            state['convergence'][key] = 0
            counters_changed[key] = 0
        else:
            state['convergence'][key] = change

    # Update story_state
    if new_state == 'COMPLETE':
        state['story_state'] = new_state
        state['complete'] = True
    elif new_state == 'ABORTED' and r_id == 'E9':
        state['story_state'] = new_state
        state['abort_reason'] = 'user abort (direct)'
        try:
            state['abort_timestamp'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        except AttributeError:
            state['abort_timestamp'] = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
    else:
        state['story_state'] = new_state

    # Build output
    output = {
        'new_state': new_state,
        'row_id': r_id,
        'description': r_desc,
        'counters_changed': counters_changed,
        'previous_state': current,
    }

    # Decision log entry
    try:
        ts = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    except AttributeError:
        ts = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
    decision = {
        'ts': ts,
        'agent': 'fg-100-orchestrator',
        'decision': 'state_transition',
        'input': {'state': current, 'event': matched[1], 'guards': guards},
        'choice': new_state,
        'reason': f'Row {r_id}: {r_desc}',
        'alternatives': [],
    }

    # Write decision log
    decisions_path = os.path.join(forge_dir, 'decisions.jsonl')
    try:
        os.makedirs(forge_dir, exist_ok=True)
        with open(decisions_path, 'a') as f:
            f.write(json.dumps(decision) + '\n')
    except OSError:
        pass  # Non-fatal: decision log is informational

    # Persist previous_state for user_continue (E5) recovery
    state['previous_state'] = current

    # Write updated state to temp file for bash to pick up
    state_tmp = os.path.join(forge_dir, '.state-transition.tmp')
    try:
        with open(state_tmp, 'w') as f:
            json.dump(state, f, indent=2)
    except OSError:
        pass  # Non-fatal: caller can read updated_state from stdout

    # Size caps — prevent unbounded growth
    if len(state.get('score_history', [])) > 50:
        state['score_history'] = state['score_history'][-50:]
    conv_data = state.get('convergence', {})
    if len(conv_data.get('phase_history', [])) > 20:
        conv_data['phase_history'] = conv_data['phase_history'][-20:]
    rb = state.get('recovery_budget', {})
    if len(rb.get('applications', [])) > 30:
        rb['applications'] = rb['applications'][-30:]

    # Include the updated state in stdout output
    output['updated_state'] = state

    return output


if __name__ == '__main__':
    if len(sys.argv) != 4:
        print(
            f"Usage: {sys.argv[0]} <event> <guards_json> <forge_dir>",
            file=sys.stderr,
        )
        print("State JSON is read from stdin.", file=sys.stderr)
        sys.exit(1)

    event = sys.argv[1]
    guards = json.loads(sys.argv[2])
    forge_dir = sys.argv[3]

    state = json.load(sys.stdin)

    matched = match_transition(event, state, guards)

    if matched is None:
        current = state['story_state']
        result = {
            'error': f'No transition for (state={current}, event={event})',
            'current_state': current,
            'event': event,
            'guards': guards,
        }
        print(json.dumps(result), file=sys.stderr)
        sys.exit(1)

    output = apply_changes(matched, state, guards, forge_dir)
    print(json.dumps(output))
