# Jenkins with React

> Extends `modules/ci-cd/jenkins.md` with React + Vite pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'oven/bun:latest' } }

    stages {
        stage('Install') {
            steps {
                sh 'bun install --frozen-lockfile'
            }
        }
        stage('Lint') {
            steps {
                sh 'bun run lint'
            }
        }
        stage('Test') {
            steps {
                sh 'bun run test'
            }
        }
        stage('Build') {
            steps {
                sh 'bun run build'
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

### Node.js Alternative

```groovy
pipeline {
    agent { docker { image 'node:22-alpine' } }

    stages {
        stage('Install') {
            steps {
                sh 'npm ci'
            }
        }
        stage('Build & Test') {
            parallel {
                stage('Lint') { steps { sh 'npm run lint' } }
                stage('Test') { steps { sh 'npm run test' } }
            }
        }
        stage('Build') {
            steps {
                sh 'npm run build'
            }
        }
    }
}
```

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

- DO use `oven/bun:latest` or `node:22-alpine` Docker agent for consistent builds
- DO run lint and test in parallel stages when they are independent
- DO archive `dist/**` as build artifacts for downstream deployment stages
- DO use `--frozen-lockfile` for deterministic dependency installs

## Additional Don'ts

- DON'T use `agent any` for frontend builds -- pin the runtime image for reproducibility
- DON'T skip the `post { success }` artifact archival -- downstream stages need the build output
- DON'T install global npm packages in the pipeline -- use `npx`/`bunx` for CLI tools
