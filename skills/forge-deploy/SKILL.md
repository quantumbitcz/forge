---
name: forge-deploy
description: "[writes] Trigger deployment to staging, production, or preview environments. Use when a PR is merged and ready to deploy, when you need to check deployment status, or when rolling back a broken deployment. Supports ArgoCD, Helm, kubectl, docker-compose."
allowed-tools: ['Read', 'Bash', 'AskUserQuestion']
ui: { ask: true }
---

# /forge-deploy -- Environment Deployment

You manage deployments to staging, production, and preview environments. You read deployment configuration from the project's `forge.local.md` and execute the appropriate deployment method.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Deploy config exists:** Check `.claude/forge.local.md` contains a `deploy` section. If not: display the helpful configuration template (see Instructions section) and STOP.

## Instructions

### 1. Parse Input

The user's argument (everything after `/forge-deploy`) determines the action:

| Command | Action |
|---------|--------|
| `/forge-deploy staging` | Deploy to staging environment |
| `/forge-deploy production` | Deploy to production (requires confirmation) |
| `/forge-deploy preview` | Deploy preview environment for current PR |
| `/forge-deploy rollback` | Rollback to previous version |
| `/forge-deploy status` | Check deployment status |
| `/forge-deploy --dry-run staging` | Show what would happen without executing |
| `/forge-deploy` (no args) | Show deployment config and available environments |

If `--dry-run` is present in the arguments, execute in dry-run mode: resolve all variables, display the full command that would be executed, show the confirmation prompt (if applicable), but do NOT execute the command. Safety guards (Section 5) still apply in dry-run mode — display any warnings that would be shown during a real deploy. Display: "DRY RUN — no changes made." If `--dry-run` is used without specifying an environment, treat it as `/forge-deploy` (show configuration).

### 2. Read Configuration

Read deployment config from `.claude/forge.local.md` under the `deploy` key:

```yaml
deploy:
  method: argocd                 # argocd | helm | kubectl | compose
  staging:
    command: "gh workflow dispatch deploy.yml -f environment=staging"
    post_deploy_check: "curl -sf https://staging.example.com/health"
  production:
    command: "gh workflow dispatch deploy.yml -f environment=production"
    require_confirmation: true
    post_deploy_check: "curl -sf https://app.example.com/health"
  preview:
    command: "gh workflow dispatch deploy.yml -f environment=preview -f pr={pr_number}"
  rollback:
    command: "gh workflow dispatch rollback.yml -f environment={environment}"
  status:
    command: "gh run list --workflow=deploy.yml --limit=5"
```

If no `deploy` config is found, display a helpful message:

```
No deployment configuration found.

To enable /forge-deploy, add a `deploy` section to your `.claude/forge.local.md`:

deploy:
  method: argocd
  staging:
    command: "gh workflow dispatch deploy.yml -f environment=staging"
  production:
    command: "gh workflow dispatch deploy.yml -f environment=production"
    require_confirmation: true
  preview:
    command: "gh workflow dispatch deploy.yml -f environment=preview -f pr={pr_number}"
  rollback:
    command: "gh workflow dispatch rollback.yml -f environment={environment}"
  status:
    command: "gh run list --workflow=deploy.yml --limit=5"
```

### 3. Deployment Actions

#### 3.1 `/forge-deploy staging`

1. Read `deploy.staging.command` from config
2. Determine the current version: read the latest git tag or commit SHA
3. Execute the staging command via Bash
4. If `post_deploy_check` is configured, wait 10 seconds then run the health check (retry up to 3 times with 10s intervals)
5. Report: command executed, version deployed, health check result

#### 3.2 `/forge-deploy production`

1. Read `deploy.production` from config
2. **Confirmation gate**: If `require_confirmation: true` (default for production), display a confirmation prompt to the user:
   ```
   PRODUCTION DEPLOYMENT

   Version: {version/commit}
   Branch: {current branch}
   Last staging deploy: {if known from status}

   Type "yes" to confirm production deployment.
   ```
   Do NOT proceed until the user explicitly confirms with "yes". Any other response aborts.
3. Execute the production command via Bash
4. If `post_deploy_check` is configured, wait 15 seconds then run the health check (retry up to 5 times with 15s intervals)
5. Report: command executed, version deployed, health check result

#### 3.3 `/forge-deploy preview`

1. Read `deploy.preview.command` from config
2. Detect the current PR number: run `gh pr view --json number -q .number` to get the PR number for the current branch
3. Replace `{pr_number}` in the command with the actual PR number
4. Execute the preview command via Bash
5. Report: command executed, PR number, preview URL if available

#### 3.4 `/forge-deploy rollback`

1. Read `deploy.rollback.command` from config
2. Ask the user which environment to rollback (staging or production) if not specified
3. Replace `{environment}` in the command with the target environment
4. For production rollbacks, require confirmation (same gate as production deploy)
5. Execute the rollback command via Bash
6. Report: command executed, environment, rollback status

#### 3.5 `/forge-deploy status`

1. Read `deploy.status.command` from config
2. Execute the status command via Bash
3. Parse and display the output in a readable format:
   ```
   Recent Deployments:

   | # | Environment | Status | Version | Time |
   |---|-------------|--------|---------|------|
   | 1 | staging     | success | abc123 | 2h ago |
   | 2 | production  | success | def456 | 1d ago |
   ```

### 4. Method-Specific Behavior

If `deploy.method` is specified, adjust behavior accordingly:

- **argocd**: Commands likely use `argocd app sync` or GitHub workflow dispatch. After deploy, check sync status with `argocd app get <app> -o json` if argocd CLI is available.
- **helm**: Commands likely use `helm upgrade --install`. Verify release status with `helm status <release>` after deploy.
- **kubectl**: Commands likely use `kubectl apply` or `kubectl set image`. Verify rollout with `kubectl rollout status`.
- **compose**: Commands likely use `docker compose up -d`. Verify with `docker compose ps`.

### 5. Safety Guards

- **Never deploy from a dirty working tree**: Run `git status --porcelain` first. If there are uncommitted changes, warn the user and suggest committing first.
- **Never deploy unmerged code to production**: Check if the current branch is the default branch (main/master) for production deploys. Warn if deploying from a feature branch.
- **Always log the deployment**: After a successful deploy, output a summary suitable for pipeline state tracking.

### 6. Variable Substitution

Replace these placeholders in commands before execution:

| Placeholder | Value |
|-------------|-------|
| `{pr_number}` | Current PR number from `gh pr view` |
| `{environment}` | Target environment name |
| `{version}` | Current git tag or short SHA |
| `{branch}` | Current git branch name |
| `{commit}` | Full commit SHA |

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Deploy command fails | Report the error output and suggest troubleshooting steps |
| Health check fails | Report the failure but do not automatically rollback (user decides) |
| Missing `gh` CLI | Suggest installing GitHub CLI if commands use `gh` |
| Missing config key | Report which config key is missing and show the expected format |
| Production deploy without confirmation | Never proceed -- abort if confirmation is not "yes" |
| Dirty working tree | Warn user and suggest committing or stashing first |
| Deploy from feature branch to production | Warn that code is not on the default branch |

## See Also

- `/forge-rollback` -- Rollback a deployment or pipeline changes
- `/forge-run` -- Full pipeline that may include deployment at the SHIPPING stage
- `/forge-verify` -- Quick build + lint + test check before deploying
- `/forge-docs-generate` -- Generate documentation before or alongside deployment
