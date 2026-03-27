# Jenkins with Spring

> Extends `modules/ci-cd/jenkins.md` with Spring Boot pipeline patterns.
> Generic Jenkins conventions (declarative pipelines, shared libraries, agent management) are NOT repeated here.

## Integration Setup

```groovy
// Jenkinsfile
pipeline {
    agent { docker { image 'eclipse-temurin:21-jdk' } }

    tools {
        jdk 'temurin-21'
    }

    environment {
        GRADLE_OPTS = '-Dorg.gradle.daemon=false'
    }

    stages {
        stage('Build') {
            steps {
                sh './gradlew assemble'
            }
        }
        stage('Test') {
            steps {
                sh './gradlew test'
            }
            post {
                always {
                    junit 'build/test-results/test/*.xml'
                }
            }
        }
    }
}
```

## Framework-Specific Patterns

### Testcontainers with Docker Agent

```groovy
stage('Integration Test') {
    agent {
        docker {
            image 'eclipse-temurin:21-jdk'
            args '-v /var/run/docker.sock:/var/run/docker.sock --group-add docker'
        }
    }
    environment {
        TESTCONTAINERS_RYUK_DISABLED = 'true'
    }
    steps {
        sh './gradlew integrationTest'
    }
    post {
        always {
            junit 'build/test-results/integrationTest/*.xml'
        }
    }
}
```

Mount the Docker socket into the build agent container for Testcontainers access. Add the `docker` group to avoid permission errors.

### Maven Jenkinsfile

```groovy
pipeline {
    agent { docker { image 'eclipse-temurin:21-jdk' } }

    stages {
        stage('Build') {
            steps {
                sh './mvnw -B package -DskipTests'
            }
        }
        stage('Test') {
            steps {
                sh './mvnw -B test'
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                }
            }
        }
        stage('Integration Test') {
            steps {
                sh './mvnw -B verify -DskipUnitTests'
            }
            post {
                always {
                    junit 'target/failsafe-reports/*.xml'
                }
            }
        }
    }
}
```

### Shared Library for Spring Boot Pipelines

```groovy
// vars/springBootPipeline.groovy
def call(Map config = [:]) {
    def javaVersion = config.javaVersion ?: '21'
    def buildTool = config.buildTool ?: 'gradle'
    def buildCmd = buildTool == 'gradle' ? './gradlew' : './mvnw -B'

    pipeline {
        agent { docker { image "eclipse-temurin:${javaVersion}-jdk" } }
        stages {
            stage('Build') { steps { sh "${buildCmd} assemble" } }
            stage('Test') { steps { sh "${buildCmd} test" } }
        }
    }
}
```

Usage: `springBootPipeline(javaVersion: '21', buildTool: 'gradle')`.

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
  shared_lib: "vars/springBootPipeline.groovy"
```

## Additional Dos

- DO publish JUnit XML results with `junit` post step for test trend tracking
- DO mount Docker socket for Testcontainers rather than running Docker-in-Docker
- DO use declarative pipelines over scripted for consistency and readability
- DO extract reusable Spring Boot pipeline logic into a shared library

## Additional Don'ts

- DON'T run the Gradle daemon in Jenkins agents -- they're ephemeral
- DON'T use `agent any` when Spring Boot builds need specific JDK versions
- DON'T skip `post { always }` for test result collection -- flaky test tracking needs it
