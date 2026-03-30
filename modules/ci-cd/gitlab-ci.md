# GitLab CI

## Overview

CI/CD platform built into GitLab, defined in `.gitlab-ci.yml`. Pipelines use stages (sequential) containing jobs (parallel) on GitLab Runners. Integrates with merge requests, container/package registries, environments, and security scanning as a unified DevSecOps platform.

- **Use for:** GitLab-hosted projects needing unified source + CI/CD + registry + security, multi-project pipelines, review apps (ephemeral envs per MR), compliance pipelines
- **Avoid for:** GitHub-hosted projects (use Actions), teams needing large third-party marketplace, CI/CD decoupled from source control (use Jenkins/Tekton), extremely large monorepos
- **Key differentiators:** DAG pipelines (`needs:`) break sequential stage model for 30-60% faster runs; Include/Extends for DRY config via remote templates; multi-project and parent-child pipelines with cross-repo artifact passing; review apps with auto-cleanup; compliance pipelines enforcing org standards

## Architecture Patterns

### DAG Pipelines with `needs:`

The `needs:` keyword creates a Directed Acyclic Graph (DAG) of job dependencies that overrides the default sequential stage execution model. Without `needs:`, all jobs in stage N must complete before any job in stage N+1 starts. With `needs:`, a job starts as soon as its explicitly declared dependencies complete, potentially executing alongside jobs from earlier stages. This can reduce pipeline duration by 30-60% on pipelines with independent test suites.

**DAG pipeline with cross-stage dependencies:**
```yaml
stages:
  - build
  - test
  - security
  - deploy

build-backend:
  stage: build
  image: gradle:8.12-jdk21
  script:
    - ./gradlew build --no-daemon --parallel
  artifacts:
    paths:
      - build/libs/*.jar
    expire_in: 1 hour

build-frontend:
  stage: build
  image: node:22-alpine
  script:
    - npm ci
    - npm run build
  artifacts:
    paths:
      - dist/
    expire_in: 1 hour

test-backend:
  stage: test
  image: gradle:8.12-jdk21
  needs: [build-backend]
  script:
    - ./gradlew test --no-daemon
  artifacts:
    reports:
      junit: '**/build/test-results/test/TEST-*.xml'

test-frontend:
  stage: test
  image: node:22-alpine
  needs: [build-frontend]
  script:
    - npm test -- --ci --coverage
  coverage: '/Lines\s*:\s*(\d+\.?\d*)%/'
  artifacts:
    reports:
      junit: junit-results.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura-coverage.xml

sast:
  stage: security
  needs: []
  variables:
    SAST_EXCLUDED_ANALYZERS: ''
  include:
    - template: Security/SAST.gitlab-ci.yml

deploy-staging:
  stage: deploy
  needs: [test-backend, test-frontend, sast]
  environment:
    name: staging
    url: https://staging.example.com
  script:
    - deploy-to-staging.sh
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

Note that `sast` declares `needs: []` — an empty dependency list means it starts immediately without waiting for any previous stage, running in parallel with the build stage. The `deploy-staging` job `needs:` all three verification jobs, starting as soon as the last one completes regardless of which stage they belong to.

### Include/Extends Composition

GitLab CI's `include:` and `extends:` keywords enable modular pipeline configuration. `include:` pulls in YAML fragments from local files, remote URLs, other projects, or GitLab CI/CD templates. `extends:` inherits configuration from abstract job definitions (prefixed with `.`). Together, they eliminate duplication across pipelines while maintaining readability.

**Shared template file (`ci/templates/gradle-build.yml`):**
```yaml
.gradle-base:
  image: gradle:8.12-jdk21
  variables:
    GRADLE_OPTS: '-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=4'
  cache:
    key:
      files:
        - gradle/wrapper/gradle-wrapper.properties
        - gradle/libs.versions.toml
    paths:
      - .gradle/caches/
      - .gradle/wrapper/
    policy: pull
  before_script:
    - gradle --version

.gradle-build:
  extends: .gradle-base
  stage: build
  script:
    - ./gradlew build --parallel --warning-mode=all
  artifacts:
    paths:
      - '**/build/libs/*.jar'
    reports:
      junit: '**/build/test-results/test/TEST-*.xml'
    expire_in: 1 day
  cache:
    policy: pull-push

.gradle-test:
  extends: .gradle-base
  stage: test
  script:
    - ./gradlew test --parallel
  artifacts:
    reports:
      junit: '**/build/test-results/test/TEST-*.xml'
    when: always
```

**Consuming the template in `.gitlab-ci.yml`:**
```yaml
include:
  - local: ci/templates/gradle-build.yml
  - project: 'my-org/ci-templates'
    ref: v2.1.0
    file: '/templates/deploy.yml'
  - template: Security/SAST.gitlab-ci.yml

stages:
  - build
  - test
  - security
  - deploy

build:
  extends: .gradle-build

unit-tests:
  extends: .gradle-test
  variables:
    GRADLE_OPTS: '-Dorg.gradle.daemon=false -Dspring.profiles.active=test'

integration-tests:
  extends: .gradle-test
  services:
    - postgres:16-alpine
  variables:
    POSTGRES_DB: testdb
    POSTGRES_USER: test
    POSTGRES_PASSWORD: test
    SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/testdb
  script:
    - ./gradlew integrationTest --parallel
```

The `include: project:` directive references templates from another GitLab project — pinned to a tag (`ref: v2.1.0`) for stability. This enables organization-wide CI standardization: update one template repository to change how all 50 services build, test, and deploy. The `extends:` keyword merges configuration deeply — a job extending `.gradle-base` inherits the image, variables, cache, and before_script, then overrides or adds its own configuration.

### Multi-Project Pipelines

Multi-project pipelines trigger downstream builds in other repositories, passing variables and artifacts between them. This pattern coordinates builds across microservice boundaries — when the API contract changes, trigger consumer service builds to verify compatibility.

**Triggering downstream pipelines:**
```yaml
stages:
  - build
  - test
  - trigger-downstream

build:
  stage: build
  script:
    - ./gradlew build --no-daemon

trigger-api-consumers:
  stage: trigger-downstream
  trigger:
    project: my-org/consumer-service
    branch: main
    strategy: depend
  variables:
    UPSTREAM_PIPELINE_ID: $CI_PIPELINE_ID
    UPSTREAM_COMMIT_SHA: $CI_COMMIT_SHA
    API_SPEC_URL: $CI_API_V4_URL/projects/$CI_PROJECT_ID/jobs/artifacts/$CI_COMMIT_REF_NAME/raw/build/api-spec.json?job=build
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      changes:
        - src/main/kotlin/com/example/api/**

trigger-deploy-infra:
  stage: trigger-downstream
  trigger:
    project: my-org/infrastructure
    branch: main
  variables:
    SERVICE_IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_TAG
```

The `strategy: depend` option makes the upstream pipeline wait for the downstream pipeline to complete — the upstream pipeline status reflects the downstream result. Without it, the trigger is fire-and-forget. Use `changes:` rules to trigger downstream only when relevant files change (API contract files, schema definitions).

### Parent-Child Pipelines

Parent-child pipelines dynamically generate child pipeline YAML at runtime. The parent pipeline runs a job that creates a YAML file, then triggers it as a child pipeline. This pattern enables dynamic pipeline generation based on repository structure (monorepo service discovery), changed files (selective testing), or external configuration.

**Dynamic child pipeline generation:**
```yaml
stages:
  - generate
  - child

detect-changes:
  stage: generate
  image: alpine:3.20
  script:
    - |
      echo "stages:" > child-pipeline.yml
      echo "  - test" >> child-pipeline.yml
      for service in services/*/; do
        name=$(basename "$service")
        if git diff --name-only $CI_MERGE_REQUEST_DIFF_BASE_SHA...$CI_COMMIT_SHA | grep -q "^$service"; then
          cat >> child-pipeline.yml <<YAML
      test-${name}:
        stage: test
        image: gradle:8.12-jdk21
        script:
          - cd services/${name}
          - ./gradlew test --no-daemon
        artifacts:
          reports:
            junit: 'services/${name}/**/build/test-results/test/TEST-*.xml'
      YAML
        fi
      done
  artifacts:
    paths:
      - child-pipeline.yml

run-tests:
  stage: child
  needs: [detect-changes]
  trigger:
    include:
      - artifact: child-pipeline.yml
        job: detect-changes
    strategy: depend
```

The parent pipeline detects which services changed, generates a child pipeline YAML with only the relevant test jobs, and triggers it. In a monorepo with 20 services, this avoids running all 20 test suites when only 2 services changed — reducing pipeline duration from 30 minutes to 5 minutes.

### Review Apps with Dynamic Environments

Review apps create ephemeral environments for every merge request, deploying the branch code to a unique URL for manual testing and stakeholder review. GitLab's environment lifecycle management handles creation, URL tracking, and automatic cleanup when the merge request is closed.

**Review app deployment:**
```yaml
deploy-review:
  stage: deploy
  image: bitnami/kubectl:1.31
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    url: https://$CI_COMMIT_REF_SLUG.review.example.com
    on_stop: stop-review
    auto_stop_in: 1 week
  script:
    - kubectl apply -f k8s/review/ --namespace review-$CI_COMMIT_REF_SLUG
    - kubectl set image deployment/app app=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
      --namespace review-$CI_COMMIT_REF_SLUG
  rules:
    - if: $CI_MERGE_REQUEST_ID

stop-review:
  stage: deploy
  image: bitnami/kubectl:1.31
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    action: stop
  script:
    - kubectl delete namespace review-$CI_COMMIT_REF_SLUG --ignore-not-found
  rules:
    - if: $CI_MERGE_REQUEST_ID
      when: manual
  allow_failure: true
```

The `on_stop:` directive links the deployment to its cleanup job. `auto_stop_in: 1 week` automatically triggers the stop job if the environment has been idle for a week, preventing resource leaks from forgotten merge requests. The environment URL appears in the merge request UI, giving reviewers one-click access to the deployed branch.

## Configuration

### Development

**Complete development pipeline (`.gitlab-ci.yml`):**
```yaml
default:
  image: gradle:8.12-jdk21
  interruptible: true

variables:
  GRADLE_OPTS: '-Dorg.gradle.daemon=false'
  GIT_DEPTH: 20

stages:
  - build
  - test
  - quality

cache:
  key:
    files:
      - gradle/wrapper/gradle-wrapper.properties
      - gradle/libs.versions.toml
  paths:
    - .gradle/caches/
    - .gradle/wrapper/
  policy: pull

build:
  stage: build
  script:
    - ./gradlew assemble --parallel --warning-mode=all
  artifacts:
    paths:
      - '**/build/libs/*.jar'
    expire_in: 1 hour
  cache:
    policy: pull-push

test:
  stage: test
  needs: [build]
  script:
    - ./gradlew test --parallel
  artifacts:
    reports:
      junit: '**/build/test-results/test/TEST-*.xml'
    when: always

lint:
  stage: quality
  needs: []
  script:
    - ./gradlew detekt --parallel
  artifacts:
    reports:
      codequality: '**/build/reports/detekt/detekt.json'
  allow_failure: true

workflow:
  rules:
    - if: $CI_MERGE_REQUEST_ID
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

The `default:` block sets shared configuration for all jobs (image, interruptibility). The `interruptible: true` flag allows GitLab to cancel running jobs when a new pipeline starts for the same merge request — equivalent to GitHub Actions' `concurrency.cancel-in-progress`. The `GIT_DEPTH: 20` shallow clone reduces checkout time. The `workflow: rules:` block at the bottom controls when pipelines run — merge requests and default branch only, preventing duplicate pipelines on push + MR events.

### Production

**Production pipeline with environments and approvals:**
```yaml
include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Dependency-Scanning.gitlab-ci.yml
  - template: Security/Secret-Detection.gitlab-ci.yml

stages:
  - build
  - test
  - security
  - package
  - deploy

build:
  stage: build
  script:
    - ./gradlew build --no-daemon --parallel
  artifacts:
    paths:
      - build/libs/*.jar
    expire_in: 1 day

package:
  stage: package
  image: docker:27
  services:
    - docker:27-dind
  variables:
    DOCKER_TLS_CERTDIR: '/certs'
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA -t $CI_REGISTRY_IMAGE:latest .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
    - docker push $CI_REGISTRY_IMAGE:latest
  rules:
    - if: $CI_COMMIT_TAG

deploy-staging:
  stage: deploy
  environment:
    name: staging
    url: https://staging.example.com
  script:
    - deploy.sh staging $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_TAG

deploy-production:
  stage: deploy
  environment:
    name: production
    url: https://api.example.com
    deployment_tier: production
  script:
    - deploy.sh production $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_TAG
      when: manual
  allow_failure: false
  needs: [deploy-staging]
```

The `when: manual` on `deploy-production` creates a manual gate — the pipeline pauses until an authorized user clicks the play button. Combined with `allow_failure: false`, the pipeline is blocked (shown as "blocked" status) until the manual action completes. Protected environments (configured in GitLab settings) restrict who can trigger the deployment.

## Performance

**Cache configuration** is the primary performance lever. GitLab CI caches are stored on the runner (local) or in object storage (distributed). The cache key strategy determines effectiveness:

```yaml
cache:
  key:
    files:
      - gradle/wrapper/gradle-wrapper.properties
      - gradle/libs.versions.toml
      - package-lock.json
    prefix: $CI_JOB_NAME
  paths:
    - .gradle/caches/
    - node_modules/
  policy: pull
```

The `files:` key generates a hash from the listed dependency manifests — any change creates a new cache key. The `prefix:` adds job-name isolation to prevent cross-job cache pollution. Use `policy: pull` (read-only) by default and `policy: pull-push` (read-write) only on jobs that should populate the cache (typically the build job on the default branch).

**Shallow cloning** reduces checkout time for repositories with large histories:
```yaml
variables:
  GIT_DEPTH: 20
  GIT_SUBMODULE_STRATEGY: recursive
```

**Parallel test splitting** distributes test suites across multiple job instances:
```yaml
test:
  stage: test
  parallel: 4
  script:
    - ./gradlew test --parallel -Ptest.include=$(./scripts/split-tests.sh $CI_NODE_INDEX $CI_NODE_TOTAL)
```

**Interruptible pipelines** cancel redundant runs:
```yaml
default:
  interruptible: true

stages:
  - build
  - test
  - deploy

deploy:
  interruptible: false
```

Mark all jobs as interruptible except deployments. When a new commit is pushed to a merge request, GitLab cancels the running pipeline and starts a new one — avoiding waste on outdated code.

**Runner tags** route jobs to appropriate infrastructure:
```yaml
build-heavy:
  tags:
    - high-memory
    - linux
  script:
    - ./gradlew build --no-daemon -Dorg.gradle.workers.max=8
```

## Security

**Protected variables** restrict secret access to protected branches and tags only. Variables marked as protected are not exposed to pipelines running on feature branches or merge requests from forks. Configure in Settings > CI/CD > Variables:

```yaml
deploy-production:
  stage: deploy
  script:
    - echo "$PRODUCTION_DEPLOY_KEY" | base64 -d > deploy-key.pem
    - deploy.sh production
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
  environment:
    name: production
```

**Variable masking** prevents sensitive values from appearing in job logs. Mark variables as "Masked" in the CI/CD settings — GitLab redacts any occurrence of the value from all log output. Variables must be at least 8 characters and match a specific regex to be maskable.

**Group-level variables** share secrets across all projects in a GitLab group. This eliminates per-project secret duplication for shared credentials (container registry tokens, deployment keys, monitoring API keys). Group variables inherit to subgroups, providing hierarchical secret management.

**Deploy tokens** provide read-only access to the container registry and package registry without exposing user credentials. They are scoped to a project or group and have configurable expiration:
```yaml
package:
  script:
    - docker login -u $CI_DEPLOY_USER -p $CI_DEPLOY_PASSWORD $CI_REGISTRY
    - docker pull $CI_REGISTRY_IMAGE:latest || true
    - docker build --cache-from $CI_REGISTRY_IMAGE:latest -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
```

**Secret detection** identifies accidentally committed credentials. GitLab's built-in template scans for API keys, tokens, passwords, and private keys:
```yaml
include:
  - template: Security/Secret-Detection.gitlab-ci.yml
```

**Compliance pipelines** (GitLab Ultimate) enforce organizational CI/CD requirements that individual projects cannot bypass. The compliance pipeline configuration is stored in a separate project and automatically prepended or appended to every project pipeline in the group. This ensures security scanning, license checks, and audit logging run even if a project team removes them from their `.gitlab-ci.yml`.

**Pipeline security checklist:**
- Mark all deployment credentials as Protected and Masked.
- Use group-level variables for shared secrets to avoid duplication.
- Include GitLab security templates (SAST, Dependency Scanning, Secret Detection) in every pipeline.
- Use protected branches and tags to restrict which pipelines can access production credentials.
- Use deploy tokens instead of personal access tokens for registry access.
- Configure merge request approval rules to require security scan passing before merge.
- Enable pipeline configuration validation (CI Lint) to catch misconfigurations before they run.

## Testing

**Validating `.gitlab-ci.yml` before pushing:**
```bash
# Using GitLab's CI Lint API
curl --request POST \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{\"content\": $(cat .gitlab-ci.yml | jq -Rs .)}" \
  "https://gitlab.example.com/api/v4/ci/lint"

# Using the glab CLI
glab ci lint .gitlab-ci.yml
```

**Testing pipeline includes locally** — the `gitlab-ci-local` tool runs pipelines on your machine:
```bash
# Install
npm install -g gitlab-ci-local

# Run all jobs
gitlab-ci-local

# Run a specific job
gitlab-ci-local --job build

# List all jobs
gitlab-ci-local --list
```

**Testing variable expansion and rules:**
```bash
# Simulate merge request context
gitlab-ci-local --variable CI_MERGE_REQUEST_ID=123

# Simulate tag context
gitlab-ci-local --variable CI_COMMIT_TAG=v1.0.0
```

**Integration testing for multi-project pipelines** — create a test project that mirrors the downstream trigger setup and verify variables and artifacts pass correctly. Use `strategy: depend` during testing to ensure the parent pipeline reflects child failures.

**Testing services (databases, caches) in CI:**
```yaml
integration-test:
  stage: test
  services:
    - name: postgres:16-alpine
      alias: db
    - name: redis:7-alpine
      alias: cache
  variables:
    POSTGRES_DB: testdb
    POSTGRES_USER: test
    POSTGRES_PASSWORD: test
    DATABASE_URL: postgresql://test:test@db:5432/testdb
    REDIS_URL: redis://cache:6379
  script:
    - ./gradlew integrationTest --no-daemon
```

Services are Docker containers running alongside the job container on the same network. Use `alias:` to set predictable hostnames. Services start before the job's `before_script` and are destroyed after the job completes.

## Dos

- Use `needs:` to create DAG pipelines that break sequential stage ordering. Jobs that have no dependency on each other should run in parallel regardless of their stage. This can cut pipeline duration by 30-60%.
- Use `include:` with versioned references (`ref: v2.1.0`) for shared pipeline templates. Store organization-wide templates in a dedicated project and pin consumers to tags for stability.
- Use `extends:` with abstract job definitions (`.dot-prefixed`) to eliminate duplication. Layer templates by composing them — `.gradle-test` extends `.gradle-base` which sets image, cache, and variables.
- Use `workflow: rules:` to control when pipelines run. Prevent duplicate pipelines on push + MR events by explicitly defining the pipeline trigger conditions at the workflow level.
- Mark all jobs as `interruptible: true` except deployments. This allows GitLab to cancel outdated pipelines when new commits are pushed, saving runner time.
- Use `cache: key: files:` with dependency manifest hashes for automatic cache invalidation. Separate cache policies: `pull-push` for the build job on the default branch, `pull` for everything else.
- Use protected variables and protected environments for deployment credentials. Never expose production secrets to merge request pipelines or unprotected branches.
- Use `artifacts: reports: junit:` to surface test results directly in the merge request UI. Include `when: always` on test artifacts so results are available even when tests fail.
- Include GitLab security templates (SAST, Dependency Scanning, Secret Detection) as a baseline in every project pipeline.

## Don'ts

- Don't rely solely on sequential stages without `needs:`. The default stage model forces all jobs in stage N to complete before stage N+1 starts, even when there are no dependencies between them. This serializes inherently parallel work.
- Don't use `only:` and `except:` — they are legacy syntax replaced by `rules:`. The `rules:` keyword provides clearer logic with `if:`, `changes:`, `exists:`, `when:`, and `allow_failure:` in a single, readable structure.
- Don't store secrets in `.gitlab-ci.yml` — not even in variable defaults. Use CI/CD variables configured in the GitLab UI, marked as Protected and Masked. Group-level variables for shared secrets.
- Don't use `cache: policy: pull-push` on every job. Only the job that populates the cache (typically build on the default branch) should push. All other jobs should use `pull` to avoid cache contention and corruption from parallel writes.
- Don't skip `artifacts: expire_in:` on build artifacts. The default retention is 30 days, which accumulates significant storage. Set explicit expiration: 1 hour for inter-job artifacts, 1 day for build outputs, 1 week for deployment artifacts.
- Don't use `when: always` on deployment jobs. It causes deployments to run even when tests fail. Use `when: manual` for production deployments and ensure `allow_failure: false` to block the pipeline until the manual action completes.
- Don't create pipelines without `GIT_DEPTH` set. Full clones of large repositories waste minutes on checkout. Set `GIT_DEPTH: 20` (or appropriate depth) in default variables.
- Don't use Docker-in-Docker (dind) without TLS. Set `DOCKER_TLS_CERTDIR: '/certs'` and use the matching dind service version to enable TLS between the job container and the Docker daemon.
- Don't define `image:` per job when all jobs use the same image. Use `default: image:` to set it once. Override only for jobs that genuinely need a different image.
