# Jenkins with NestJS

> Extends `modules/ci-cd/jenkins.md` with NestJS pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'node:22-slim' } }

    stages {
        stage('Install') {
            steps { sh 'npm ci' }
        }
        stage('Lint') {
            steps { sh 'npm run lint' }
        }
        stage('Build') {
            steps { sh 'npm run build' }
        }
        stage('Test') {
            steps {
                sh 'npm test -- --coverage --reporters=default --reporters=jest-junit'
            }
            post {
                always { junit 'junit.xml' }
            }
        }
    }
}
```

## Framework-Specific Patterns

### Swagger Spec Generation

```groovy
stage('Generate OpenAPI') {
    steps {
        sh 'node dist/swagger-cli.js > openapi.json'
        archiveArtifacts artifacts: 'openapi.json'
    }
}
```

### Docker Image Publishing

```groovy
stage('Publish') {
    when { branch 'main' }
    steps {
        script {
            def image = docker.build("${env.REGISTRY}/nestjs-app:${env.BUILD_NUMBER}")
            docker.withRegistry("https://${env.REGISTRY}", 'registry-creds') {
                image.push()
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

- DO run `nest build` before tests to catch compilation errors early
- DO publish JUnit XML results for test trend tracking
- DO generate and archive OpenAPI specs as build artifacts
- DO use `npm ci` for deterministic installs

## Additional Don'ts

- DON'T skip the build stage -- NestJS requires compilation
- DON'T use `agent any` when builds need a specific Node.js version
- DON'T skip `post { always }` for test result collection
