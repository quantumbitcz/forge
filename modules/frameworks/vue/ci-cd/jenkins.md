# Jenkins with Vue / Nuxt

> Extends `modules/ci-cd/jenkins.md` with Vue 3 / Nuxt 3 pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'node:22-alpine' } }

    stages {
        stage('Install') {
            steps {
                sh 'npm ci'
            }
        }
        stage('Validate') {
            parallel {
                stage('Lint') {
                    steps { sh 'npm run lint' }
                }
                stage('Type Check') {
                    steps { sh 'npx nuxi typecheck' }
                }
                stage('Test') {
                    steps { sh 'npm run test' }
                }
            }
        }
        stage('Build') {
            steps {
                sh 'npm run build'
            }
            post {
                success {
                    archiveArtifacts artifacts: '.output/**', fingerprint: true
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

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "Jenkinsfile"
```

## Additional Dos

- DO run lint, type check, and test in parallel stages
- DO use `nuxi typecheck` for Nuxt-generated types
- DO archive `.output/**` for downstream deployment stages
- DO use `node:22-alpine` Docker agent for consistent builds

## Additional Don'ts

- DON'T use `agent any` for frontend builds -- pin the Node.js image
- DON'T skip the `post { success }` artifact archival
- DON'T use `nuxt dev` in Jenkins -- build and preview the production output
