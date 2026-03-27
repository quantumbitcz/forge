# GitLab CI with Kubernetes

> Extends `modules/ci-cd/gitlab-ci.md` with Kubernetes infrastructure CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - build
  - deploy

validate-charts:
  stage: validate
  image: alpine/helm:latest
  script:
    - helm lint charts/*
    - helm template charts/* | kubectl apply --dry-run=client -f -

security-scan:
  stage: validate
  image: aquasec/trivy:latest
  script:
    - trivy config charts/ --exit-code 1 --severity HIGH,CRITICAL

build-image:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

## Framework-Specific Patterns

### Policy Validation

```yaml
policy-check:
  stage: validate
  image: openpolicyagent/conftest:latest
  script:
    - helm template charts/* | conftest test -p policy/ -
```

### Kubeconform Validation

```yaml
schema-check:
  stage: validate
  image: ghcr.io/yannh/kubeconform:latest
  script:
    - helm template charts/* | kubeconform -strict -kubernetes-version 1.31.0
```

### Trivy Image Scan

```yaml
image-scan:
  stage: build
  image: aquasec/trivy:latest
  script:
    - trivy image $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA --exit-code 1 --severity HIGH,CRITICAL
  needs:
    - build-image
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

### GitLab Kubernetes Agent Deployment

```yaml
deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - kubectl config use-context $KUBE_CONTEXT
    - helm upgrade --install app charts/app
        --namespace production
        --set image.tag=$CI_COMMIT_SHA
        --wait --timeout 300s
  environment:
    name: production
    kubernetes:
      namespace: production
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  when: manual
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: ".gitlab-ci.yml"
```

## Additional Dos

- DO use `alpine/helm` image for lightweight Helm validation
- DO run Trivy for both config and image scanning
- DO use `when: manual` for production deployment gates
- DO use GitLab Kubernetes Agent for secure cluster access

## Additional Don'ts

- DON'T use `kubectl apply` without `--dry-run=client` in validation stages
- DON'T skip Trivy image scanning after build
- DON'T deploy automatically to production without manual approval
- DON'T store kubeconfig files in CI variables -- use GitLab Agent
