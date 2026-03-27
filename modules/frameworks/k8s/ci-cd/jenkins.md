# Jenkins with Kubernetes

> Extends `modules/ci-cd/jenkins.md` with Kubernetes infrastructure pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'alpine/helm:latest' } }

    stages {
        stage('Validate') {
            steps {
                sh 'helm lint charts/*'
                sh 'helm template charts/* | kubectl apply --dry-run=client -f -'
            }
        }
        stage('Security Scan') {
            agent { docker { image 'aquasec/trivy:latest' } }
            steps {
                sh 'trivy config charts/ --exit-code 1 --severity HIGH,CRITICAL'
            }
        }
        stage('Build Image') {
            when { branch 'main' }
            steps {
                script {
                    def image = docker.build("${env.REGISTRY}/app:${env.BUILD_NUMBER}")
                    docker.withRegistry("https://${env.REGISTRY}", 'registry-creds') {
                        image.push()
                        image.push('latest')
                    }
                }
            }
        }
    }
}
```

## Framework-Specific Patterns

### Kubernetes Plugin for Jenkins

```groovy
// Jenkins running in Kubernetes can use dynamic pod agents
pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: helm
    image: alpine/helm:latest
    command: ['sleep', 'infinity']
  - name: trivy
    image: aquasec/trivy:latest
    command: ['sleep', 'infinity']
"""
        }
    }
    stages {
        stage('Validate') {
            steps {
                container('helm') {
                    sh 'helm lint charts/*'
                }
            }
        }
        stage('Scan') {
            steps {
                container('trivy') {
                    sh 'trivy config charts/ --exit-code 1 --severity HIGH,CRITICAL'
                }
            }
        }
    }
}
```

### Helm Deployment

```groovy
stage('Deploy') {
    when { branch 'main' }
    input {
        message 'Deploy to production?'
        ok 'Deploy'
    }
    steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
            sh """
                helm upgrade --install app charts/app \
                    --namespace production \
                    --set image.tag=${env.BUILD_NUMBER} \
                    --wait --timeout 300s
            """
        }
    }
}
```

### Shared Library for Infrastructure Pipelines

```groovy
// vars/helmPipeline.groovy
def call(Map config = [:]) {
    def chartPath = config.chartPath ?: 'charts/*'
    pipeline {
        agent { docker { image 'alpine/helm:latest' } }
        stages {
            stage('Lint') { steps { sh "helm lint ${chartPath}" } }
            stage('Template') { steps { sh "helm template ${chartPath} | kubectl apply --dry-run=client -f -" } }
        }
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "Jenkinsfile"
```

## Additional Dos

- DO use the Kubernetes plugin for dynamic pod agents when Jenkins runs in K8s
- DO use `input` step for manual production deployment approval
- DO use `withCredentials` for kubeconfig access -- never hardcode cluster credentials
- DO use the `alpine/helm` image for lightweight Helm operations

## Additional Don'ts

- DON'T store kubeconfig in the Jenkinsfile -- use Jenkins credentials store
- DON'T deploy to production without manual approval (`input` step)
- DON'T use `kubectl apply` without `--dry-run=client` in validation stages
- DON'T use `agent any` for infrastructure pipelines -- pin tool images
