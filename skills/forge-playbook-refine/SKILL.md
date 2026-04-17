---
name: forge-playbook-refine
description: "[writes] Review and apply playbook refinement proposals. Use when playbooks have accumulated run data and proposals are ready for review. Trigger: /forge-playbook-refine [playbook_id]"
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'AskUserQuestion']
ui: { ask: true }
---

# /forge-playbook-refine — Interactive Playbook Refinement

Review and apply improvement proposals generated from pipeline run data. Proposals are evidence-backed suggestions for making playbooks produce better code.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Prerequisites

1. **Forge initialized:** `.claude/forge.local.md` exists
2. **Run history exists:** `.forge/run-history.db` exists
3. **Proposals available:** `.forge/playbook-refinements/` has at least one file

If prerequisites fail, STOP with guidance:
- No run history → "Run the pipeline first to generate data."
- No proposals → "No refinement proposals yet. Run playbooks 3+ times to generate proposals."

## Arguments

`$ARGUMENTS` = optional playbook_id. If omitted, list playbooks with pending proposals.

## Instructions

### No playbook_id provided

1. List all `.forge/playbook-refinements/*.json` files
2. For each, show: playbook_id, proposal count, confidence distribution
3. Ask user to select one

### Playbook selected

1. Read `.forge/playbook-refinements/{playbook_id}.json`
2. Filter to `status: ready` proposals only
3. If no ready proposals: "All proposals for {playbook_id} have been processed."
4. For each ready proposal, present via AskUserQuestion:

```
## Proposal: {id}
**Type:** {type}
**Target:** {target}
**Confidence:** {confidence} ({agreement})

**Current:** {current_value}
**Proposed:** {proposed_value}

**Evidence:** {evidence}
**Expected Impact:** {impact_estimate}
```

Options:
- **Accept** — Apply this refinement to the playbook
- **Reject** — Dismiss this proposal permanently
- **Modify** — Accept with changes (ask for modified value)
- **Defer** — Skip for now, revisit later

### Applying accepted proposals

1. Locate playbook file:
   - Project: `.claude/forge-playbooks/{playbook_id}.md`
   - Built-in: `shared/playbooks/{playbook_id}.md`
   - If built-in, copy to `.claude/forge-playbooks/` first (project override)
2. Edit the playbook frontmatter/body per proposal type:
   - `scoring_gap` / `acceptance_gap` → append to `acceptance_criteria:` list
   - `stage_focus` → modify `stages.focus` array
   - `parameter_default` → modify `parameters[].default`
3. Increment `version` in playbook frontmatter
4. Update `.forge/playbook-refinements/{playbook_id}.json`:
   - Set accepted proposals to `status: applied`
   - Set rejected proposals to `status: rejected`
   - Set deferred proposals to `status: deferred`
5. Log to `forge-log.md`: `[REFINE-APPLIED] {playbook_id} v{old}→v{new}: {proposal_ids}`

## Guard Rails

- Respect `<!-- locked -->` fences in playbook files — skip proposals targeting locked sections
- Never modify `pass_threshold`, `concerns_threshold`, or scoring weights
- Never remove VERIFYING, REVIEWING, or SHIPPING from stages

## Error Handling

- Playbook file not found → STOP: "Playbook {id} not found in project or built-in playbooks."
- Locked section targeted → skip proposal, inform user: "Proposal {id} targets a locked section. Skipped."
- Write fails → STOP with error, do not update refinement file status

## See Also

- `/forge-playbooks` — Create, list, run, and analyze pipeline playbooks
- `/forge-insights` — Cross-run analytics including playbook effectiveness
- `/forge-run` — Execute the pipeline (generates the run data that feeds refinements)
