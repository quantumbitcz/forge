# GitHub Actions with Kubernetes

> Extends `modules/ci-cd/github-actions.md` with Kubernetes infrastructure CI patterns.
> Generic GitHub Actions conventions (workflow triggers, caching strategies, matrix builds) are NOT repeated here.

## Integration Setup

```yaml
# .github/workflows/ci.yml
name: Infrastructure CI
on:
  push:
    branches: [main]
    paths:
      - 'charts/**'
      - 'deploy/**'
      - 'Dockerfile'
  pull_request:
    branches: [main]
    paths:
      - 'charts/**'
      - 'deploy/**'
      - 'Dockerfile'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Helm lint
        run: |
          helm lint charts/*

      - name: Template validation
        run: |
          helm template charts/* | kubectl apply --dry-run=client -f -

      - name: Trivy scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: charts/
          exit-code: 1
          severity: HIGH,CRITICAL
```

## Framework-Specific Patterns

### Helm Lint + Template Validation

```yaml
- name: Helm lint
  run: |
    for chart in charts/*/; do
      helm lint "$chart" --values "$chart/values.yaml"
    done

- name: Dry-run apply
  run: |
    for chart in charts/*/; do
      helm template "$chart" | kubectl apply --dry-run=client -f -
    done
```

`helm lint` catches chart structure issues. `kubectl apply --dry-run=client` validates the generated YAML against the Kubernetes API schema without a cluster.

### Policy Validation with Conftest

```yaml
- name: Install Conftest
  run: |
    wget -qO- https://github.com/open-policy-agent/conftest/releases/download/v0.55.0/conftest_0.55.0_Linux_x86_64.tar.gz | tar xz
    sudo mv conftest /usr/local/bin/

- name: Policy check
  run: |
    helm template charts/* | conftest test -p policy/ -
```

Conftest applies OPA/Rego policies to Helm output. Use it to enforce organizational standards (resource limits, security context, labels).

### Trivy Security Scan

```yaml
- name: Trivy config scan
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: config
    scan-ref: charts/
    exit-code: 1
    severity: HIGH,CRITICAL

- name: Trivy image scan
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: image
    image-ref: ghcr.io/${{ github.repository }}:${{ github.sha }}
    exit-code: 1
    severity: HIGH,CRITICAL
```

Run both config scanning (Helm charts, Dockerfiles) and image scanning (container vulnerabilities).

### Kubeconform Schema Validation

```yaml
- name: Install kubeconform
  run: |
    wget -qO- https://github.com/yannh/kubeconform/releases/download/v0.6.7/kubeconform-linux-amd64.tar.gz | tar xz
    sudo mv kubeconform /usr/local/bin/

- name: Validate manifests
  run: |
    helm template charts/* | kubeconform -strict -kubernetes-version 1.31.0
```

Kubeconform validates Kubernetes manifests against the OpenAPI schema. Use `-strict` to catch unknown fields.

### Docker Image Build and Push

```yaml
build-image:
  runs-on: ubuntu-latest
  if: github.ref == 'refs/heads/main'
  steps:
    - uses: actions/checkout@v6
    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    - uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: |
          ghcr.io/${{ github.repository }}:${{ github.sha }}
          ghcr.io/${{ github.repository }}:latest
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
  policy_dir: "policy/"
```

## Additional Dos

- DO run `helm lint`, `kubectl dry-run`, and `kubeconform` for comprehensive validation
- DO use Trivy for both config scanning (charts) and image scanning (containers)
- DO use Conftest with OPA policies for organizational standard enforcement
- DO restrict CI triggers to relevant paths (`charts/`, `deploy/`, `Dockerfile`)
- DO pin Kubernetes schema version in kubeconform to match your target cluster

## Additional Don'ts

- DON'T skip security scanning -- Trivy catches misconfigurations and CVEs
- DON'T use `kubectl apply` without `--dry-run=client` in CI -- it would modify the cluster
- DON'T assume `helm lint` catches all issues -- it only validates chart structure, not YAML semantics
- DON'T push images with mutable tags only (`latest`) -- always include an immutable tag (SHA)
