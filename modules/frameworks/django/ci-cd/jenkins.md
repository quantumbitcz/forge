# Jenkins with Django

> Extends `modules/ci-cd/jenkins.md` with Django pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'python:3.12-slim' } }

    environment {
        DJANGO_SETTINGS_MODULE = 'config.settings.test'
    }

    stages {
        stage('Install') {
            steps {
                sh 'pip install uv && uv sync'
            }
        }
        stage('Lint') {
            steps {
                sh 'uv run ruff check .'
                sh 'uv run python manage.py check --deploy'
            }
        }
        stage('Test') {
            steps {
                sh 'uv run python manage.py migrate'
                sh 'uv run python manage.py makemigrations --check --dry-run'
                sh 'uv run pytest --junitxml=report.xml --cov'
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

### Database Service for Tests

```groovy
stage('Test') {
    agent {
        docker {
            image 'python:3.12-slim'
            args '--network=ci-network'
        }
    }
    environment {
        DATABASE_URL = 'postgresql://test:test@postgres:5432/test'
        DJANGO_SETTINGS_MODULE = 'config.settings.test'
    }
    steps {
        sh 'pip install uv && uv sync'
        sh 'uv run python manage.py migrate'
        sh 'uv run pytest --junitxml=report.xml'
    }
    post {
        always {
            junit 'report.xml'
        }
    }
}
```

### Static Files Collection

```groovy
stage('Static Files') {
    steps {
        sh 'uv run python manage.py collectstatic --noinput'
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "Jenkinsfile"
```

## Additional Dos

- DO set `DJANGO_SETTINGS_MODULE` in the pipeline environment block
- DO publish JUnit XML results with `junit` post step
- DO run `makemigrations --check --dry-run` to catch schema drift
- DO run `collectstatic --noinput` to verify static file configuration

## Additional Don'ts

- DON'T run tests without setting `DJANGO_SETTINGS_MODULE` -- defaults may point to production
- DON'T use production `SECRET_KEY` in CI pipelines
- DON'T skip `post { always }` for test result collection
