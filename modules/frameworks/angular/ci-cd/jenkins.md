# Jenkins with Angular

> Extends `modules/ci-cd/jenkins.md` with Angular CLI pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'node:22' } }

    stages {
        stage('Install') {
            steps {
                sh 'npm ci'
            }
        }
        stage('Validate') {
            parallel {
                stage('Lint') {
                    steps { sh 'npx ng lint' }
                }
                stage('Test') {
                    environment {
                        CHROME_BIN = '/usr/bin/chromium'
                    }
                    steps {
                        sh 'apt-get update && apt-get install -y chromium'
                        sh 'npx ng test --no-watch --browsers=ChromeHeadless'
                    }
                }
            }
        }
        stage('Build') {
            steps {
                sh 'npx ng build --configuration production'
            }
            post {
                success {
                    archiveArtifacts artifacts: 'dist/**', fingerprint: true
                }
            }
        }
    }
}
```

## Framework-Specific Patterns

### Docker Image Publishing

```groovy
stage('Publish') {
    when { branch 'main' }
    steps {
        script {
            def image = docker.build("${env.REGISTRY}/${env.JOB_NAME}:${env.BUILD_NUMBER}")
            docker.withRegistry("https://${env.REGISTRY}", 'registry-creds') {
                image.push()
                image.push('latest')
            }
        }
    }
}
```

### Shared Library for Angular Pipelines

```groovy
// vars/angularPipeline.groovy
def call(Map config = [:]) {
    def nodeVersion = config.nodeVersion ?: '22'
    pipeline {
        agent { docker { image "node:${nodeVersion}" } }
        stages {
            stage('Install') { steps { sh 'npm ci' } }
            stage('Lint') { steps { sh 'npx ng lint' } }
            stage('Build') { steps { sh 'npx ng build --configuration production' } }
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

- DO use `node:22` (not Alpine) for Karma test stages that need Chromium
- DO run lint and test in parallel stages when they are independent
- DO archive `dist/**` as build artifacts for downstream deployment
- DO use `--configuration production` for AOT compilation in CI

## Additional Don'ts

- DON'T use `node:22-alpine` when running browser-based tests -- Alpine lacks required libraries
- DON'T skip `post { success }` artifact archival -- deployment stages need the build output
- DON'T use `ng serve` in Jenkins -- build once, deploy the artifact
