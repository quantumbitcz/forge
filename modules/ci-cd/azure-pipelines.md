# Azure Pipelines

## Overview

CI/CD service within Azure DevOps using YAML pipelines (`azure-pipelines.yml`) with stages, jobs, and steps. Runs on Microsoft-hosted (Ubuntu/macOS/Windows) or self-hosted agents with deep Azure ecosystem integration.

- **Use for:** Azure-invested orgs (AD, Key Vault, AKS), multi-platform builds with MS toolchains (.NET, VS Build Tools), enterprise compliance with template-enforced standards across repos
- **Avoid for:** GitHub-hosted OSS (GitHub Actions has better contributor UX), orgs with no Azure footprint, Kubernetes-native CI/CD (use Tekton)
- **Key differentiators:** `extends:` templates enforce org-wide pipeline standards projects cannot bypass; multi-stage YAML models full delivery lifecycle with environment approvals; Variable Groups + Key Vault for centralized secret management; native deployment strategies (rolling, canary) via Environments

## Architecture Patterns

### Multi-Stage Pipelines

Multi-stage pipelines define the complete delivery lifecycle in a single YAML file. Stages execute sequentially by default; jobs within a stage execute in parallel by default. Each stage can target a different environment with its own approval gates, variable groups, and deployment strategies.

**Complete multi-stage pipeline (`azure-pipelines.yml`):**
```yaml
trigger:
  branches:
    include:
      - main
  paths:
    exclude:
      - '**/*.md'
      - docs/

pr:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

variables:
  - group: shared-build-vars
  - name: imageRepository
    value: 'my-app'
  - name: dockerRegistryServiceConnection
    value: 'acr-connection'

stages:
  - stage: Build
    displayName: 'Build and Test'
    jobs:
      - job: BuildJob
        steps:
          - task: JavaToolInstaller@0
            inputs:
              versionSpec: '21'
              jdkArchitectureOption: 'x64'
              jdkSourceOption: 'PreInstalled'

          - task: Gradle@3
            inputs:
              gradleWrapperFile: 'gradlew'
              tasks: 'build'
              publishJUnitResults: true
              testResultsFiles: '**/build/test-results/test/TEST-*.xml'
              javaHomeOption: 'JDKVersion'
              jdkVersionOption: '1.21'

          - task: PublishBuildArtifacts@1
            inputs:
              pathToPublish: 'build/libs'
              artifactName: 'build-output'

  - stage: Package
    displayName: 'Build Docker Image'
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - job: DockerBuild
        steps:
          - task: Docker@2
            inputs:
              containerRegistry: $(dockerRegistryServiceConnection)
              repository: $(imageRepository)
              command: buildAndPush
              Dockerfile: 'Dockerfile'
              tags: |
                $(Build.BuildId)
                latest

  - stage: DeployStaging
    displayName: 'Deploy to Staging'
    dependsOn: Package
    jobs:
      - deployment: DeployToStaging
        environment: staging
        strategy:
          runOnce:
            deploy:
              steps:
                - task: KubernetesManifest@1
                  inputs:
                    action: deploy
                    kubernetesServiceConnection: 'aks-staging'
                    namespace: 'my-app'
                    manifests: 'k8s/staging/*.yml'
                    containers: |
                      $(containerRegistry)/$(imageRepository):$(Build.BuildId)

  - stage: DeployProduction
    displayName: 'Deploy to Production'
    dependsOn: DeployStaging
    jobs:
      - deployment: DeployToProduction
        environment: production
        strategy:
          runOnce:
            deploy:
              steps:
                - task: KubernetesManifest@1
                  inputs:
                    action: deploy
                    kubernetesServiceConnection: 'aks-production'
                    namespace: 'my-app'
                    manifests: 'k8s/production/*.yml'
                    containers: |
                      $(containerRegistry)/$(imageRepository):$(Build.BuildId)
```

The `condition:` on the Package stage prevents Docker builds on PR pipelines. The `deployment:` job type (instead of `job:`) integrates with Azure Environments for approval gates, deployment history, and health checks. The `strategy:` block defines how the deployment executes — `runOnce` for simple deployments, `rolling` for zero-downtime updates, or `canary` for percentage-based rollouts.

### Templates (Extends and Includes)

Azure Pipelines templates are the most powerful compliance mechanism in CI/CD. The `extends:` template wraps the consuming pipeline, inserting required stages/jobs/steps that the consumer cannot remove. This enforces organizational requirements (security scanning, compliance checks, artifact signing) regardless of what the project team configures.

**Organization template (`templates/required-pipeline.yml`):**
```yaml
parameters:
  - name: buildStages
    type: stageList
    default: []

stages:
  - stage: SecurityScan
    displayName: 'Required Security Scan'
    jobs:
      - job: SAST
        steps:
          - task: CredScan@3
            inputs:
              toolVersion: Latest
          - task: SdtReport@2
            inputs:
              GdnExportSarifFile: true

  - ${{ each stage in parameters.buildStages }}:
      - ${{ stage }}

  - stage: ComplianceGate
    displayName: 'Required Compliance Gate'
    dependsOn:
      - ${{ each stage in parameters.buildStages }}:
          - ${{ stage.stage }}
    jobs:
      - job: Compliance
        steps:
          - script: echo "Compliance checks passed"
```

**Service pipeline extending the template:**
```yaml
extends:
  template: templates/required-pipeline.yml@org-templates
  parameters:
    buildStages:
      - stage: Build
        jobs:
          - job: BuildApp
            pool:
              vmImage: 'ubuntu-latest'
            steps:
              - task: Gradle@3
                inputs:
                  tasks: 'build'
              - task: PublishTestResults@2
                inputs:
                  testResultsFormat: JUnit
                  testResultsFiles: '**/TEST-*.xml'

resources:
  repositories:
    - repository: org-templates
      type: git
      name: MyOrg/pipeline-templates
      ref: refs/tags/v2.0
```

The `extends:` keyword forces the consuming pipeline to inherit the template structure. The security scan stage runs before the project's build stages; the compliance gate runs after. The project team cannot skip or remove these stages — they can only provide their own stages via the `buildStages` parameter.

**Step-level templates for reusable build logic:**
```yaml
# templates/steps/gradle-build.yml
parameters:
  - name: javaVersion
    type: string
    default: '21'
  - name: gradleTasks
    type: string
    default: 'build'

steps:
  - task: JavaToolInstaller@0
    inputs:
      versionSpec: ${{ parameters.javaVersion }}
      jdkArchitectureOption: x64
      jdkSourceOption: PreInstalled

  - task: Cache@2
    inputs:
      key: 'gradle | "$(Agent.OS)" | **/gradle-wrapper.properties, **/libs.versions.toml'
      restoreKeys: |
        gradle | "$(Agent.OS)"
      path: $(GRADLE_USER_HOME)/caches

  - task: Gradle@3
    inputs:
      gradleWrapperFile: 'gradlew'
      tasks: ${{ parameters.gradleTasks }}
      publishJUnitResults: true
      testResultsFiles: '**/TEST-*.xml'
```

**Using the step template:**
```yaml
jobs:
  - job: Build
    steps:
      - template: templates/steps/gradle-build.yml
        parameters:
          javaVersion: '21'
          gradleTasks: 'build --parallel'
```

Templates resolve at compile time (before the pipeline runs), so template expressions (`${{ }}`) are evaluated during YAML processing, not at runtime. This distinction matters: template expressions can generate YAML structure (stages, jobs), while runtime expressions (`$()` or `$[variables]`) can only provide values.

### Variable Groups with Key Vault

Variable groups centralize configuration and secrets across pipelines. When linked to Azure Key Vault, secrets are fetched at pipeline runtime — they are never stored in Azure DevOps. Key Vault integration supports automatic rotation: update the secret in Key Vault and all pipelines pick up the new value on the next run.

**Variable group configuration (defined in Azure DevOps UI or via CLI):**
```bash
# Create variable group linked to Key Vault
az pipelines variable-group create \
  --name 'production-secrets' \
  --authorize true \
  --variables "[]" \
  --organization https://dev.azure.com/my-org \
  --project MyProject

# Link to Key Vault
az pipelines variable-group variable create \
  --group-id 1 \
  --name 'database-password' \
  --value '' \
  --secret true
```

**Using variable groups in pipelines:**
```yaml
variables:
  - group: shared-build-config
  - group: staging-secrets
  - name: localVar
    value: 'some-value'

stages:
  - stage: Deploy
    variables:
      - group: production-secrets
    jobs:
      - deployment: DeployProd
        environment: production
        strategy:
          runOnce:
            deploy:
              steps:
                - script: |
                    echo "Deploying with Key Vault secrets"
                    # $(database-password) is fetched from Key Vault at runtime
```

Variable groups can be restricted to specific pipelines and environments. Combined with Key Vault access policies, this provides defense-in-depth: the Azure DevOps variable group authorization controls which pipelines can request the secrets, and Key Vault access policies control which managed identities can read them.

### Environments with Approvals

Azure Pipelines Environments represent deployment targets (staging, production, QA) with associated approval gates, health checks, and deployment history. Environments are defined in Azure DevOps and referenced in pipeline YAML. They provide a complete audit trail of what was deployed, when, by whom, and what the approval chain looked like.

**Environment with approval gates and checks:**
```yaml
# Environment 'production' configured in Azure DevOps with:
# - Required approvers: lead-dev, ops-team
# - Business hours check: Mon-Fri 9am-5pm
# - Exclusive lock: only one deployment at a time

stages:
  - stage: DeployProduction
    jobs:
      - deployment: Production
        environment: production
        strategy:
          rolling:
            maxParallel: 25%
            deploy:
              steps:
                - task: KubernetesManifest@1
                  inputs:
                    action: deploy
                    kubernetesServiceConnection: 'aks-prod'
                    namespace: production
                    manifests: 'k8s/production/*.yml'
                    strategy: rolling
            routeTraffic:
              steps:
                - script: echo "Routing traffic to new pods"
            postRouteTraffic:
              steps:
                - task: AzureMonitor@1
                  inputs:
                    monitorId: 'health-check-rule'
                    waitForCompletion: true
            on:
              failure:
                steps:
                  - task: KubernetesManifest@1
                    inputs:
                      action: reject
                      kubernetesServiceConnection: 'aks-prod'
                      namespace: production
              success:
                steps:
                  - task: KubernetesManifest@1
                    inputs:
                      action: promote
                      kubernetesServiceConnection: 'aks-prod'
                      namespace: production
```

The `rolling` strategy deploys to 25% of pods at a time. After routing traffic, the `postRouteTraffic` step runs health checks. On failure, the deployment rolls back automatically. On success, the new version is promoted. The environment's approval gates pause the pipeline before the deployment starts, requiring authorized users to approve.

### Service Connections

Service connections abstract authentication to external services (Azure, AWS, Kubernetes, Docker registries) into reusable, auditable objects. They are created in Azure DevOps project settings and referenced by name in pipeline YAML. Service connections support managed identity, service principal, OIDC (workload identity federation), and token-based authentication.

**Service connection types and usage:**
```yaml
resources:
  containers:
    - container: build
      image: my-acr.azurecr.io/build-tools:latest
      endpoint: acr-connection

steps:
  # Azure Resource Manager connection (service principal or managed identity)
  - task: AzureCLI@2
    inputs:
      azureSubscription: 'azure-production'
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: |
        az aks get-credentials --resource-group rg-prod --name aks-prod
        kubectl apply -f k8s/

  # Kubernetes service connection
  - task: KubernetesManifest@1
    inputs:
      kubernetesServiceConnection: 'aks-production'
      action: deploy
      manifests: 'k8s/*.yml'

  # Docker registry connection
  - task: Docker@2
    inputs:
      containerRegistry: 'acr-connection'
      command: buildAndPush
      repository: my-app
      tags: $(Build.BuildId)
```

Service connections with workload identity federation (OIDC) are preferred over service principals with secrets — they eliminate the need for secret rotation and reduce the blast radius of credential compromise.

## Configuration

### Development

**Development-focused pipeline with caching and PR validation:**
```yaml
trigger: none

pr:
  branches:
    include:
      - main
  paths:
    exclude:
      - '**/*.md'

pool:
  vmImage: 'ubuntu-latest'

variables:
  GRADLE_USER_HOME: $(Pipeline.Workspace)/.gradle

steps:
  - task: JavaToolInstaller@0
    inputs:
      versionSpec: '21'
      jdkArchitectureOption: x64
      jdkSourceOption: PreInstalled

  - task: Cache@2
    displayName: 'Cache Gradle dependencies'
    inputs:
      key: 'gradle | "$(Agent.OS)" | **/gradle-wrapper.properties, **/libs.versions.toml'
      restoreKeys: |
        gradle | "$(Agent.OS)"
      path: $(GRADLE_USER_HOME)/caches

  - task: Gradle@3
    displayName: 'Build and test'
    inputs:
      gradleWrapperFile: 'gradlew'
      tasks: 'build'
      options: '--no-daemon --parallel --warning-mode=all'
      publishJUnitResults: true
      testResultsFiles: '**/TEST-*.xml'
      javaHomeOption: 'JDKVersion'
      jdkVersionOption: '1.21'

  - task: PublishCodeCoverageResults@2
    inputs:
      summaryFileLocation: '**/build/reports/jacoco/test/jacocoTestReport.xml'
```

The `trigger: none` with `pr:` block runs the pipeline only on pull requests — not on every push to the default branch. This saves pipeline minutes during development while providing merge-blocking CI feedback.

### Production

**Production pipeline with templates and environments:**
```yaml
trigger:
  branches:
    include:
      - main
  tags:
    include:
      - 'v*'

resources:
  repositories:
    - repository: templates
      type: git
      name: MyOrg/pipeline-templates
      ref: refs/tags/v2.0

extends:
  template: templates/standard-pipeline.yml@templates
  parameters:
    javaVersion: '21'
    buildTasks: 'build --parallel'
    dockerImage: 'my-app'
    environments:
      - name: staging
        serviceConnection: 'aks-staging'
      - name: production
        serviceConnection: 'aks-production'
        requireApproval: true
```

## Performance

**Caching** with the `Cache@2` task persists dependency downloads between runs:
```yaml
- task: Cache@2
  inputs:
    key: 'gradle | "$(Agent.OS)" | **/gradle-wrapper.properties, **/libs.versions.toml'
    restoreKeys: |
      gradle | "$(Agent.OS)"
    path: $(GRADLE_USER_HOME)/caches
```

The cache key is a hash of the specified files — any dependency change creates a new cache entry. The `restoreKeys` provide fallback for partial cache hits.

**Parallel jobs** split work across multiple agents:
```yaml
jobs:
  - job: UnitTests
    pool:
      vmImage: 'ubuntu-latest'
    steps:
      - script: ./gradlew test --no-daemon

  - job: IntegrationTests
    pool:
      vmImage: 'ubuntu-latest'
    steps:
      - script: ./gradlew integrationTest --no-daemon

  - job: LintAndAnalysis
    pool:
      vmImage: 'ubuntu-latest'
    steps:
      - script: ./gradlew detekt --no-daemon
```

Jobs within a stage run in parallel by default. Use `dependsOn:` to create sequential dependencies when needed.

**Pipeline artifacts** pass build outputs between stages without rebuilding:
```yaml
- task: PublishPipelineArtifact@1
  inputs:
    targetPath: 'build/libs'
    artifactName: 'app-jar'

# In downstream stage:
- task: DownloadPipelineArtifact@2
  inputs:
    artifactName: 'app-jar'
    targetPath: '$(Pipeline.Workspace)/app'
```

**Self-hosted agent pools** for persistent caches and specialized hardware. Use scale set agents (VMSS) for auto-scaling based on pipeline demand.

**Conditional stage execution** prevents unnecessary work:
```yaml
- stage: Deploy
  condition: and(succeeded(), startsWith(variables['Build.SourceBranch'], 'refs/tags/v'))
```

## Security

**Service connections with workload identity federation** — use OIDC instead of service principal secrets:
```bash
az ad app federated-credential create \
  --id <app-id> \
  --parameters '{
    "name": "azure-pipelines-prod",
    "issuer": "https://vstoken.dev.azure.com/<org-id>",
    "subject": "sc://my-org/my-project/production-connection",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**Variable group security** — mark sensitive variables as secret. Secret variables are encrypted at rest and masked in logs. Link variable groups to Key Vault for automatic rotation.

**Environment approvals** — configure required approvers, business hours checks, and exclusive locks on environments. This prevents accidental deployments and provides an audit trail.

**Branch protection** — restrict which branches can trigger deployment stages using conditions:
```yaml
- stage: DeployProduction
  condition: and(succeeded(), startsWith(variables['Build.SourceBranch'], 'refs/tags/'))
```

**Security checklist:**
- Use service connections with workload identity federation (OIDC) instead of service principal secrets.
- Link variable groups to Azure Key Vault for centralized secret management with automatic rotation.
- Configure environment approvals with required reviewers for production deployments.
- Use `extends:` templates from a central repository to enforce security scanning.
- Restrict pipeline permissions: limit who can edit pipelines, create service connections, and approve deployments.
- Enable audit logging in Azure DevOps for compliance tracking.
- Use managed identities for self-hosted agents instead of personal credentials.
- Pin template references to tags, not branches.

## Testing

**Validating pipeline YAML:**
```bash
# Using Azure DevOps REST API
az pipelines run --name my-pipeline --branch main --preview

# Using the Azure DevOps CLI
az pipelines show --name my-pipeline --query 'configuration'
```

**Testing templates in isolation** — create a test pipeline that exercises the template with various parameter combinations:
```yaml
# test-pipeline.yml
trigger: none

resources:
  repositories:
    - repository: templates
      type: git
      name: MyOrg/pipeline-templates
      ref: refs/heads/feature/template-update

extends:
  template: templates/standard-pipeline.yml@templates
  parameters:
    javaVersion: '21'
    buildTasks: 'assemble'
```

**Testing variable group access** — verify that pipelines can read variable groups and that Key Vault integration works:
```yaml
- stage: VerifySecrets
  jobs:
    - job: CheckAccess
      variables:
        - group: test-secrets
      steps:
        - script: |
            if [ -z "$(test-secret)" ]; then
              echo "ERROR: Secret not available"
              exit 1
            fi
            echo "Secret access verified"
```

## Dos

- Use `extends:` templates from a central repository to enforce organizational standards. Projects that extend the template cannot remove required stages (security scanning, compliance checks). This is the most powerful compliance mechanism in CI/CD.
- Use variable groups linked to Azure Key Vault for all secrets. Secrets are fetched at runtime, automatically rotated, and never stored in Azure DevOps. Key Vault access policies provide an additional authorization layer.
- Use environments with approval gates for production deployments. Configure required reviewers, business hours checks, and exclusive locks. The environment provides a complete deployment audit trail.
- Use service connections with workload identity federation (OIDC) instead of service principal secrets. OIDC eliminates the need for secret rotation and reduces blast radius.
- Use the `Cache@2` task with hash-based keys for dependency caching. Include dependency manifest files in the key to automatically invalidate when dependencies change.
- Use `condition:` expressions to skip stages on PR pipelines. Build and test stages should run on every PR; packaging and deployment stages should only run on the default branch or tags.
- Use pipeline artifacts (`PublishPipelineArtifact` / `DownloadPipelineArtifact`) to share outputs between stages without rebuilding.
- Use `template:` references pinned to tags for stable, versioned pipeline templates.
- Use `trigger: paths:` to skip pipelines when only documentation or non-code files change.

## Don'ts

- Don't use the classic (GUI) editor for new pipelines. YAML pipelines are version-controlled, reviewable, and portable. Classic pipelines are opaque, tied to the Azure DevOps UI, and difficult to audit.
- Don't store secrets as plain pipeline variables. Use variable groups linked to Key Vault or mark variables as secret. Plain variables are visible in pipeline logs and API responses.
- Don't use `extends:` template references pinned to branches (`ref: refs/heads/main`). Branch references receive changes immediately, which can break consuming pipelines. Pin to tags.
- Don't skip environment approvals for production deployments. Environments without approval gates allow any pipeline run to deploy to production — including accidental triggers from feature branches.
- Don't create service connections with broad permissions. Scope each connection to the minimum required: specific resource groups, specific clusters, specific registries. Avoid subscription-level Contributor roles.
- Don't use `dependsOn: []` (empty) to skip stage dependencies unless you understand the implications. An empty `dependsOn` makes the stage run immediately, potentially before prerequisite stages complete.
- Don't hardcode Azure subscription IDs, tenant IDs, or resource group names in pipeline YAML. Use variable groups or service connection configurations to keep infrastructure details out of source code.
- Don't ignore pipeline run previews. Use `az pipelines run --preview` to validate YAML changes before running.
- Don't use self-hosted agents without proper security hardening. Self-hosted agents persist between runs — ensure workspace cleanup, restrict network access, and use managed identities.
