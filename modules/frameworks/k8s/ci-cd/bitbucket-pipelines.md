# Bitbucket Pipelines with Kubernetes

> Extends `modules/ci-cd/bitbucket-pipelines.md` with Kubernetes infrastructure pipeline patterns.
> Generic Bitbucket Pipelines conventions (step definitions, caching, artifacts) are NOT repeated here.

## Integration Setup

```yaml
# bitbucket-pipelines.yml
image: alpine/helm:latest

definitions:
  caches:
    helm: ~/.cache/helm

pipelines:
  default:
    - step:
        name: Validate
        caches:
          - helm
        script:
          - helm lint charts/*
          - helm template charts/* | kubectl apply --dry-run=client -f -
    - step:
        name: Security Scan
        image: aquasec/trivy:latest
        script:
          - trivy config charts/ --exit-code 1 --severity HIGH,CRITICAL
```

## Framework-Specific Patterns

### Kubernetes Deployment

```yaml
pipelines:
  branches:
    main:
      - step:
          name: Build & Push Image
          services:
            - docker
          script:
            - docker build -t $REGISTRY/$IMAGE:$BITBUCKET_COMMIT .
            - docker push $REGISTRY/$IMAGE:$BITBUCKET_COMMIT

      - step:
          name: Deploy to Staging
          deployment: staging
          image: alpine/helm:latest
          script:
            - helm upgrade --install my-app charts/my-app
                --namespace staging
                --set image.tag=$BITBUCKET_COMMIT
                --values charts/my-app/values-staging.yaml
                --wait --timeout 300s

      - step:
          name: Deploy to Production
          deployment: production
          trigger: manual
          image: alpine/helm:latest
          script:
            - helm upgrade --install my-app charts/my-app
                --namespace production
                --set image.tag=$BITBUCKET_COMMIT
                --values charts/my-app/values-production.yaml
                --wait --timeout 300s
```

### Kubeconfig via Repository Variables

```yaml
script:
  - echo $KUBE_CONFIG | base64 -d > /tmp/kubeconfig
  - export KUBECONFIG=/tmp/kubeconfig
  - helm upgrade --install my-app charts/my-app
```

Store the base64-encoded kubeconfig as a secured repository variable. Decode it at runtime -- never commit kubeconfig files.

### Parallel Validation

```yaml
- parallel:
    - step:
        name: Helm Lint
        script:
          - helm lint charts/*
    - step:
        name: Trivy Scan
        image: aquasec/trivy:latest
        script:
          - trivy config charts/ --exit-code 1
    - step:
        name: KubeLinter
        image: stackrox/kube-linter:latest
        script:
          - kube-linter lint charts/
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "bitbucket-pipelines.yml"
```

## Additional Dos

- DO use `deployment` steps with named environments for promotion tracking
- DO use `trigger: manual` for production deployments
- DO use parallel steps for independent validation (lint, scan, kubeLinter)
- DO use `--wait` in Helm deployments for status verification

## Additional Don'ts

- DON'T commit kubeconfig files -- store as base64-encoded secured repository variables
- DON'T deploy to production automatically -- use manual trigger
- DON'T use `latest` tag in production deployments -- use `$BITBUCKET_COMMIT`
- DON'T skip validation steps -- Helm lint and security scanning prevent broken deployments
