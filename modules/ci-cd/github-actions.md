# GitHub Actions

## Overview

GitHub Actions is a CI/CD platform integrated directly into GitHub that executes workflows defined in YAML files within the `.github/workflows/` directory. Workflows are triggered by repository events (push, pull_request, release, schedule, `workflow_dispatch` for manual triggers, and `repository_dispatch` for external triggers). Each workflow runs on GitHub-hosted runners (Ubuntu, macOS, Windows) or self-hosted runners, with jobs executing in isolated virtual environments that are destroyed after each run.

Use GitHub Actions when the project is hosted on GitHub and the team wants CI/CD tightly coupled with pull request workflows, code review, and release management. GitHub Actions excels at PR-gated builds, multi-platform testing (matrix strategies across OS and language versions), and automated releases. Its marketplace of 20,000+ community actions accelerates common tasks (caching, deployment, notification), and its deep integration with GitHub's API (check runs, deployments, environments, OIDC) eliminates the authentication friction that plagues external CI systems.

Do not use GitHub Actions for workloads that require persistent build agents with warm caches (use Jenkins or self-hosted runners), extremely long-running jobs exceeding the 6-hour limit (use dedicated build infrastructure), or organizations with strict air-gapped requirements where no SaaS CI is acceptable (use Tekton or Jenkins). For GitLab-hosted repositories, use GitLab CI instead — cross-platform mirroring adds complexity without benefit. For teams already invested in CircleCI or Azure Pipelines with extensive orb/template libraries, the migration cost may outweigh the integration benefits.

Key differentiators: (1) First-class GitHub integration — status checks, deployments, environments, and OIDC tokens are native, not bolted on. (2) Reusable workflows (`workflow_call`) enable organizational standardization without requiring a separate plugin/orb system. (3) Composite actions package multi-step logic into reusable units versioned alongside application code. (4) OIDC authentication eliminates long-lived cloud credentials for AWS, GCP, and Azure deployments. (5) Matrix strategies test across OS, language version, and dependency combinations with a single job definition. (6) Concurrency controls prevent redundant runs and resource contention without external tooling.

## Architecture Patterns

### Reusable Workflows

Reusable workflows (`workflow_call` trigger) extract common CI/CD logic into standalone workflow files that other workflows call like functions. They solve the copy-paste problem where 15 microservices each maintain identical CI pipelines that drift over time. The calling workflow passes inputs and secrets; the reusable workflow executes its jobs and returns outputs. Reusable workflows can live in the same repository or in a dedicated organization-wide `.github` repository.

**Organization-wide reusable workflow (`.github/workflows/ci-build.yml` in the shared repo):**
```yaml
name: Reusable CI Build

on:
  workflow_call:
    inputs:
      java-version:
        description: 'JDK version'
        required: false
        type: string
        default: '21'
      build-command:
        description: 'Build command to execute'
        required: false
        type: string
        default: './gradlew build --no-daemon --parallel'
      upload-artifacts:
        description: 'Whether to upload build artifacts'
        required: false
        type: boolean
        default: true
    secrets:
      SONAR_TOKEN:
        required: false
    outputs:
      build-version:
        description: 'Build version from Gradle'
        value: ${{ jobs.build.outputs.version }}

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.version.outputs.version }}
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: ${{ inputs.java-version }}

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v4
        with:
          cache-read-only: ${{ github.ref != format('refs/heads/{0}', github.event.repository.default_branch) }}

      - name: Build
        run: ${{ inputs.build-command }}

      - name: Extract version
        id: version
        run: echo "version=$(./gradlew properties -q | grep '^version:' | awk '{print $2}')" >> "$GITHUB_OUTPUT"

      - name: Upload artifacts
        if: inputs.upload-artifacts
        uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: '**/build/libs/*.jar'
          retention-days: 5
```

**Calling the reusable workflow from a service repository:**
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    uses: my-org/.github/.github/workflows/ci-build.yml@main
    with:
      java-version: '21'
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}

  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'
    uses: my-org/.github/.github/workflows/deploy.yml@main
    with:
      version: ${{ needs.build.outputs.build-version }}
```

The organizational pattern centralizes CI logic while allowing per-repo customization through inputs. When the build process changes (new cache strategy, updated action versions), update one file instead of 15. Pin the reference to a tag (`@v1`) rather than `@main` for production workflows to prevent breaking changes from propagating immediately.

### Composite Actions

Composite actions package multiple steps into a single reusable action defined by an `action.yml` file. Unlike reusable workflows (which define entire jobs), composite actions are steps within a job — they share the job's runner, environment variables, and filesystem. This makes them ideal for packaging setup sequences, build tooling, and deployment scripts that need to share state with surrounding steps.

**Custom composite action (`/.github/actions/setup-project/action.yml`):**
```yaml
name: 'Setup Project'
description: 'Set up JDK, Gradle, and project dependencies'

inputs:
  java-version:
    description: 'JDK version'
    required: false
    default: '21'
  gradle-cache-read-only:
    description: 'Gradle cache read-only mode'
    required: false
    default: 'false'

outputs:
  project-version:
    description: 'Detected project version'
    value: ${{ steps.version.outputs.version }}

runs:
  using: 'composite'
  steps:
    - name: Set up JDK ${{ inputs.java-version }}
      uses: actions/setup-java@v4
      with:
        distribution: 'temurin'
        java-version: ${{ inputs.java-version }}

    - name: Setup Gradle
      uses: gradle/actions/setup-gradle@v4
      with:
        cache-read-only: ${{ inputs.gradle-cache-read-only }}

    - name: Detect project version
      id: version
      shell: bash
      run: |
        VERSION=$(./gradlew properties -q | grep '^version:' | awk '{print $2}')
        echo "version=${VERSION}" >> "$GITHUB_OUTPUT"
```

**Using the composite action in a workflow:**
```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup project
        uses: ./.github/actions/setup-project
        with:
          java-version: '21'
          gradle-cache-read-only: ${{ github.ref != 'refs/heads/main' }}

      - name: Build
        run: ./gradlew build --no-daemon --parallel
```

Composite actions must specify `shell:` on every `run:` step (unlike regular workflow steps where shell defaults to `bash`). Store them under `.github/actions/` for repository-scoped actions or in a dedicated repository for organization-wide sharing. Version them with tags (`@v1`, `@v2`) when shared across repositories.

### Matrix Strategies

Matrix strategies generate multiple job instances from combinations of variables, enabling comprehensive testing across platforms, language versions, and configurations without duplicating job definitions. The matrix expands at workflow parse time — a 3x3 matrix creates 9 parallel jobs automatically. Combined with `fail-fast: false`, all combinations run to completion even if one fails, providing a complete compatibility picture.

**Multi-dimensional matrix with exclusions and includes:**
```yaml
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      max-parallel: 6
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        java-version: ['17', '21', '23']
        exclude:
          - os: macos-latest
            java-version: '17'
        include:
          - os: ubuntu-latest
            java-version: '21'
            coverage: true
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK ${{ matrix.java-version }}
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: ${{ matrix.java-version }}

      - name: Test
        run: ./gradlew test --no-daemon

      - name: Upload coverage
        if: matrix.coverage
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: '**/build/reports/jacoco/'
```

Use `exclude` to remove invalid or unnecessary combinations (macOS + JDK 17 is irrelevant if the project requires JDK 21+). Use `include` to add properties to specific combinations (coverage reporting only on one OS/JDK pair). Set `max-parallel` to avoid overwhelming shared resources (databases, external services). Set `fail-fast: false` for PR checks where seeing all failures matters more than fast feedback.

### Caching Strategy

GitHub Actions provides a built-in caching mechanism (`actions/cache`) that persists files between workflow runs. Effective caching is the single biggest performance lever — a cold Gradle build that takes 8 minutes can drop to 2 minutes with warm dependency and build caches. The cache key strategy determines hit rates: too specific keys cause misses; too broad keys serve stale data.

**Layered caching with fallback keys:**
```yaml
- name: Cache Gradle dependencies
  uses: actions/cache@v4
  with:
    path: |
      ~/.gradle/caches
      ~/.gradle/wrapper
    key: gradle-${{ runner.os }}-${{ hashFiles('**/*.gradle.kts', '**/gradle-wrapper.properties', '**/libs.versions.toml') }}
    restore-keys: |
      gradle-${{ runner.os }}-

- name: Cache Docker layers
  uses: actions/cache@v4
  with:
    path: /tmp/.buildx-cache
    key: docker-${{ runner.os }}-${{ hashFiles('**/Dockerfile') }}
    restore-keys: |
      docker-${{ runner.os }}-
```

The `key` uses `hashFiles()` on dependency manifests — any change to `libs.versions.toml` or `build.gradle.kts` creates a new cache entry. The `restore-keys` provide prefix-based fallback: if the exact key misses, the most recent cache with a matching prefix is restored. This ensures a partial cache hit (stale but mostly valid) rather than a complete miss after every dependency change.

For tool-specific setup actions (`actions/setup-java`, `gradle/actions/setup-gradle`, `actions/setup-node`), prefer their built-in caching over manual `actions/cache` steps — they handle cache paths, keys, and invalidation automatically with tool-specific optimizations.

### OIDC Authentication for Cloud

OpenID Connect (OIDC) authentication replaces long-lived cloud credentials (AWS access keys, GCP service account keys) with short-lived tokens issued by GitHub's OIDC provider. The workflow requests a JWT from GitHub, presents it to the cloud provider's STS (Security Token Service), and receives temporary credentials scoped to the specific repository, branch, and environment. This eliminates the need to store cloud credentials as repository secrets entirely.

**AWS deployment with OIDC (no stored credentials):**
```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-deploy
          aws-region: eu-central-1
          role-session-name: deploy-${{ github.run_id }}

      - name: Deploy to ECS
        run: |
          aws ecs update-service \
            --cluster production \
            --service my-app \
            --force-new-deployment
```

**GCP deployment with OIDC:**
```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: 'projects/123456789/locations/global/workloadIdentityPools/github/providers/my-repo'
          service_account: 'deploy@my-project.iam.gserviceaccount.com'

      - name: Deploy to Cloud Run
        uses: google-github-actions/deploy-cloudrun@v2
        with:
          service: my-app
          region: europe-west1
          image: 'gcr.io/my-project/my-app:${{ github.sha }}'
```

The OIDC trust relationship is configured in the cloud provider's IAM: the trust policy specifies the GitHub OIDC issuer URL, the repository, and optionally the branch and environment. This means even if a repository secret is compromised, it is useless — the token exchange requires a valid GitHub Actions JWT that can only be minted during an actual workflow run. Always scope the IAM role to the minimum permissions needed for the deployment.

## Configuration

### Development

Developer-focused workflows optimize for fast feedback on pull requests. The configuration prioritizes speed (caching, parallelism, skip conditions), clear status reporting (check annotations), and safety (concurrency controls to prevent duplicate runs).

**Complete PR workflow (`.github/workflows/ci.yml`):**
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}

permissions:
  contents: read
  checks: write
  pull-requests: read

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run linter
        uses: super-linter/super-linter@v7
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          VALIDATE_ALL_CODEBASE: false
          DEFAULT_BRANCH: main

  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '21'

      - uses: gradle/actions/setup-gradle@v4
        with:
          cache-read-only: ${{ github.event_name == 'pull_request' }}

      - name: Build and test
        run: ./gradlew build --no-daemon --parallel --warning-mode=all

      - name: Publish test results
        if: always()
        uses: mikepenz/action-junit-report@v4
        with:
          report_paths: '**/build/test-results/test/TEST-*.xml'
          check_name: 'Test Results'
```

The `concurrency` block with `cancel-in-progress: true` cancels previous runs for the same branch when a new push arrives — essential for PRs where rapid iteration means the previous run is already obsolete. The condition `github.ref != 'refs/heads/main'` preserves main branch runs to avoid cancelling deployment pipelines. The `permissions` block follows least-privilege: only `contents: read`, `checks: write` (for test annotations), and `pull-requests: read` are needed.

### Production

Production workflows emphasize safety (environment approvals, deployment gates), traceability (artifact provenance, deployment records), and reliability (rollback mechanisms, health checks). They use GitHub Environments to enforce approval gates and restrict which branches can deploy.

**Release and deploy workflow (`.github/workflows/release.yml`):**
```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write
  packages: write
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image-digest: ${{ steps.build-image.outputs.digest }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '21'

      - uses: gradle/actions/setup-gradle@v4

      - name: Build
        run: ./gradlew build --no-daemon --parallel

      - name: Build and push Docker image
        id: build-image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository }}:${{ github.ref_name }}
            ghcr.io/${{ github.repository }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy-staging:
    needs: build
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: eu-central-1

      - name: Deploy to staging
        run: |
          aws ecs update-service \
            --cluster staging \
            --service my-app \
            --force-new-deployment

      - name: Wait for deployment
        run: |
          aws ecs wait services-stable \
            --cluster staging \
            --services my-app

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: eu-central-1

      - name: Deploy to production
        run: |
          aws ecs update-service \
            --cluster production \
            --service my-app \
            --force-new-deployment

      - name: Verify deployment health
        run: |
          for i in $(seq 1 30); do
            STATUS=$(curl -sf https://api.example.com/actuator/health | jq -r '.status')
            if [ "$STATUS" = "UP" ]; then
              echo "Deployment healthy"
              exit 0
            fi
            sleep 10
          done
          echo "Deployment health check failed"
          exit 1
```

The `environment:` field links jobs to GitHub Environments, which enforce required reviewers, wait timers, and branch protection rules. Staging deploys automatically after build; production requires manual approval (configured in repository settings). The health check step verifies the deployment is serving traffic before marking the workflow as successful.

## Performance

**Concurrency controls** prevent redundant work. The `concurrency` key groups runs by a unique identifier (branch, PR number, or workflow name) and optionally cancels in-progress runs when a newer commit arrives. Without concurrency controls, pushing 5 commits in rapid succession spawns 5 independent workflow runs — wasteful and confusing when only the latest matters:
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.ref }}
  cancel-in-progress: true
```

**Path filtering** skips workflows entirely when changes do not affect the relevant code. A documentation-only change should not trigger a full build:
```yaml
on:
  push:
    paths:
      - 'src/**'
      - 'build.gradle.kts'
      - 'gradle/**'
      - '.github/workflows/ci.yml'
    paths-ignore:
      - '**.md'
      - 'docs/**'
```

**Job-level conditional execution** with `if:` expressions avoids spinning up runners for jobs that cannot produce useful results:
```yaml
jobs:
  deploy:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    needs: build
    runs-on: ubuntu-latest
```

**Artifact passing between jobs** — use `actions/upload-artifact` and `actions/download-artifact` to share build outputs between jobs without rebuilding. Set `retention-days` to the minimum needed (default is 90 days, which wastes storage):
```yaml
- uses: actions/upload-artifact@v4
  with:
    name: build-output
    path: build/libs/
    retention-days: 1
```

**Docker layer caching** using GitHub Actions cache backend avoids rebuilding unchanged Docker layers:
```yaml
- uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

**Self-hosted runners** for heavy workloads — GitHub-hosted runners have 7 GB RAM and 2 vCPUs (standard) or 14 GB and 4 vCPUs (large). For builds that exceed these limits (large monorepos, Android emulator tests, GPU workloads), self-hosted runners on dedicated hardware or autoscaling cloud instances (via `actions-runner-controller` on Kubernetes) provide more resources and persistent caches. Self-hosted runners keep the Gradle daemon, Docker images, and dependency caches warm between runs, dramatically reducing build times for repeat builds.

**Workflow-level timeouts** prevent stuck jobs from consuming runner minutes indefinitely:
```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - name: Long-running step
        timeout-minutes: 10
        run: ./gradlew build
```

## Security

**Permissions block** — every workflow must declare explicit permissions using the `permissions:` key. The default `GITHUB_TOKEN` has broad permissions; restricting them to the minimum required prevents token misuse if a step is compromised. Set repository-level default to `contents: read` and escalate per-workflow:
```yaml
permissions:
  contents: read
  pull-requests: write
  checks: write
```

**Pin actions to full SHA** — never use mutable tags (`@v4`, `@main`) for third-party actions in production workflows. A tag can be force-pushed to point at malicious code. Pin to the full commit SHA and add a comment with the version for readability:
```yaml
# Pinned to actions/checkout v4.1.7
- uses: actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332
```

Use Dependabot or Renovate to automatically propose SHA updates when new versions are released. For first-party actions (`actions/*`) and organization-owned actions, tag pinning (`@v4`) is acceptable because the trust boundary is within your organization.

**Secret masking** — GitHub automatically masks repository secrets in logs, but dynamically generated sensitive values (API keys from vault lookups, tokens from OIDC exchanges) need explicit masking:
```yaml
- name: Fetch API key from vault
  id: vault
  run: |
    API_KEY=$(vault kv get -field=api_key secret/my-app)
    echo "::add-mask::${API_KEY}"
    echo "api-key=${API_KEY}" >> "$GITHUB_OUTPUT"
```

The `::add-mask::` workflow command tells the runner to redact the value from all subsequent log output. Always mask before echoing to `$GITHUB_OUTPUT` or `$GITHUB_ENV` to prevent accidental exposure in step outputs.

**`pull_request_target` safety** — the `pull_request_target` event runs in the context of the base branch with write permissions and access to secrets. This is dangerous when combined with `actions/checkout` of the PR head — an attacker can submit a PR that modifies the workflow file or build scripts to exfiltrate secrets. Safe usage requires explicit checkout of the base branch only, or using a two-workflow pattern:
```yaml
# DANGEROUS — checks out attacker-controlled code with secrets access
on: pull_request_target
steps:
  - uses: actions/checkout@v4
    with:
      ref: ${{ github.event.pull_request.head.sha }}  # PR code with base secrets!

# SAFE — checks out base branch code only
on: pull_request_target
steps:
  - uses: actions/checkout@v4  # defaults to base branch
```

The safe pattern for labeling or commenting on external PRs uses `pull_request_target` without checking out PR code. For builds that need PR code with secrets (e.g., Sonar analysis), use a two-job pattern: job 1 runs on `pull_request` (no secrets, builds the PR), job 2 runs on `workflow_run` (has secrets, processes artifacts from job 1).

**Environment protection rules** — configure GitHub Environments with required reviewers, wait timers, and deployment branch restrictions. This ensures production deployments are gated by human approval and limited to specific branches:
```yaml
jobs:
  deploy:
    environment:
      name: production
      url: https://api.example.com
    runs-on: ubuntu-latest
```

**Dependency review** — automatically flag new dependencies with known vulnerabilities or restrictive licenses on pull requests:
```yaml
- name: Dependency review
  uses: actions/dependency-review-action@v4
  with:
    fail-on-severity: moderate
    deny-licenses: GPL-3.0, AGPL-3.0
```

**Supply chain security checklist:**
- Set repository-level default permissions to `contents: read` (Settings > Actions > General).
- Pin all third-party actions to full commit SHA.
- Use OIDC for cloud authentication — never store long-lived cloud credentials as secrets.
- Enable Dependabot for action version updates.
- Restrict `GITHUB_TOKEN` permissions per workflow to minimum required.
- Never use `pull_request_target` with checkout of PR head code.
- Enable branch protection rules requiring status checks, reviews, and signed commits.
- Use GitHub Advanced Security (secret scanning, code scanning) for comprehensive coverage.

## Testing

**Testing workflow configurations** requires validating that workflows parse correctly, that matrix strategies expand as expected, and that conditional logic triggers under the right conditions. Unlike application code, workflow YAML cannot be unit-tested locally — validation relies on linting, dry-run capabilities, and structured integration testing.

**Local workflow validation with `actionlint`:**
```bash
# Install actionlint
brew install actionlint

# Validate all workflows
actionlint .github/workflows/*.yml

# Validate with shellcheck integration (checks run: steps)
actionlint -shellcheck= .github/workflows/*.yml
```

`actionlint` catches syntax errors, invalid action references, undefined secret usage, type mismatches in expressions, and deprecated features. Run it as a pre-commit hook or in CI to catch errors before they reach GitHub's slower feedback loop.

**Testing with `act` for local execution:**
```bash
# Install act
brew install act

# Run a specific workflow locally
act push --workflows .github/workflows/ci.yml --job build

# Run with specific event payload
act pull_request --eventpath .github/test-events/pr-opened.json

# List available jobs without running
act --list
```

`act` runs workflows locally in Docker containers, providing fast feedback during development. It does not perfectly replicate GitHub's runner environment (some GitHub context variables are unavailable, caching behaves differently), but it catches most configuration errors.

**Integration testing for reusable workflows** — create a test workflow that calls the reusable workflow with known inputs and asserts on outputs:
```yaml
name: Test Reusable Workflow

on:
  pull_request:
    paths:
      - '.github/workflows/ci-build.yml'

jobs:
  test-default-inputs:
    uses: ./.github/workflows/ci-build.yml
    with:
      java-version: '21'

  test-custom-inputs:
    uses: ./.github/workflows/ci-build.yml
    with:
      java-version: '17'
      build-command: './gradlew check --no-daemon'
      upload-artifacts: false

  verify-outputs:
    needs: test-default-inputs
    runs-on: ubuntu-latest
    steps:
      - name: Verify build version output
        run: |
          if [ -z "${{ needs.test-default-inputs.outputs.build-version }}" ]; then
            echo "ERROR: build-version output is empty"
            exit 1
          fi
```

**Testing composite actions** — create a workflow that exercises the action with various input combinations:
```yaml
name: Test Setup Action

on:
  pull_request:
    paths:
      - '.github/actions/setup-project/**'

jobs:
  test-action:
    strategy:
      matrix:
        java-version: ['17', '21']
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Test setup action
        id: setup
        uses: ./.github/actions/setup-project
        with:
          java-version: ${{ matrix.java-version }}

      - name: Verify Java version
        run: |
          ACTUAL=$(java -version 2>&1 | head -1)
          echo "Java version: $ACTUAL"
          echo "$ACTUAL" | grep -q "${{ matrix.java-version }}"

      - name: Verify project version output
        run: |
          echo "Project version: ${{ steps.setup.outputs.project-version }}"
          [ -n "${{ steps.setup.outputs.project-version }}" ]
```

## Dos

- Declare explicit `permissions:` on every workflow. Default `GITHUB_TOKEN` permissions are too broad. Start with `contents: read` and add only what each job requires. This limits blast radius if any step is compromised.
- Pin third-party actions to full commit SHA in production workflows. Tags are mutable and can be force-pushed to point at malicious code. Use Dependabot or Renovate to propose SHA updates when new versions are released.
- Use `concurrency` with `cancel-in-progress: true` on PR workflows to avoid wasting runner minutes on superseded commits. Group by `github.head_ref` for PRs and `github.ref` for branch pushes.
- Use reusable workflows (`workflow_call`) to standardize CI/CD across repositories. Store them in an organization-wide `.github` repository and pin callers to tags (`@v1`) for stability.
- Use OIDC authentication for cloud deployments. Short-lived tokens from GitHub's OIDC provider eliminate the need for long-lived cloud credentials stored as secrets, reducing the attack surface.
- Use path filtering (`paths:`, `paths-ignore:`) to skip workflows when changes are irrelevant. A README change should not trigger a 15-minute build pipeline.
- Use GitHub Environments with required reviewers and deployment branch restrictions for production deployments. This provides an auditable approval gate and prevents accidental deployments from feature branches.
- Set `timeout-minutes` on every job and long-running step. The default 6-hour timeout wastes runner minutes when a build hangs. Most CI jobs should complete in under 15 minutes.
- Use `actions/cache` with `hashFiles()` keys on dependency manifests and `restore-keys` fallback for partial cache hits. Prefer tool-specific setup actions with built-in caching over manual cache management.
- Mask dynamically generated secrets with `::add-mask::` before writing them to `$GITHUB_OUTPUT` or `$GITHUB_ENV`. GitHub only auto-masks repository secrets, not values fetched at runtime.

## Don'ts

- Don't use `pull_request_target` with `actions/checkout` of the PR head branch. This grants the PR code access to secrets and write permissions intended for the base branch. Use a two-workflow pattern (`pull_request` + `workflow_run`) when PR code needs secret access.
- Don't store long-lived cloud credentials (AWS access keys, GCP service account keys) as repository secrets. Use OIDC authentication instead — it produces short-lived tokens scoped to the specific workflow run, repository, and environment.
- Don't use mutable tags (`@v4`, `@latest`, `@main`) for third-party actions in production workflows. A compromised or force-pushed tag executes arbitrary code in your workflow with full `GITHUB_TOKEN` access. Pin to SHA.
- Don't omit the `permissions:` block — the default is overly permissive. A workflow that only reads code and posts check results does not need `packages: write` or `deployments: write`. Least privilege is the only safe default.
- Don't use `${{ github.event.pull_request.body }}` or other user-controlled inputs in `run:` steps without sanitization. Expression injection allows arbitrary command execution. Use environment variables instead of inline expressions for untrusted inputs.
- Don't hardcode secrets in workflow files, composite actions, or `run:` steps. Use repository secrets, organization secrets, or environment secrets — and rotate them on a schedule.
- Don't use `continue-on-error: true` on security-critical steps (vulnerability scanning, secret detection, license checks). A passing workflow with silently ignored security failures provides false confidence. If the step is flaky, fix the flakiness.
- Don't skip `if: always()` on test result publishing steps. Without it, test results are not uploaded when the build step fails — exactly when they are most needed for debugging.
- Don't create workflows without `concurrency` controls. Without them, pushing 5 commits in quick succession spawns 5 independent runs, wasting runner minutes and creating confusing status checks.
- Don't use self-hosted runners for untrusted workflows (public repository forks). Self-hosted runners persist state between runs — a malicious workflow can install backdoors, steal credentials, or compromise the host. Use ephemeral GitHub-hosted runners for public repositories.
