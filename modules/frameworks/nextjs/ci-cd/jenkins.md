# Jenkins with Next.js

> Extends `modules/ci-cd/jenkins.md` with Next.js pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'node:22-slim' } }

    stages {
        stage('Install') { steps { sh 'npm ci' } }
        stage('Lint') { steps { sh 'npm run lint' } }
        stage('Build') { steps { sh 'npm run build' } }
        stage('Test') {
            steps { sh 'npm test' }
            post { always { junit 'junit.xml' } }
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
            def image = docker.build("${env.REGISTRY}/nextjs-app:${env.BUILD_NUMBER}")
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

- DO run `next build` to validate Server/Client component boundaries
- DO run `next lint` for framework-specific linting
- DO publish JUnit XML results
- DO use declarative pipelines

## Additional Don'ts

- DON'T skip the build step
- DON'T use `agent any` when builds need a specific Node.js version
- DON'T skip `post { always }` for test results
