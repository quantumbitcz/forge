# Jenkins with FastAPI

> Extends `modules/ci-cd/jenkins.md` with FastAPI pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'python:3.12-slim' } }

    stages {
        stage('Install') {
            steps {
                sh 'pip install uv && uv sync'
            }
        }
        stage('Lint') {
            steps {
                sh 'uv run ruff check .'
            }
        }
        stage('Test') {
            steps {
                sh 'uv run pytest --junitxml=report.xml --cov=app'
            }
            post {
                always {
                    junit 'report.xml'
                }
            }
        }
    }
}
```

## Framework-Specific Patterns

### Database Service for Integration Tests

```groovy
stage('Integration Test') {
    agent {
        docker {
            image 'python:3.12-slim'
            args '--network=ci-network'
        }
    }
    environment {
        DATABASE_URL = 'postgresql://test:test@postgres:5432/test'
    }
    steps {
        sh 'pip install uv && uv sync'
        sh 'uv run alembic upgrade head'
        sh 'uv run pytest tests/integration/ --junitxml=integration-report.xml'
    }
    post {
        always {
            junit 'integration-report.xml'
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
            def image = docker.build("${env.REGISTRY}/fastapi-app:${env.BUILD_NUMBER}")
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

- DO publish JUnit XML results with `junit` post step for test trend tracking
- DO use `uv sync` for deterministic dependency installation
- DO run Alembic migrations before integration tests
- DO use declarative pipelines for consistency

## Additional Don'ts

- DON'T install dev dependencies in production Docker stages
- DON'T use `pip install -r requirements.txt` when uv lockfile is available
- DON'T skip `post { always }` for test result collection
