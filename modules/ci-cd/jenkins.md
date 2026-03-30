# Jenkins

## Overview

Open-source automation server orchestrating CI/CD via `Jenkinsfile` (Pipeline-as-Code). Runs on any infrastructure (bare metal, VMs, containers, K8s) with controller-agent distributed execution and 1,800+ plugins.

- **Use for:** air-gapped/on-premise environments, heterogeneous build agents (Linux/Windows/macOS/ARM), long-running pipelines (no timeout limits), complex orchestration with approval gates
- **Avoid for:** new greenfield projects on GitHub/GitLab (use native CI), teams without capacity to manage Jenkins infrastructure, K8s-native declarative pipelines (use Tekton)
- **Key features:** shared libraries (org-wide pipeline reuse), multibranch pipeline auto-discovery, horizontal scaling via dynamic agent provisioning (K8s/Docker/cloud VMs), 1,800+ plugin ecosystem

## Architecture Patterns

### Declarative Pipelines

Declarative pipeline syntax is the recommended approach for Jenkins pipelines. It provides a structured, opinionated format with clear sections (`agent`, `stages`, `steps`, `post`) that is easier to read, write, and maintain than scripted pipelines. The declarative syntax enforces a consistent structure while providing `script {}` blocks as escape hatches for complex logic.

**Complete declarative pipeline (`Jenkinsfile`):**
```groovy
pipeline {
    agent {
        label 'jdk21'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds(abortPrevious: true)
        timestamps()
    }

    environment {
        GRADLE_OPTS = '-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=4'
        APP_VERSION = sh(script: './gradlew properties -q | grep "^version:" | awk \'{print $2}\'', returnStdout: true).trim()
    }

    tools {
        jdk 'temurin-21'
        gradle 'gradle-8.12'
    }

    stages {
        stage('Build') {
            steps {
                sh './gradlew build --parallel --warning-mode=all'
            }
            post {
                always {
                    junit '**/build/test-results/test/TEST-*.xml'
                    archiveArtifacts artifacts: '**/build/libs/*.jar', fingerprint: true
                }
            }
        }

        stage('Quality') {
            parallel {
                stage('Static Analysis') {
                    steps {
                        sh './gradlew detekt'
                    }
                    post {
                        always {
                            recordIssues(tools: [detekt(pattern: '**/build/reports/detekt/detekt.xml')])
                        }
                    }
                }
                stage('Security Scan') {
                    steps {
                        sh './gradlew dependencyCheckAnalyze'
                    }
                    post {
                        always {
                            dependencyCheckPublisher pattern: '**/build/reports/dependency-check-report.xml'
                        }
                    }
                }
            }
        }

        stage('Docker') {
            when {
                branch 'main'
            }
            steps {
                script {
                    def image = docker.build("my-app:${env.APP_VERSION}")
                    docker.withRegistry('https://registry.example.com', 'docker-registry-creds') {
                        image.push()
                        image.push('latest')
                    }
                }
            }
        }

        stage('Deploy Staging') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-staging', variable: 'KUBECONFIG')]) {
                    sh "kubectl set image deployment/my-app app=registry.example.com/my-app:${env.APP_VERSION}"
                    sh 'kubectl rollout status deployment/my-app --timeout=300s'
                }
            }
        }

        stage('Deploy Production') {
            when {
                buildingTag()
            }
            input {
                message 'Deploy to production?'
                ok 'Deploy'
                submitter 'admin,deployers'
            }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-production', variable: 'KUBECONFIG')]) {
                    sh "kubectl set image deployment/my-app app=registry.example.com/my-app:${env.APP_VERSION}"
                    sh 'kubectl rollout status deployment/my-app --timeout=300s'
                }
            }
        }
    }

    post {
        failure {
            slackSend(channel: '#builds', color: 'danger',
                message: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>)")
        }
        success {
            slackSend(channel: '#builds', color: 'good',
                message: "SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>)")
        }
        cleanup {
            cleanWs()
        }
    }
}
```

Key declarative features: `parallel {}` runs stages concurrently within a parent stage. `when {}` conditionalizes stage execution based on branch, tag, or expression. `input {}` pauses the pipeline for human approval with role-based access (`submitter`). `post {}` blocks handle success, failure, and cleanup at both stage and pipeline levels. `options { disableConcurrentBuilds(abortPrevious: true) }` cancels the previous build when a new one starts — essential for PR builds.

### Shared Libraries

Shared libraries extract reusable pipeline logic into a separate Git repository, loaded by Jenkins at pipeline startup. They enable organization-wide standardization: 100 service repositories share the same build, test, and deploy logic without copy-paste. Changes to the library propagate to all consumers on the next build.

**Library structure (`jenkins-shared-library/`):**
```
vars/
  gradleBuild.groovy
  dockerPublish.groovy
  deployToK8s.groovy
  standardPipeline.groovy
src/
  com/example/ci/
    BuildConfig.groovy
    DeployTarget.groovy
resources/
  com/example/ci/
    deploy-template.yaml
```

**`vars/gradleBuild.groovy`** — a global function callable from any Jenkinsfile:
```groovy
def call(Map config = [:]) {
    def javaVersion = config.javaVersion ?: '21'
    def buildCommand = config.buildCommand ?: './gradlew build --no-daemon --parallel'

    pipeline {
        agent {
            label "jdk${javaVersion}"
        }

        options {
            timeout(time: 30, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: '10'))
            disableConcurrentBuilds(abortPrevious: true)
        }

        tools {
            jdk "temurin-${javaVersion}"
        }

        stages {
            stage('Build') {
                steps {
                    sh buildCommand
                }
                post {
                    always {
                        junit '**/build/test-results/test/TEST-*.xml'
                    }
                }
            }
        }

        post {
            cleanup {
                cleanWs()
            }
        }
    }
}
```

**`vars/deployToK8s.groovy`** — a step function for deployment:
```groovy
def call(Map config) {
    def environment = config.environment
    def image = config.image
    def namespace = config.namespace ?: environment
    def credentialsId = "kubeconfig-${environment}"

    withCredentials([file(credentialsId: credentialsId, variable: 'KUBECONFIG')]) {
        sh """
            kubectl set image deployment/${config.service} \
                app=${image} \
                --namespace ${namespace}
            kubectl rollout status deployment/${config.service} \
                --namespace ${namespace} \
                --timeout=300s
        """
    }
}
```

**Consuming the shared library in a service's `Jenkinsfile`:**
```groovy
@Library('my-org-shared-library@v2.1') _

gradleBuild(
    javaVersion: '21',
    buildCommand: './gradlew build --no-daemon --parallel'
)
```

The `@Library` annotation loads the shared library from the configured Git repository. Pin to a tag (`@v2.1`) for stability — `@main` receives changes immediately, which can break consumer pipelines. The underscore (`_`) after the annotation is required syntax when importing the entire library. The `vars/` directory contains global functions; `src/` contains regular Groovy classes for complex logic; `resources/` contains template files accessible via `libraryResource()`.

### Multibranch Pipelines

Multibranch pipelines automatically discover branches and pull requests in a repository, creating a pipeline instance for each. When a new branch is pushed or a PR is opened, Jenkins creates a new pipeline job. When the branch is deleted, the job is removed. This eliminates manual job configuration and ensures every branch gets CI feedback.

**Multibranch pipeline configuration (via `Jenkinsfile` in each branch):**
```groovy
pipeline {
    agent any

    stages {
        stage('Build') {
            steps {
                sh './gradlew build --no-daemon'
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                sh './deploy.sh staging'
            }
        }
    }
}
```

The `when { branch 'main' }` directive ensures deployment stages only run on the main branch — feature branch builds skip them automatically. Multibranch pipeline discovery is configured in Jenkins (Manage Jenkins > New Item > Multibranch Pipeline), pointing at the repository and specifying branch discovery behaviors (all branches, only those with PRs, only protected branches).

**Organization folders** extend multibranch to all repositories in a GitHub or GitLab organization. Jenkins scans the organization, finds repositories containing a `Jenkinsfile`, and creates multibranch pipeline jobs for each. New repositories are automatically onboarded — push a `Jenkinsfile` and Jenkins discovers it.

### Pipeline-as-Code with Configuration

Separating pipeline configuration from pipeline logic keeps `Jenkinsfile` files concise while allowing per-repository customization. The shared library provides the pipeline structure; a configuration file in each repository provides the parameters.

**`ci-config.yaml` in the service repository:**
```yaml
service:
  name: user-service
  language: kotlin
  jdk: '21'

build:
  command: './gradlew build --no-daemon --parallel'
  test_reports: '**/build/test-results/test/TEST-*.xml'

docker:
  registry: registry.example.com
  image_name: user-service

deploy:
  staging:
    cluster: staging
    namespace: user-service
  production:
    cluster: production
    namespace: user-service
    approvers: 'admin,lead-devs'
```

**Shared library consuming the configuration (`vars/standardPipeline.groovy`):**
```groovy
def call() {
    def config = readYaml(file: 'ci-config.yaml')

    pipeline {
        agent { label "jdk${config.service.jdk}" }

        stages {
            stage('Build') {
                steps {
                    sh config.build.command
                }
                post {
                    always {
                        junit config.build.test_reports
                    }
                }
            }

            stage('Docker') {
                when { branch 'main' }
                steps {
                    script {
                        def image = docker.build("${config.docker.image_name}:${env.BUILD_NUMBER}")
                        docker.withRegistry("https://${config.docker.registry}", 'docker-creds') {
                            image.push()
                        }
                    }
                }
            }

            stage('Deploy Staging') {
                when { branch 'main' }
                steps {
                    deployToK8s(
                        environment: 'staging',
                        service: config.service.name,
                        image: "${config.docker.registry}/${config.docker.image_name}:${env.BUILD_NUMBER}",
                        namespace: config.deploy.staging.namespace
                    )
                }
            }
        }
    }
}
```

**Service `Jenkinsfile`:**
```groovy
@Library('my-org-shared-library@v2') _
standardPipeline()
```

This pattern reduces every service's `Jenkinsfile` to two lines while maintaining per-service customization through the YAML configuration file. The shared library enforces organizational standards (security scanning, artifact fingerprinting, notification) while the config file controls service-specific parameters.

### Blue Ocean Visualization

Blue Ocean is a Jenkins plugin providing a modern, visual pipeline editor and execution viewer. It renders pipelines as visual graphs showing parallel stages, sequential flows, and stage status in an intuitive interface. While the classic Jenkins UI shows builds as flat log streams, Blue Ocean displays the pipeline structure, making complex multi-stage pipelines comprehensible at a glance.

Blue Ocean automatically generates visualizations from declarative pipeline definitions — no additional configuration required. It also provides a visual pipeline editor for creating pipelines through a drag-and-drop interface, though teams should prefer `Jenkinsfile` in version control for reproducibility.

## Configuration

### Development

**Jenkins configuration-as-code (`jenkins.yaml`)** — the JCasC plugin configures Jenkins declaratively, replacing manual UI configuration:
```yaml
jenkins:
  systemMessage: 'Jenkins configured via JCasC'
  numExecutors: 0
  securityRealm:
    local:
      allowsSignup: false
  authorizationStrategy:
    roleBased:
      roles:
        global:
          - name: admin
            permissions:
              - 'Overall/Administer'
            entries:
              - user: admin
          - name: developer
            permissions:
              - 'Overall/Read'
              - 'Job/Build'
              - 'Job/Read'
              - 'Job/Cancel'

  clouds:
    - kubernetes:
        name: kubernetes
        namespace: jenkins
        jenkinsUrl: http://jenkins:8080
        containerCapStr: '20'
        templates:
          - name: jdk21
            label: jdk21
            containers:
              - name: jnlp
                image: eclipse-temurin:21-jdk
                workingDir: /home/jenkins/agent
                resourceRequestCpu: '500m'
                resourceRequestMemory: '1Gi'
                resourceLimitCpu: '2'
                resourceLimitMemory: '4Gi'

unclassified:
  globalLibraries:
    libraries:
      - name: my-org-shared-library
        defaultVersion: v2
        retriever:
          modernSCM:
            scm:
              git:
                remote: https://github.com/my-org/jenkins-shared-library.git
                credentialsId: github-token
```

JCasC makes Jenkins configuration reproducible and version-controlled. The controller is stateless — rebuild it from the YAML file at any time. Store `jenkins.yaml` in a dedicated configuration repository and apply it during Jenkins deployment.

### Production

**Production Jenkins deployment on Kubernetes** — use the official Helm chart with JCasC:
```bash
helm repo add jenkins https://charts.jenkins.io
helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --set controller.JCasC.configScripts.main="$(cat jenkins.yaml)" \
  --set controller.installPlugins[0]=kubernetes:4000 \
  --set controller.installPlugins[1]=workflow-aggregator:600 \
  --set controller.installPlugins[2]=configuration-as-code:1900 \
  --set controller.installPlugins[3]=git:5.6 \
  --set persistence.size=50Gi \
  --set controller.resources.requests.cpu=2 \
  --set controller.resources.requests.memory=4Gi
```

**Agent pod templates for production:**
```yaml
clouds:
  - kubernetes:
      templates:
        - name: gradle-builder
          label: gradle
          nodeUsageMode: EXCLUSIVE
          containers:
            - name: gradle
              image: gradle:8.12-jdk21
              command: sleep
              args: infinity
              workingDir: /home/jenkins/agent
              resourceRequestCpu: '1'
              resourceRequestMemory: '4Gi'
              resourceLimitCpu: '4'
              resourceLimitMemory: '8Gi'
            - name: docker
              image: docker:27-dind
              privileged: true
              resourceRequestCpu: '500m'
              resourceRequestMemory: '1Gi'
          volumes:
            - emptyDirVolume:
                mountPath: /var/run/docker.sock
                memory: false
          podRetention: onFailure
```

The `podRetention: onFailure` keeps failed agent pods for debugging (inspect logs, exec into the container) while cleaning up successful ones immediately. Use `EXCLUSIVE` node usage mode to prevent the pod from running arbitrary jobs — only jobs explicitly requesting the `gradle` label use this template.

## Performance

**Kubernetes dynamic agents** scale Jenkins horizontally. Instead of maintaining a pool of idle agents, Jenkins creates agent pods on-demand and destroys them after the build completes. This provides virtually unlimited concurrency while paying only for actual compute usage.

**Build caching** — Jenkins does not provide built-in caching like GitHub Actions or GitLab CI. Implement caching through workspace persistence (for non-ephemeral agents), shared NFS volumes, or build tool-specific remote caches (Gradle remote build cache, npm registry cache):
```groovy
stage('Build') {
    steps {
        sh '''
            mkdir -p $HOME/.gradle/caches
            ./gradlew build --no-daemon --build-cache \
                -Dorg.gradle.caching=true \
                -DbuildCacheUrl=https://cache.example.com/cache/
        '''
    }
}
```

**Pipeline durability settings** — for performance-sensitive pipelines, reduce durability to avoid synchronous disk writes:
```groovy
pipeline {
    options {
        durabilityHint('PERFORMANCE_OPTIMIZED')
    }
}
```

`PERFORMANCE_OPTIMIZED` reduces checkpoint frequency, making pipelines faster but less resilient to controller crashes. Use for short-lived PR builds; use `MAX_SURVIVABILITY` (default) for production deployment pipelines.

**Parallel stages** execute independent work concurrently:
```groovy
stage('Test') {
    parallel {
        stage('Unit Tests') {
            steps { sh './gradlew test' }
        }
        stage('Integration Tests') {
            agent { label 'docker' }
            steps { sh './gradlew integrationTest' }
        }
        stage('E2E Tests') {
            agent { label 'browser' }
            steps { sh 'npm run test:e2e' }
        }
    }
}
```

Each parallel stage can use a different agent, distributing load across the cluster.

**Workspace cleanup** prevents disk exhaustion on persistent agents:
```groovy
post {
    cleanup {
        cleanWs(
            cleanWhenNotBuilt: false,
            deleteDirs: true,
            disableDeferredWipeout: false,
            notFailBuild: true,
            patterns: [[pattern: '.gradle/**', type: 'EXCLUDE']]
        )
    }
}
```

The `patterns` option preserves the Gradle cache directory while cleaning everything else — balancing disk space with build speed.

## Security

**Credentials management** — Jenkins provides a centralized credential store that injects secrets into pipelines without exposing them in configuration or logs. Credentials support multiple types: username/password, SSH keys, secret files, secret text, and certificates:
```groovy
stage('Deploy') {
    steps {
        withCredentials([
            usernamePassword(
                credentialsId: 'docker-registry',
                usernameVariable: 'DOCKER_USER',
                passwordVariable: 'DOCKER_PASS'
            ),
            file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG'),
            string(credentialsId: 'slack-webhook', variable: 'SLACK_URL')
        ]) {
            sh '''
                docker login -u $DOCKER_USER -p $DOCKER_PASS registry.example.com
                kubectl apply -f k8s/
            '''
        }
    }
}
```

The `withCredentials` block injects secrets as environment variables scoped to the block — they are automatically masked in console output. Credentials are stored encrypted on the Jenkins controller and never written to build logs.

**Script approval** — Jenkins sandboxes Groovy scripts in pipelines. Any method call not in the sandbox whitelist requires admin approval via the script approval UI. This prevents pipeline authors from executing arbitrary code on the controller:
```groovy
// This requires script approval if not in the sandbox whitelist
@NonCPS
def parseJson(String text) {
    new groovy.json.JsonSlurper().parseText(text)
}
```

Prefer declarative pipeline steps over scripted Groovy to minimize the script approval surface. When scripted blocks are necessary, review and approve them carefully — a malicious `@NonCPS` method runs outside the sandbox with full Jenkins permissions.

**RBAC with the Role-Based Authorization Strategy plugin:**
```yaml
authorizationStrategy:
  roleBased:
    roles:
      global:
        - name: admin
          permissions: ['Overall/Administer']
        - name: developer
          permissions: ['Overall/Read', 'Job/Build', 'Job/Read', 'Job/Cancel']
        - name: viewer
          permissions: ['Overall/Read', 'Job/Read']
      items:
        - name: deploy-prod
          pattern: '.*-deploy-prod'
          permissions: ['Job/Build', 'Job/Read']
```

**Agent security** — never run builds on the Jenkins controller. Set "Number of executors" to 0 on the controller and use dedicated agent nodes. Controller builds have access to Jenkins internal files, credentials, and configuration:
```yaml
jenkins:
  numExecutors: 0
```

**Security checklist:**
- Set controller executors to 0 — all builds on agents only.
- Use credentials plugin for all secrets — never hardcode in Jenkinsfile.
- Enable CSRF protection and agent-to-controller security.
- Use RBAC to restrict job creation, build triggers, and deployment approvals.
- Pin shared library versions to tags, not branches.
- Review script approvals regularly — remove unused approvals.
- Keep Jenkins and plugins updated — subscribe to security advisories.
- Use HTTPS for the Jenkins UI and agent communication.

## Testing

**Validating Jenkinsfile syntax:**
```bash
# Using the Jenkins CLI
java -jar jenkins-cli.jar -s http://jenkins:8080 -auth user:token \
  declarative-linter < Jenkinsfile

# Using the HTTP API
curl -X POST -F "jenkinsfile=<Jenkinsfile" \
  http://jenkins:8080/pipeline-model-converter/validate
```

**Testing shared libraries with JenkinsPipelineUnit:**
```groovy
// test/groovy/GradleBuildTest.groovy
import com.lesfurets.jenkins.unit.BasePipelineTest
import org.junit.Before
import org.junit.Test

class GradleBuildTest extends BasePipelineTest {
    @Override
    @Before
    void setUp() {
        super.setUp()
        helper.registerAllowedMethod('junit', [String], null)
        helper.registerAllowedMethod('archiveArtifacts', [Map], null)
        helper.registerAllowedMethod('cleanWs', [], null)
    }

    @Test
    void 'gradleBuild executes build command'() {
        def script = loadScript('vars/gradleBuild.groovy')
        script.call(javaVersion: '21')

        printCallStack()
        assertJobStatusSuccess()
    }

    @Test
    void 'gradleBuild uses custom build command'() {
        def script = loadScript('vars/gradleBuild.groovy')
        script.call(buildCommand: './gradlew check --no-daemon')

        assertCallStackContains('./gradlew check --no-daemon')
    }
}
```

JenkinsPipelineUnit mocks the Jenkins runtime, allowing unit tests for shared library functions without a running Jenkins instance. Register mocks for pipeline steps (`junit`, `archiveArtifacts`, `withCredentials`) and assert on the call stack.

**Integration testing shared libraries** — create a test pipeline in Jenkins that exercises the library:
```groovy
@Library('my-org-shared-library@PR-42') _

// Test with minimal config
gradleBuild(javaVersion: '21')
```

Use the `@Library('name@PR-42')` syntax to test library changes from a pull request branch before merging.

## Dos

- Use declarative pipeline syntax (`pipeline {}`) for all new pipelines. It provides structure, validation, and restart capabilities that scripted pipelines lack. Reserve `script {}` blocks for escape hatches that declarative syntax cannot express.
- Use shared libraries for organization-wide pipeline logic. Store them in a dedicated Git repository, version with tags, and configure them globally in Jenkins. This eliminates Jenkinsfile duplication across services.
- Use `withCredentials` for all secret access. Credentials are encrypted at rest, masked in logs, and scoped to the block. Never pass secrets through environment variables set outside `withCredentials`.
- Set `numExecutors: 0` on the Jenkins controller. Run all builds on dedicated agents. Controller builds have access to Jenkins internals and are a security risk.
- Use `disableConcurrentBuilds(abortPrevious: true)` to cancel outdated builds. Without it, pushing multiple commits queues up builds that waste agent time on superseded code.
- Use Jenkins Configuration as Code (JCasC) to make the controller reproducible. Store `jenkins.yaml` in version control. A controller should be rebuildable from configuration alone.
- Use Kubernetes dynamic agents for horizontal scaling. Agent pods are created on-demand and destroyed after the build, providing unlimited concurrency without idle resource costs.
- Use `timeout(time: 30, unit: 'MINUTES')` on every pipeline. Stuck builds without timeouts consume agent resources indefinitely.
- Use multibranch pipeline organization folders to automatically discover repositories and branches. Manual job creation does not scale beyond a handful of services.

## Don'ts

- Don't use scripted pipeline syntax (`node {}`) for new pipelines. Scripted pipelines lack the structure, validation, and built-in features (parallel stages, post conditions, when directives) of declarative pipelines. They are harder to read, harder to maintain, and not supported by Blue Ocean's visual editor.
- Don't run builds on the Jenkins controller. The controller has access to all credentials, configuration, and internal state. A compromised build step could extract secrets, modify configurations, or install backdoors.
- Don't store credentials in Jenkinsfile, environment variables, or job configuration. Use the Jenkins Credentials Plugin with `withCredentials` to inject secrets at build time with automatic log masking.
- Don't use `@Library('name@main')` in production Jenkinsfiles. Branch references receive changes immediately, which can break consumer pipelines. Pin to tags (`@v2.1`) for stability and predictability.
- Don't ignore script approval requests. Each approval grants the approved code full access to the Jenkins runtime. Review the exact method call, understand what it does, and deny unnecessary approvals. Remove stale approvals periodically.
- Don't use `durabilityHint('PERFORMANCE_OPTIMIZED')` on deployment pipelines. Reduced checkpointing means a controller crash can leave deployments in an inconsistent state. Reserve performance optimization for short-lived, non-critical builds.
- Don't skip workspace cleanup. Without `cleanWs()` in the `post.cleanup` block, workspace directories accumulate on persistent agents, eventually filling disks and causing build failures.
- Don't use the classic Jenkins UI for pipeline creation. Define pipelines in `Jenkinsfile` committed to version control. UI-configured pipelines are not reproducible, not reviewable, and not auditable.
- Don't install plugins without verifying compatibility. Jenkins plugin version conflicts cause controller crashes and pipeline failures. Use the Plugin Installation Manager CLI to manage plugin versions declaratively.
