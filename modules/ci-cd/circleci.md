# CircleCI

## Overview

CircleCI is a cloud-native CI/CD platform that defines pipelines in a `.circleci/config.yml` file. Pipelines consist of workflows (orchestration layer) containing jobs (execution units) that run on CircleCI's managed execution environments — Docker containers, Linux VMs, macOS VMs, Windows VMs, Arm VMs, or self-hosted runners. CircleCI's architecture separates orchestration (workflow engine) from execution (compute environments), enabling efficient resource utilization and fine-grained control over execution contexts.

Use CircleCI when the team needs fast build times with sophisticated caching (CircleCI's cache is persistent and content-addressable), advanced test splitting (automatic parallel distribution of test files across containers), or first-class Docker support (Docker layer caching, remote Docker environments). CircleCI excels at polyglot projects where different jobs need different execution environments within the same pipeline, and at organizations that benefit from Contexts (shared secret namespaces with RBAC) for managing credentials across projects.

Do not use CircleCI for GitHub-exclusive organizations that want maximum platform integration (GitHub Actions provides deeper integration with PRs, checks, and deployments). Do not use CircleCI for air-gapped or fully on-premise requirements — while CircleCI offers a server product, its cloud offering is the primary platform. For Kubernetes-native CI/CD where pipelines should be Kubernetes resources, use Tekton instead.

Key differentiators: (1) Orbs are reusable, versioned packages of pipeline configuration that combine jobs, commands, and executors into shareable units — the most mature reuse mechanism in CI/CD. (2) Test splitting with `circleci tests split` automatically distributes test files across parallel containers by timing data, minimizing wall-clock time. (3) Contexts provide shared secret namespaces with fine-grained RBAC, enabling secure credential sharing across projects. (4) Docker layer caching (DLC) persists Docker build layers between runs, dramatically accelerating image builds. (5) Resource classes allow selecting compute size (small, medium, large, xlarge) per job, matching resources to workload requirements.

## Architecture Patterns

### Orbs (Reusable Packages)

Orbs are versioned packages of reusable CircleCI configuration — collections of jobs, commands, executors, and parameters published to the CircleCI Orb Registry. They encapsulate complex CI/CD patterns (AWS deployment, Kubernetes deployment, Slack notification) into single-line invocations. Orbs can be public (shared across organizations) or private (scoped to an organization).

**Using orbs for common tasks:**
```yaml
version: 2.1

orbs:
  gradle: circleci/gradle@3.0
  docker: circleci/docker@2.6
  aws-ecr: circleci/aws-ecr@9.3
  aws-ecs: circleci/aws-ecs@4.1
  slack: circleci/slack@4.13

workflows:
  build-and-deploy:
    jobs:
      - gradle/test:
          executor:
            name: gradle/default
            tag: '8.12-jdk21'
          test_command: test --parallel

      - docker/publish:
          requires:
            - gradle/test
          image: my-app
          registry: $AWS_ECR_REGISTRY
          tag: $CIRCLE_SHA1
          use-remote-docker: true
          docker-layer-caching: true
          filters:
            branches:
              only: main

      - aws-ecs/deploy-service-update:
          requires:
            - docker/publish
          cluster: production
          service-name: my-app
          container-image-name-updates: 'container=app,tag=${CIRCLE_SHA1}'
          context: aws-production

      - slack/on-hold:
          requires:
            - aws-ecs/deploy-service-update
          context: slack-notifications
```

**Creating a custom orb (`my-orb/orb.yml`):**
```yaml
version: 2.1

description: Organization standard build and deploy orb

executors:
  jdk:
    parameters:
      version:
        type: string
        default: '21'
    docker:
      - image: eclipse-temurin:<< parameters.version >>-jdk
    resource_class: large

commands:
  gradle-build:
    parameters:
      command:
        type: string
        default: './gradlew build --no-daemon --parallel'
    steps:
      - checkout
      - restore_cache:
          keys:
            - gradle-v2-{{ checksum "gradle/libs.versions.toml" }}-{{ checksum "gradle/wrapper/gradle-wrapper.properties" }}
            - gradle-v2-
      - run:
          name: Build
          command: << parameters.command >>
      - save_cache:
          key: gradle-v2-{{ checksum "gradle/libs.versions.toml" }}-{{ checksum "gradle/wrapper/gradle-wrapper.properties" }}
          paths:
            - ~/.gradle/caches
            - ~/.gradle/wrapper
      - store_test_results:
          path: build/test-results
      - store_artifacts:
          path: build/reports

jobs:
  build-and-test:
    executor:
      name: jdk
      version: << parameters.java-version >>
    parameters:
      java-version:
        type: string
        default: '21'
      build-command:
        type: string
        default: './gradlew build --no-daemon --parallel'
    steps:
      - gradle-build:
          command: << parameters.build-command >>
```

**Publishing the orb:**
```bash
# Create namespace (once)
circleci namespace create my-org github my-org

# Create orb (once)
circleci orb create my-org/standard-build

# Publish dev version for testing
circleci orb publish orb.yml my-org/standard-build@dev:alpha

# Promote to production version
circleci orb publish promote my-org/standard-build@dev:alpha semver:minor
```

Orbs follow semantic versioning. Pin consumers to major versions (`@3.0`) for automatic minor/patch updates, or exact versions (`@3.0.2`) for maximum stability. Development versions (`@dev:alpha`) are mutable and expire after 90 days — use them for testing before promotion.

### Contexts (Shared Secrets)

Contexts are named collections of environment variables shared across projects. They provide organizational secret management with RBAC — restrict which teams can use which contexts, which prevents accidental or unauthorized access to production credentials. Contexts are referenced at the workflow level, making the secret scope explicit in the configuration.

**Using contexts in workflows:**
```yaml
version: 2.1

workflows:
  deploy:
    jobs:
      - build:
          context: shared-build-tools

      - deploy-staging:
          requires: [build]
          context:
            - shared-build-tools
            - aws-staging
          filters:
            branches:
              only: main

      - hold-production:
          type: approval
          requires: [deploy-staging]
          filters:
            branches:
              only: main

      - deploy-production:
          requires: [hold-production]
          context:
            - shared-build-tools
            - aws-production
          filters:
            branches:
              only: main
```

The `aws-staging` context contains AWS credentials for the staging account; `aws-production` contains credentials for production. RBAC rules (configured in CircleCI organization settings) restrict `aws-production` to the deployment team. The `type: approval` job creates a manual gate — the pipeline pauses until an authorized user approves the production deployment in the CircleCI UI.

### Workflows with Fan-In/Fan-Out

CircleCI workflows orchestrate job execution with dependency graphs, enabling complex patterns: parallel fan-out (run many jobs simultaneously), fan-in (wait for all parallel jobs to complete), sequential gates, and conditional branching. The workflow engine handles dependency resolution and concurrency automatically.

**Fan-out/fan-in with approval gates:**
```yaml
version: 2.1

workflows:
  build-test-deploy:
    jobs:
      - build

      # Fan-out: parallel test stages
      - unit-tests:
          requires: [build]
      - integration-tests:
          requires: [build]
      - security-scan:
          requires: [build]
      - lint:
          requires: [build]

      # Fan-in: wait for all tests
      - deploy-staging:
          requires:
            - unit-tests
            - integration-tests
            - security-scan
            - lint
          filters:
            branches:
              only: main

      # Approval gate
      - approve-production:
          type: approval
          requires: [deploy-staging]

      # Conditional deployment
      - deploy-production:
          requires: [approve-production]
          context: aws-production
```

The `requires:` array creates explicit dependencies. `deploy-staging` waits for all four test jobs to complete (fan-in). If any test job fails, the deployment does not run. The approval gate pauses the pipeline for human review before production deployment.

### Test Splitting

Test splitting is CircleCI's mechanism for distributing test files across parallel containers to minimize total test execution time. The `circleci tests split` command reads a list of test files and assigns each container a subset based on timing data from previous runs. This ensures even distribution: slow test files are spread across containers rather than concentrated in one.

**Parallel test execution with timing-based splitting:**
```yaml
jobs:
  test:
    parallelism: 4
    docker:
      - image: eclipse-temurin:21-jdk
      - image: postgres:16-alpine
        environment:
          POSTGRES_DB: testdb
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
    steps:
      - checkout

      - restore_cache:
          keys:
            - gradle-v2-{{ checksum "gradle/libs.versions.toml" }}

      - run:
          name: Split and run tests
          command: |
            # Collect test class files
            TEST_CLASSES=$(find . -name "*Test.class" -path "*/build/classes/*" | \
              sed 's/.*build\/classes\/[^\/]*\///' | \
              sed 's/\.class$//' | \
              sed 's/\//./g' | \
              circleci tests split --split-by=timings)

            # Run only the assigned test classes
            ./gradlew test --no-daemon \
              $(echo "$TEST_CLASSES" | sed 's/\S*/--tests \0/g')

      - store_test_results:
          path: build/test-results

      - save_cache:
          key: gradle-v2-{{ checksum "gradle/libs.versions.toml" }}
          paths:
            - ~/.gradle/caches
```

With `parallelism: 4`, CircleCI creates 4 container instances of the job. Each instance receives `$CIRCLE_NODE_INDEX` (0-3) and `$CIRCLE_NODE_TOTAL` (4). The `circleci tests split --split-by=timings` command uses historical test timing data to assign approximately equal total time to each container. On the first run (no timing data), it falls back to file-count-based splitting.

## Configuration

### Development

**Complete development configuration (`.circleci/config.yml`):**
```yaml
version: 2.1

orbs:
  gradle: circleci/gradle@3.0

executors:
  jdk21:
    docker:
      - image: eclipse-temurin:21-jdk
    resource_class: medium
    working_directory: ~/project

jobs:
  build:
    executor: jdk21
    steps:
      - checkout
      - restore_cache:
          keys:
            - gradle-v2-{{ checksum "gradle/libs.versions.toml" }}-{{ checksum "gradle/wrapper/gradle-wrapper.properties" }}
            - gradle-v2-
      - run:
          name: Build
          command: ./gradlew build --no-daemon --parallel --warning-mode=all
      - save_cache:
          key: gradle-v2-{{ checksum "gradle/libs.versions.toml" }}-{{ checksum "gradle/wrapper/gradle-wrapper.properties" }}
          paths:
            - ~/.gradle/caches
            - ~/.gradle/wrapper
      - store_test_results:
          path: build/test-results
      - store_artifacts:
          path: build/reports
          destination: reports
      - persist_to_workspace:
          root: .
          paths:
            - build/libs

  lint:
    executor: jdk21
    steps:
      - checkout
      - restore_cache:
          keys:
            - gradle-v2-{{ checksum "gradle/libs.versions.toml" }}
      - run:
          name: Static analysis
          command: ./gradlew detekt --no-daemon
      - store_artifacts:
          path: build/reports/detekt

workflows:
  ci:
    jobs:
      - build
      - lint
```

The `persist_to_workspace` step shares build artifacts between jobs in the same workflow. The `store_test_results` step enables CircleCI's test insights (timing data for splitting, flaky test detection, test result trends). The `store_artifacts` step makes reports downloadable from the CircleCI UI.

### Production

**Production deployment configuration:**
```yaml
version: 2.1

orbs:
  aws-ecr: circleci/aws-ecr@9.3
  aws-ecs: circleci/aws-ecs@4.1

executors:
  jdk21:
    docker:
      - image: eclipse-temurin:21-jdk
    resource_class: large

jobs:
  build:
    executor: jdk21
    steps:
      - checkout
      - restore_cache:
          keys:
            - gradle-v2-{{ checksum "gradle/libs.versions.toml" }}
      - run:
          name: Build and test
          command: ./gradlew build --no-daemon --parallel
      - save_cache:
          key: gradle-v2-{{ checksum "gradle/libs.versions.toml" }}
          paths:
            - ~/.gradle/caches
      - store_test_results:
          path: build/test-results
      - persist_to_workspace:
          root: .
          paths:
            - build/libs
            - Dockerfile

  build-image:
    docker:
      - image: cimg/base:current
    resource_class: medium
    steps:
      - attach_workspace:
          at: .
      - setup_remote_docker:
          docker_layer_caching: true
      - run:
          name: Build and push Docker image
          command: |
            echo "$ECR_PASSWORD" | docker login --username AWS --password-stdin $ECR_REGISTRY
            docker build -t $ECR_REGISTRY/my-app:$CIRCLE_SHA1 .
            docker push $ECR_REGISTRY/my-app:$CIRCLE_SHA1

  deploy-staging:
    docker:
      - image: cimg/aws:2024.03
    steps:
      - run:
          name: Deploy to ECS staging
          command: |
            aws ecs update-service \
              --cluster staging \
              --service my-app \
              --force-new-deployment
            aws ecs wait services-stable \
              --cluster staging \
              --services my-app

  deploy-production:
    docker:
      - image: cimg/aws:2024.03
    steps:
      - run:
          name: Deploy to ECS production
          command: |
            aws ecs update-service \
              --cluster production \
              --service my-app \
              --force-new-deployment
            aws ecs wait services-stable \
              --cluster production \
              --services my-app

workflows:
  deploy:
    jobs:
      - build:
          filters:
            tags:
              only: /^v.*/
            branches:
              only: main

      - build-image:
          requires: [build]
          context: aws-shared
          filters:
            tags:
              only: /^v.*/
            branches:
              only: main

      - deploy-staging:
          requires: [build-image]
          context: aws-staging
          filters:
            tags:
              only: /^v.*/
            branches:
              only: main

      - approve-production:
          type: approval
          requires: [deploy-staging]
          filters:
            tags:
              only: /^v.*/
            branches:
              ignore: /.*/

      - deploy-production:
          requires: [approve-production]
          context: aws-production
          filters:
            tags:
              only: /^v.*/
            branches:
              ignore: /.*/
```

The `filters:` block controls which branches and tags trigger each job. Production deployment only triggers on tags matching `v*`, ensuring only tagged releases reach production. The `approve-production` gate requires manual approval in the CircleCI UI before the production deployment proceeds.

## Performance

**Docker layer caching** persists Docker build layers between runs. For projects that build Docker images, this can reduce image build time from 5 minutes to 30 seconds when only application code changes:
```yaml
- setup_remote_docker:
    docker_layer_caching: true
```

**Resource classes** match compute to workload. Do not over-provision: use `small` for linting, `medium` for standard builds, `large` for compilation-heavy or memory-intensive jobs:
```yaml
jobs:
  lint:
    resource_class: small
    docker:
      - image: node:22-alpine
    steps:
      - run: npm run lint

  build:
    resource_class: large
    docker:
      - image: eclipse-temurin:21-jdk
    steps:
      - run: ./gradlew build --no-daemon -Dorg.gradle.workers.max=4
```

**Workspace persistence** passes artifacts between jobs without re-downloading or rebuilding:
```yaml
- persist_to_workspace:
    root: .
    paths:
      - build/libs
      - dist/

# In downstream job:
- attach_workspace:
    at: .
```

Workspaces transfer via a tarball through CircleCI's storage — keep them small by persisting only what downstream jobs need.

**Cache optimization** — use multiple caches for different concerns:
```yaml
- restore_cache:
    keys:
      - gradle-deps-v2-{{ checksum "gradle/libs.versions.toml" }}
      - gradle-deps-v2-

- restore_cache:
    keys:
      - npm-deps-v2-{{ checksum "package-lock.json" }}
      - npm-deps-v2-
```

Separate caches for separate dependency managers prevent cache invalidation of npm dependencies when only Gradle dependencies change.

**Conditional workflow execution** with pipeline parameters:
```yaml
parameters:
  run-integration-tests:
    type: boolean
    default: true

jobs:
  integration-test:
    when: << pipeline.parameters.run-integration-tests >>
```

## Security

**Context RBAC** — restrict which teams can use which contexts. In CircleCI organization settings, assign security groups to contexts. Only members of the assigned group can trigger workflows that reference the context. This prevents developers from accidentally using production credentials in test pipelines.

**Environment variable scoping** — CircleCI supports four levels of environment variables with increasing precedence: organization-level (contexts), project-level (project settings), job-level (`environment:` in config), and step-level (`environment:` in steps). Production secrets should be in restricted contexts, not project-level variables which any branch can access.

**Restricted contexts** — configure contexts to require approval from a security group before they can be used in a workflow. This adds a manual gate: when a workflow references a restricted context, it pauses until an authorized user approves.

**SSH key management** — CircleCI injects deploy keys and user keys for repository checkout. Use read-only deploy keys for builds and read-write keys only for jobs that need to push (releases, documentation updates). Rotate keys periodically.

**Security checklist:**
- Use contexts for all secrets — not project-level environment variables for sensitive credentials.
- Configure RBAC on contexts containing production credentials.
- Pin orb versions to specific semver (not `volatile` or `dev:` versions).
- Use `setup_remote_docker` for Docker builds — do not mount the host Docker socket.
- Enable 2FA for all organization members.
- Restrict which branches can trigger deployment workflows using `filters:`.
- Audit context usage regularly — remove unused contexts and revoke stale credentials.

## Testing

**Validating configuration locally:**
```bash
# Install CircleCI CLI
brew install circleci

# Validate config syntax
circleci config validate

# Process config (expand orbs, resolve includes)
circleci config process .circleci/config.yml

# Run a specific job locally
circleci local execute --job build
```

The `circleci config process` command expands orbs and resolves all dynamic elements, showing the final YAML that CircleCI will execute. This is essential for debugging orb parameter expansion and conditional logic.

**Testing orbs before publishing:**
```bash
# Validate orb syntax
circleci orb validate orb.yml

# Publish dev version
circleci orb publish orb.yml my-org/my-orb@dev:testing

# Test in a pipeline
# Reference: my-org/my-orb@dev:testing
```

**Testing with local execution:**
```bash
# Run build job with local Docker
circleci local execute --job build \
  -e CIRCLE_BRANCH=main \
  -e CIRCLE_SHA1=abc123
```

Local execution runs the job in Docker containers on the developer's machine. It does not support all features (workspaces, caching, and some orbs may not work), but it catches most configuration errors before pushing.

## Dos

- Use orbs for common CI/CD patterns. The CircleCI Orb Registry contains certified orbs for AWS, GCP, Docker, Slack, and dozens of other integrations. Custom orbs standardize organization-specific patterns across projects.
- Use contexts for all credentials and sensitive environment variables. Context RBAC restricts access to authorized teams. Never store production credentials as project-level environment variables.
- Use `parallelism:` with `circleci tests split --split-by=timings` for test suites exceeding 3 minutes. Timing-based splitting distributes tests evenly across containers, often halving total test time.
- Use `store_test_results` for all test output. CircleCI uses this data for test insights (timing analysis, flaky test detection) and timing-based test splitting in future runs.
- Use `resource_class` to match compute to workload. Over-provisioning wastes credits; under-provisioning slows builds. Use `small` for linting, `medium` for standard builds, `large` for compilation.
- Pin orbs to major versions (`@3.0`) for automatic minor/patch updates, or exact versions (`@3.0.2`) for maximum stability. Never use `volatile` in production.
- Use approval gates (`type: approval`) for production deployments. Combined with context RBAC, this provides auditable, role-based deployment authorization.
- Use `setup_remote_docker` with `docker_layer_caching: true` for Docker image builds. DLC persists layers between runs, dramatically reducing image build times.
- Use `persist_to_workspace` and `attach_workspace` to share artifacts between jobs. Do not rebuild artifacts that already exist in the workspace.

## Don'ts

- Don't use project-level environment variables for production secrets. They are accessible to all branches, including feature branches and forks. Use restricted contexts with RBAC instead.
- Don't set `parallelism:` without implementing test splitting. Without `circleci tests split`, all containers run the full test suite — multiplying execution time instead of dividing it.
- Don't ignore test timing data. Without `store_test_results`, CircleCI cannot optimize test splitting and cannot detect flaky tests. Always store test results for every test job.
- Don't use `large` or `xlarge` resource classes for every job. CircleCI bills by resource class. A lint job that uses 200MB of RAM does not need 8GB. Match resource class to actual resource requirements.
- Don't cache build outputs (compiled classes, bundled assets) — cache only dependency downloads. Build outputs change on every commit; caching them wastes upload/download time without saving rebuild time.
- Don't use `setup_remote_docker` for non-Docker jobs. The remote Docker environment adds startup overhead (10-30 seconds). Only enable it for jobs that actually build or run Docker containers.
- Don't use `dev:` orb versions in production pipelines. Development versions are mutable and expire after 90 days. They provide no stability guarantee. Promote to a semver release before production use.
- Don't skip `filters:` on deployment jobs. Without branch/tag filters, deployment jobs run on every push to every branch, including feature branches and forks.
- Don't use `persist_to_workspace` for large artifacts (>1 GB). Workspace transfers are uploaded to and downloaded from CircleCI's storage, which adds latency proportional to size. Use external artifact storage (S3, GCS) for large files.
