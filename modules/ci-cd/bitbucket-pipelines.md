# Bitbucket Pipelines

## Overview

Bitbucket Pipelines is a CI/CD service built into Bitbucket Cloud that defines pipelines in a `bitbucket-pipelines.yml` file at the repository root. Pipelines consist of steps (sequential execution units) that run in Docker containers on Atlassian's managed infrastructure. Each step is an isolated Docker container with a shared filesystem (the repository clone), and steps within a stage can run in parallel. Bitbucket Pipelines integrates with the Atlassian ecosystem — Jira (deployment tracking, build status), Confluence (documentation), and Bitbucket's native pull request workflows.

Use Bitbucket Pipelines when the project is hosted on Bitbucket Cloud and the team uses the Atlassian ecosystem (Jira for project management, Confluence for documentation). Bitbucket Pipelines provides a straightforward, opinionated CI/CD experience with minimal configuration overhead. It excels at small-to-medium projects where simplicity and speed of setup outweigh the advanced features of more complex CI platforms. Its Pipes system (pre-built reusable components) accelerates common tasks like AWS deployment, Docker publishing, and Slack notifications.

Do not use Bitbucket Pipelines for Bitbucket Server/Data Center (it is Cloud-only — use Bamboo or Jenkins for self-hosted Bitbucket). Do not use Bitbucket Pipelines for projects requiring extensive parallelism beyond 10 parallel steps, long-running builds exceeding 2 hours (hard limit), or large build artifacts exceeding 1 GB. For complex multi-project orchestration or Kubernetes-native CI/CD, use GitLab CI, Jenkins, or Tekton instead.

Key differentiators: (1) Zero-configuration Docker support — every step runs in a Docker container with the specified image. (2) Pipes are pre-built, parameterized integrations (200+) that abstract complex deployment steps into single YAML blocks. (3) Deployment environments with Jira integration provide deployment tracking and status visibility across the Atlassian ecosystem. (4) Built-in caching with named caches and automatic dependency detection simplifies cache management. (5) Build minutes pricing model makes cost predictable for small-to-medium teams.

## Architecture Patterns

### Step Definitions

Bitbucket Pipelines organizes work into steps — sequential units of execution, each running in its own Docker container. Steps can be grouped into stages for parallel execution, conditional on branch patterns, or manual for deployment gates. The pipeline model is simpler than multi-stage CI platforms, trading advanced orchestration for configuration clarity.

**Complete pipeline with step types:**
```yaml
image: eclipse-temurin:21-jdk

definitions:
  caches:
    gradle: ~/.gradle/caches
    gradle-wrapper: ~/.gradle/wrapper

  steps:
    - step: &build-step
        name: Build and Test
        caches:
          - gradle
          - gradle-wrapper
        script:
          - ./gradlew build --no-daemon --parallel --warning-mode=all
        artifacts:
          - build/libs/*.jar
        after-script:
          - pipe: atlassian/bitbucket-upload-file:0.7.1
            variables:
              BITBUCKET_USERNAME: $BITBUCKET_USERNAME
              BITBUCKET_APP_PASSWORD: $BITBUCKET_APP_PASSWORD
              FILENAME: 'build/test-results/**/*.xml'

    - step: &lint-step
        name: Static Analysis
        caches:
          - gradle
        script:
          - ./gradlew detekt --no-daemon

    - step: &docker-step
        name: Build Docker Image
        services:
          - docker
        caches:
          - docker
        script:
          - docker build -t $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT .
          - echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin $DOCKER_REGISTRY
          - docker push $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT

pipelines:
  default:
    - step: *build-step
    - step: *lint-step

  branches:
    main:
      - step: *build-step
      - parallel:
          - step: *lint-step
          - step:
              name: Security Scan
              script:
                - pipe: atlassian/bitbucket-snyk-scan:1.0.0
                  variables:
                    SNYK_TOKEN: $SNYK_TOKEN
      - step: *docker-step
      - step:
          name: Deploy Staging
          deployment: staging
          script:
            - pipe: atlassian/aws-ecs-deploy:2.0.0
              variables:
                AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
                AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
                AWS_DEFAULT_REGION: 'eu-central-1'
                CLUSTER_NAME: 'staging'
                SERVICE_NAME: 'my-app'
                TASK_DEFINITION: 'task-definition.json'

  tags:
    'v*':
      - step: *build-step
      - step: *docker-step
      - step:
          name: Deploy Production
          deployment: production
          trigger: manual
          script:
            - pipe: atlassian/aws-ecs-deploy:2.0.0
              variables:
                AWS_ACCESS_KEY_ID: $AWS_PROD_ACCESS_KEY_ID
                AWS_SECRET_ACCESS_KEY: $AWS_PROD_SECRET_ACCESS_KEY
                AWS_DEFAULT_REGION: 'eu-central-1'
                CLUSTER_NAME: 'production'
                SERVICE_NAME: 'my-app'
                TASK_DEFINITION: 'task-definition.json'
```

YAML anchors (`&build-step`) and aliases (`*build-step`) enable step reuse within the same file. The `definitions: steps:` block declares reusable step templates. The `parallel:` block runs multiple steps concurrently. The `trigger: manual` on the production deployment creates a manual gate — the pipeline pauses until a user clicks Deploy in the Bitbucket UI.

Pipeline selection: `default` runs for all branches without explicit configuration. `branches:` overrides the default for named branches or patterns. `tags:` triggers for tag pushes. `pull-requests:` runs for pull request creation and updates. `custom:` defines manually-triggered pipelines.

### Pipes (Reusable Components)

Pipes are pre-built Docker containers that execute specific tasks — deployment, notification, scanning, publishing — with a parameterized interface. They encapsulate complex multi-step operations (AWS authentication, ECS task definition updates, deployment verification) into single YAML blocks. Bitbucket maintains certified Pipes for common integrations, and organizations can create custom Pipes.

**Common Pipes usage:**
```yaml
script:
  # AWS S3 deployment
  - pipe: atlassian/aws-s3-deploy:1.2.0
    variables:
      AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
      AWS_DEFAULT_REGION: 'eu-central-1'
      S3_BUCKET: 'my-app-frontend'
      LOCAL_PATH: 'dist/'
      ACL: 'public-read'

  # Slack notification
  - pipe: atlassian/slack-notify:2.1.0
    variables:
      WEBHOOK_URL: $SLACK_WEBHOOK_URL
      MESSAGE: 'Deployment to staging complete for $BITBUCKET_COMMIT'

  # Jira deployment tracking
  - pipe: atlassian/jira-register-deployment:1.0.0
    variables:
      JIRA_CLIENT_ID: $JIRA_CLIENT_ID
      JIRA_CLIENT_SECRET: $JIRA_CLIENT_SECRET
      ENVIRONMENT: 'staging'
      ENVIRONMENT_TYPE: 'staging'
```

**Creating a custom Pipe:**
```yaml
# pipe.yml (in the pipe repository)
name: Custom Deploy
image: alpine/k8s:1.31
variables:
  CLUSTER_NAME:
    type: string
    required: true
  NAMESPACE:
    type: string
    default: 'default'
  IMAGE_TAG:
    type: string
    required: true

# pipe.sh (entry point)
#!/usr/bin/env bash
set -euo pipefail

echo "Deploying to cluster: ${CLUSTER_NAME}"
kubectl config use-context "${CLUSTER_NAME}"
kubectl set image deployment/app app="${IMAGE_TAG}" -n "${NAMESPACE}"
kubectl rollout status deployment/app -n "${NAMESPACE}" --timeout=300s
```

**Using the custom Pipe:**
```yaml
- pipe: my-org/custom-deploy:1.0.0
  variables:
    CLUSTER_NAME: 'production'
    NAMESPACE: 'my-app'
    IMAGE_TAG: '$DOCKER_REGISTRY/my-app:$BITBUCKET_COMMIT'
```

Pipes are versioned with semantic versioning. Pin to major versions (`1.0.0`) for stability. Custom Pipes are stored as Bitbucket repositories and published to the Pipe marketplace or used privately within the organization.

### Deployment Environments

Bitbucket Pipelines deployment environments track which commits are deployed to which environments, providing visibility in the Bitbucket UI and Jira. Environments support environment-specific variables (separate credentials for staging and production), deployment history, and promotion workflows.

**Environment configuration:**
```yaml
pipelines:
  branches:
    main:
      - step:
          name: Build
          script:
            - ./gradlew build --no-daemon
          artifacts:
            - build/libs/*.jar

      - step:
          name: Deploy to Test
          deployment: test
          script:
            - ./deploy.sh test

      - step:
          name: Deploy to Staging
          deployment: staging
          script:
            - ./deploy.sh staging

      - step:
          name: Deploy to Production
          deployment: production
          trigger: manual
          script:
            - ./deploy.sh production
```

Each `deployment:` reference creates a deployment entry visible in Bitbucket's Deployments dashboard and linked Jira issues. Environment-specific variables (configured in Repository Settings > Deployments) override repository-level variables, allowing different credentials per environment without conditional logic in the pipeline.

### Parallel Steps

Parallel steps run multiple steps concurrently within a stage, reducing pipeline duration for independent tasks. Bitbucket supports up to 10 parallel steps per group. Each parallel step runs in its own Docker container with access to the repository and any artifacts from previous sequential steps.

**Parallel execution patterns:**
```yaml
pipelines:
  branches:
    main:
      - step:
          name: Build
          script:
            - ./gradlew assemble --no-daemon
          artifacts:
            - build/libs/*.jar

      - parallel:
          - step:
              name: Unit Tests
              caches:
                - gradle
              script:
                - ./gradlew test --no-daemon

          - step:
              name: Integration Tests
              services:
                - postgres
              caches:
                - gradle
              script:
                - ./gradlew integrationTest --no-daemon

          - step:
              name: Security Scan
              script:
                - pipe: atlassian/bitbucket-snyk-scan:1.0.0
                  variables:
                    SNYK_TOKEN: $SNYK_TOKEN

          - step:
              name: Lint
              script:
                - ./gradlew detekt --no-daemon

      - step:
          name: Deploy
          deployment: staging
          script:
            - ./deploy.sh staging

definitions:
  services:
    postgres:
      image: postgres:16-alpine
      variables:
        POSTGRES_DB: testdb
        POSTGRES_USER: test
        POSTGRES_PASSWORD: test
```

The Build step runs first (sequential). The four test/analysis steps run in parallel. The Deploy step waits for all parallel steps to complete before executing. Services (like PostgreSQL) are defined in the `definitions:` block and referenced by name in steps that need them.

## Configuration

### Development

**Development pipeline for pull requests:**
```yaml
image: eclipse-temurin:21-jdk

definitions:
  caches:
    gradle: ~/.gradle/caches
    gradle-wrapper: ~/.gradle/wrapper

pipelines:
  pull-requests:
    '**':
      - step:
          name: Build and Test
          caches:
            - gradle
            - gradle-wrapper
          script:
            - ./gradlew build --no-daemon --parallel
          after-script:
            - |
              if [ -d "build/test-results" ]; then
                echo "Test results available at build/test-results"
              fi

      - step:
          name: Static Analysis
          caches:
            - gradle
          script:
            - ./gradlew detekt --no-daemon

  default:
    - step:
        name: Build
        caches:
          - gradle
          - gradle-wrapper
        script:
          - ./gradlew build --no-daemon
```

The `pull-requests: '**':` pattern matches all branches for PR pipelines. The `default:` pipeline runs on branches without explicit configuration. The `after-script:` block runs regardless of whether the main script succeeded or failed — useful for collecting test results even on build failure.

### Production

**Production pipeline with full deployment chain:**
```yaml
image: eclipse-temurin:21-jdk

options:
  max-time: 30
  size: 2x

definitions:
  caches:
    gradle: ~/.gradle/caches
  services:
    docker:
      memory: 2048

pipelines:
  branches:
    main:
      - step:
          name: Build and Test
          size: 2x
          caches:
            - gradle
          script:
            - ./gradlew build --no-daemon --parallel
          artifacts:
            - build/libs/*.jar

      - step:
          name: Build and Push Docker Image
          services:
            - docker
          script:
            - export IMAGE_TAG=$DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT
            - docker build -t $IMAGE_TAG .
            - echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin $DOCKER_REGISTRY
            - docker push $IMAGE_TAG

      - step:
          name: Deploy Staging
          deployment: staging
          script:
            - pipe: atlassian/aws-ecs-deploy:2.0.0
              variables:
                AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
                AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
                AWS_DEFAULT_REGION: 'eu-central-1'
                CLUSTER_NAME: 'staging'
                SERVICE_NAME: 'my-app'
                TASK_DEFINITION: 'task-definition.json'

      - step:
          name: Deploy Production
          deployment: production
          trigger: manual
          script:
            - pipe: atlassian/aws-ecs-deploy:2.0.0
              variables:
                AWS_ACCESS_KEY_ID: $AWS_PROD_ACCESS_KEY_ID
                AWS_SECRET_ACCESS_KEY: $AWS_PROD_SECRET_ACCESS_KEY
                AWS_DEFAULT_REGION: 'eu-central-1'
                CLUSTER_NAME: 'production'
                SERVICE_NAME: 'my-app'
                TASK_DEFINITION: 'task-definition.json'
```

The `options: size: 2x` doubles the available resources (8 GB RAM, 4 vCPUs instead of 4 GB, 2 vCPUs). The `options: max-time: 30` sets a 30-minute pipeline timeout. The `trigger: manual` on production deployment creates a manual gate with the Deploy button in the Bitbucket UI.

## Performance

**Caching** is the primary performance lever. Bitbucket provides built-in caches for common tools (docker, node, pip, maven, composer) and supports custom cache definitions:

```yaml
definitions:
  caches:
    gradle: ~/.gradle/caches
    gradle-wrapper: ~/.gradle/wrapper
    npm: node_modules

pipelines:
  default:
    - step:
        caches:
          - gradle
          - gradle-wrapper
        script:
          - ./gradlew build --no-daemon
```

Built-in caches are automatically invalidated when their respective lock files change (`package-lock.json` for npm, `gradle/libs.versions.toml` for Gradle). Custom caches persist for 7 days and are evicted on LRU basis. Each cache is limited to 1 GB.

**Step size** — use `size: 2x` for memory-intensive steps (compilation, Docker builds) and default size for lightweight steps (linting, notifications):
```yaml
- step:
    name: Build
    size: 2x
    script:
      - ./gradlew build --no-daemon
```

**Artifacts** pass build outputs between steps without rebuilding:
```yaml
- step:
    name: Build
    script:
      - ./gradlew assemble --no-daemon
    artifacts:
      - build/libs/*.jar

- step:
    name: Deploy
    script:
      - ls build/libs/  # artifacts from previous step
```

Artifacts are automatically available in subsequent steps. Keep them small — large artifacts add upload/download overhead between steps.

**Parallel steps** reduce wall-clock time for independent tasks. Always parallelize test types (unit, integration, e2e) and analysis tasks (lint, security scan).

**Clone depth** reduces checkout time:
```yaml
clone:
  depth: 10
```

## Security

**Repository variables** store secrets encrypted and inject them as environment variables. Mark variables as "Secured" to prevent them from appearing in logs and being available in forks:

Configure in Repository Settings > Repository Variables:
- `DOCKER_USERNAME` — not secured (visible in logs)
- `DOCKER_PASSWORD` — secured (masked in logs, not available in forks)
- `AWS_ACCESS_KEY_ID` — secured

**Deployment variables** provide environment-specific credentials. Variables defined on the "staging" deployment environment are only available in steps with `deployment: staging`. This prevents staging credentials from leaking into production deployments and vice versa.

**Secured variables in forks** — secured variables are not available in pipelines triggered by forks. This prevents external contributors from exfiltrating secrets through malicious pipeline modifications. For open-source projects, this is the primary defense against credential theft.

**IP allowlisting** — Bitbucket Pipelines publishes the IP ranges used by runners. Add these to firewall rules for services that restrict access by IP (databases, internal APIs, deployment targets).

**Security checklist:**
- Mark all sensitive variables as Secured.
- Use deployment-specific variables for environment credentials.
- Set `trigger: manual` on production deployment steps.
- Review pipeline changes in pull requests before merging — pipeline modifications can exfiltrate secrets.
- Use Pipes from verified publishers (Atlassian-maintained where possible).
- Pin Pipe versions to exact semver, not `latest`.
- Limit repository admin access — admins can view secured variable values through the API.

## Testing

**Validating `bitbucket-pipelines.yml` locally:**
```bash
# Using the Bitbucket Pipelines validator
# (available as a web tool in Bitbucket settings)
# Repository Settings > Pipelines > Settings > Validate

# Using Docker to run steps locally
docker run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  eclipse-temurin:21-jdk \
  ./gradlew build --no-daemon
```

**Testing with `bbrun` for local execution:**
```bash
# Install bbrun
pip install bbrun

# Run default pipeline
bbrun

# Run specific branch pipeline
bbrun --pipeline branches:main

# Run specific step
bbrun --step "Build and Test"
```

**Testing services locally:**
```bash
# Start service containers manually
docker run -d --name test-postgres \
  -e POSTGRES_DB=testdb \
  -e POSTGRES_USER=test \
  -e POSTGRES_PASSWORD=test \
  -p 5432:5432 \
  postgres:16-alpine

# Run tests with service available
DATABASE_URL=postgresql://test:test@localhost:5432/testdb \
  ./gradlew integrationTest --no-daemon
```

**Testing deployment Pipes** — use the `--dry-run` option if the Pipe supports it, or test in a staging environment before production:
```yaml
- step:
    name: Test Deploy Pipe
    deployment: test
    script:
      - pipe: atlassian/aws-ecs-deploy:2.0.0
        variables:
          AWS_ACCESS_KEY_ID: $AWS_TEST_ACCESS_KEY_ID
          AWS_SECRET_ACCESS_KEY: $AWS_TEST_SECRET_ACCESS_KEY
          CLUSTER_NAME: 'test'
          SERVICE_NAME: 'my-app-test'
          TASK_DEFINITION: 'task-definition.json'
```

## Dos

- Use `definitions:` to declare reusable step templates and YAML anchors for DRY pipeline configuration. Shared step definitions eliminate duplication across branch pipelines, tag pipelines, and PR pipelines.
- Use deployment environments with Jira integration for deployment tracking. Each `deployment:` step creates a deployment record visible in Bitbucket's Deployments dashboard and linked Jira issues.
- Use `trigger: manual` for production deployment steps. This creates a deployment gate requiring explicit human action in the Bitbucket UI, preventing accidental production deployments.
- Use deployment-specific variables for environment credentials. Staging credentials should only be available in `deployment: staging` steps, not in all steps across all branches.
- Use `parallel:` for independent steps (unit tests, integration tests, linting, security scanning). Up to 10 parallel steps per group, each in its own Docker container.
- Use the built-in caches (`docker`, `node`, `gradle`) and define custom caches in `definitions:` for additional dependency paths. Caches are automatically invalidated when dependency manifests change.
- Mark all sensitive repository variables as Secured. Secured variables are masked in logs and not available in fork pipelines.
- Use `after-script:` for test result collection and cleanup. It runs regardless of step success/failure, ensuring test reports are always available.

## Don'ts

- Don't store credentials in `bitbucket-pipelines.yml`. Use repository variables (marked as Secured) or deployment-specific variables configured in the Bitbucket UI.
- Don't use `default:` pipeline for deployment steps. The `default:` pipeline runs on all branches without explicit configuration, including feature branches. Deployment should be restricted to specific branches using `branches:` configuration.
- Don't skip `trigger: manual` on production deployment steps. Without it, every push to the configured branch automatically deploys to production — one bad commit away from an outage.
- Don't use `latest` or unversioned Pipe references. Pin Pipes to specific versions (`atlassian/aws-ecs-deploy:2.0.0`) for reproducibility. Unversioned Pipes can break without warning when the publisher releases a new version.
- Don't exceed 1 GB per cache. Bitbucket enforces a 1 GB limit per named cache. Large caches fail to upload silently. Split large caches into multiple named caches if needed.
- Don't ignore the 2-hour pipeline timeout. Bitbucket hard-limits pipeline duration at 120 minutes. Design pipelines to complete well within this limit. If builds consistently approach the limit, optimize or split them.
- Don't use `size: 2x` on every step. It doubles resource consumption and build minute usage. Reserve it for genuinely resource-intensive steps (compilation, Docker builds, test suites).
- Don't forget `clone: depth:` for repositories with large histories. The default full clone wastes time and bandwidth. Set an appropriate shallow clone depth.
- Don't use Docker-in-Docker without the `docker` service definition. Steps that build Docker images need the `services: - docker` declaration and the `docker` service defined in `definitions:`.
