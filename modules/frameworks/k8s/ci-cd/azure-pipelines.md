# Azure Pipelines with Kubernetes

> Extends `modules/ci-cd/azure-pipelines.md` with Kubernetes infrastructure pipeline patterns.
> Generic Azure Pipelines conventions (stages, jobs, variable groups) are NOT repeated here.

## Integration Setup

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: ubuntu-latest

stages:
  - stage: Validate
    jobs:
      - job: LintAndValidate
        steps:
          - task: HelmInstaller@1
            inputs:
              helmVersionToInstall: latest
          - script: helm lint charts/*
          - script: helm template charts/* | kubectl apply --dry-run=client -f -

  - stage: SecurityScan
    jobs:
      - job: TrivyScan
        steps:
          - script: |
              curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
              trivy config charts/ --exit-code 1 --severity HIGH,CRITICAL
```

## Framework-Specific Patterns

### AKS Deployment

```yaml
- stage: Deploy
  dependsOn: Validate
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
    - deployment: DeployToAKS
      environment: production
      strategy:
        runOnce:
          deploy:
            steps:
              - task: KubernetesManifest@1
                inputs:
                  action: deploy
                  connectionType: azureResourceManager
                  azureSubscriptionConnection: $(azureSubscription)
                  azureResourceGroup: $(resourceGroup)
                  kubernetesCluster: $(aksCluster)
                  namespace: production
                  manifests: k8s/*.yaml

              - task: HelmDeploy@1
                inputs:
                  connectionType: Azure Resource Manager
                  azureSubscription: $(azureSubscription)
                  azureResourceGroup: $(resourceGroup)
                  kubernetesCluster: $(aksCluster)
                  command: upgrade
                  chartType: FilePath
                  chartPath: charts/my-app
                  releaseName: my-app
                  namespace: production
                  valueFile: charts/my-app/values-production.yaml
                  arguments: --wait --timeout 300s
```

### Azure Container Registry Build

```yaml
- task: Docker@2
  inputs:
    containerRegistry: $(acrConnection)
    repository: $(imageRepository)
    command: buildAndPush
    Dockerfile: Dockerfile
    tags: |
      $(Build.BuildId)
      $(Build.SourceVersion)
      latest
```

### Multi-Environment Pipeline

```yaml
- stage: DeployStaging
  jobs:
    - deployment: Staging
      environment: staging
      strategy:
        runOnce:
          deploy:
            steps:
              - task: HelmDeploy@1
                inputs:
                  command: upgrade
                  releaseName: my-app
                  namespace: staging
                  valueFile: charts/my-app/values-staging.yaml

- stage: DeployProduction
  dependsOn: DeployStaging
  jobs:
    - deployment: Production
      environment: production
      strategy:
        runOnce:
          deploy:
            steps:
              - task: HelmDeploy@1
                inputs:
                  command: upgrade
                  releaseName: my-app
                  namespace: production
                  valueFile: charts/my-app/values-production.yaml
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "azure-pipelines.yml"
```

## Additional Dos

- DO use `deployment` jobs with `environment` for approval gates
- DO use Azure Container Registry (ACR) for image storage
- DO use `HelmDeploy@1` task for Helm-based Kubernetes deployments
- DO use `--wait` in Helm deployments for deployment verification

## Additional Don'ts

- DON'T store kubeconfig or AKS credentials in pipeline YAML -- use service connections
- DON'T deploy to production without a staging gate
- DON'T use `latest` tag in production deployments -- use build-specific tags
- DON'T skip `helm lint` and `--dry-run` validation in the pipeline
