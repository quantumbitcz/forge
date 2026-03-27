# Jenkins with Express

> Extends `modules/ci-cd/jenkins.md` with Express/Node.js pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'node:22-slim' } }

    environment {
        NODE_ENV = 'test'
        npm_config_cache = '.npm'
    }

    stages {
        stage('Install') {
            steps {
                sh 'npm ci'
            }
        }
        stage('Lint') {
            steps {
                sh 'npx eslint .'
            }
        }
        stage('Test') {
            steps {
                sh 'npm test -- --coverage --reporters=default --reporters=jest-junit'
            }
            post {
                always {
                    junit 'junit.xml'
                }
            }
        }
    }
}
```

## Framework-Specific Patterns

### Health Endpoint Testing

```groovy
stage('Smoke Test') {
    steps {
        sh '''
            npm start &
            sleep 3
            curl -f http://localhost:3000/health || exit 1
            kill %1
        '''
    }
}
```

### Docker Image Publishing

```groovy
stage('Publish') {
    when { branch 'main' }
    steps {
        script {
            def image = docker.build("${env.REGISTRY}/express-app:${env.BUILD_NUMBER}")
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

- DO use `npm ci` for deterministic installs in Jenkins
- DO publish JUnit XML results with `junit` post step
- DO set `npm_config_cache` to a local directory for caching
- DO use declarative pipelines for consistency

## Additional Don'ts

- DON'T use `npm install` in CI -- use `npm ci` for reproducible builds
- DON'T skip `post { always }` for test result collection
- DON'T use `agent any` when builds need a specific Node.js version
