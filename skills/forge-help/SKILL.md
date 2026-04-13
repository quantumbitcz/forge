---
name: forge-help
description: "Interactive decision tree to find the right Forge skill. Use when unsure which skill to use, exploring capabilities, or need help choosing between similar skills. Trigger: /forge-help, which skill should I use, help me choose, what can forge do"
---

# /forge-help -- Skill Decision Tree

Interactive guide to find the right Forge skill for your situation.

## Prerequisites

None. This skill is a reference guide.

## Instructions

Display the decision tree below. If the user asks a specific question, navigate to the relevant category.

### Decision Tree

**What do you want to do?**

1. **Build something new**
   - Clear requirement? -> `/forge-run`
   - Vague idea? -> `/forge-shape` then `/forge-run`
   - Multiple features? -> `/forge-sprint`
   - New project from scratch? -> `/bootstrap-project`

2. **Fix something**
   - Bug with reproduction steps? -> `/forge-fix`
   - Flaky test? -> `/forge-fix` (auto-detects flaky patterns)
   - Pipeline broken? -> `/forge-diagnose` then `/repair-state`
   - Config issues? -> `/config-validate`

3. **Review code**
   - Changed files only? -> `/forge-review`
   - Full codebase audit? -> `/codebase-health`
   - Fix all issues? -> `/deep-health`
   - Security focused? -> `/security-audit`

4. **Manage pipeline**
   - Check status? -> `/forge-status`
   - Resume stopped run? -> `/forge-resume`
   - Stop a run? -> `/forge-abort`
   - Start fresh? -> `/forge-reset`
   - Rollback changes? -> `/forge-rollback`
   - View history? -> `/forge-history`

5. **Documentation & config**
   - Generate docs? -> `/docs-generate`
   - Edit config? -> `/forge-config`
   - Validate config? -> `/config-validate`
   - Deploy? -> `/deploy`

6. **Analytics & insights**
   - Pipeline analytics? -> `/forge-insights`
   - Performance profiling? -> `/forge-profile`
   - Codebase Q&A? -> `/forge-ask`
   - Playbook templates? -> `/forge-playbooks`

7. **Knowledge graph**
   - Initialize? -> `/graph-init`
   - Check health? -> `/graph-status`
   - Query? -> `/graph-query`
   - Rebuild? -> `/graph-rebuild`
   - Debug issues? -> `/graph-debug`

8. **Advanced**
   - Compress agent prompts? -> `/forge-compress`
   - Terse output mode? -> `/forge-caveman`
   - Framework migration? -> `/migration`
   - Automations? -> `/forge-automation`

## Error Handling

None. This skill displays static content.

## See Also

- `/forge-tour` -- guided 5-stop introduction for new users
- `/forge-init` -- first-time project setup
