# CircleCI with Kubernetes

> Extends `modules/ci-cd/circleci.md` with Kubernetes infrastructure CI/CD patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  kubernetes: circleci/kubernetes@1.3

jobs:
  validate:
    docker:
      - image: alpine/helm:latest
    steps:
      - checkout
      - run: helm lint charts/*
      - run: helm template charts/* | kubectl apply --dry-run=client -f -

  security-scan:
    docker:
      - image: aquasec/trivy:latest
    steps:
      - checkout
      - run: trivy config charts/ --exit-code 1 --severity HIGH,CRITICAL

workflows:
  ci:
    jobs:
      - validate
      - security-scan
```

## Framework-Specific Patterns

### Helm Deployment

```yaml
deploy:
  docker:
    - image: alpine/helm:latest
  steps:
    - checkout
    - kubernetes/install-kubeconfig:
        kubeconfig: KUBECONFIG_DATA
    - run:
        command: |
          helm upgrade --install my-app charts/my-app \
            --namespace production \
            --set image.tag=$CIRCLE_SHA1 \
            --values charts/my-app/values-production.yaml \
            --wait --timeout 300s
```

### Docker Image Build and Push

```yaml
build-image:
  docker:
    - image: cimg/base:current
  steps:
    - checkout
    - setup_remote_docker:
        docker_layer_caching: true
    - run:
        command: |
          docker build -t $REGISTRY/app:$CIRCLE_SHA1 .
          echo "$DOCKER_PASSWORD" | docker login $REGISTRY -u "$DOCKER_USERNAME" --password-stdin
          docker push $REGISTRY/app:$CIRCLE_SHA1
```

### Parallel Validation

```yaml
workflows:
  ci:
    jobs:
      - validate
      - security-scan
      - kube-lint:
          docker:
            - image: stackrox/kube-linter:latest
          steps:
            - checkout
            - run: kube-linter lint charts/
      - build-image:
          requires:
            - validate
            - security-scan
      - deploy:
          requires:
            - build-image
          filters:
            branches:
              only: main
```

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use the CircleCI Kubernetes orb for kubeconfig management
- DO run Helm lint, template validation, and security scanning in parallel
- DO use `docker_layer_caching` for faster image builds
- DO use branch filters to restrict production deployments to `main`

## Additional Don'ts

- DON'T store kubeconfig in the repository -- use CircleCI environment variables
- DON'T deploy to production without validation and security scanning
- DON'T use `latest` tag for production images -- use `$CIRCLE_SHA1`
- DON'T skip `--wait` in Helm deployments -- it masks deployment failures
