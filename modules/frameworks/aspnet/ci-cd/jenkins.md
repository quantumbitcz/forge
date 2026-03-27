# Jenkins with ASP.NET

> Extends `modules/ci-cd/jenkins.md` with ASP.NET Core pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'mcr.microsoft.com/dotnet/sdk:9.0' } }

    stages {
        stage('Restore') { steps { sh 'dotnet restore' } }
        stage('Build') { steps { sh 'dotnet build --no-restore -c Release' } }
        stage('Test') {
            steps {
                sh 'dotnet test --no-build -c Release --logger "trx;LogFileName=results.trx"'
            }
            post {
                always { mstest testResultsFile: '**/results.trx' }
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
            def image = docker.build("${env.REGISTRY}/aspnet-app:${env.BUILD_NUMBER}")
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

- DO use the .NET SDK Docker image for consistent build environments
- DO publish TRX test results for Jenkins test trend tracking
- DO build in Release configuration
- DO use declarative pipelines

## Additional Don'ts

- DON'T use Debug configuration in CI
- DON'T skip `post { always }` for test results
- DON'T use `agent any` when builds need a specific .NET SDK version
