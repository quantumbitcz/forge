# Helm with Spring

> Extends `modules/container-orchestration/helm.md` with Spring Boot Helm chart patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```yaml
# Chart.yaml
apiVersion: v2
name: spring-boot-app
version: 1.0.0
appVersion: "3.4.3"
description: Spring Boot application Helm chart
```

```yaml
# values.yaml
replicaCount: 2

image:
  repository: registry.example.com/spring-app
  tag: latest
  pullPolicy: IfNotPresent

spring:
  profiles: production
  jvmOpts: >-
    -XX:MaxRAMPercentage=75
    -XX:+UseG1GC
    -XX:+UseContainerSupport
    -XX:+ExitOnOutOfMemoryError

resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: "1"

actuator:
  port: 8080
  basePath: /actuator
```

## Framework-Specific Patterns

### Spring Profiles Mapped to Environments

```yaml
# values-dev.yaml
spring:
  profiles: dev
  jvmOpts: >-
    -XX:MaxRAMPercentage=75
    -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005

# values-staging.yaml
spring:
  profiles: staging

# values-production.yaml
spring:
  profiles: production
replicaCount: 3
resources:
  requests:
    memory: 1Gi
  limits:
    memory: 2Gi
```

Install with `helm install app ./chart -f values-production.yaml`.

### Actuator Health Probe Paths

```yaml
# templates/deployment.yaml (snippet)
containers:
  - name: {{ .Chart.Name }}
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    env:
      - name: SPRING_PROFILES_ACTIVE
        value: {{ .Values.spring.profiles | quote }}
      - name: JAVA_OPTS
        value: {{ .Values.spring.jvmOpts | quote }}
    ports:
      - name: http
        containerPort: 8080
    livenessProbe:
      httpGet:
        path: {{ .Values.actuator.basePath }}/health/liveness
        port: http
      initialDelaySeconds: 60
      periodSeconds: 10
      failureThreshold: 5
    readinessProbe:
      httpGet:
        path: {{ .Values.actuator.basePath }}/health/readiness
        port: http
      initialDelaySeconds: 30
      periodSeconds: 5
      failureThreshold: 3
    startupProbe:
      httpGet:
        path: {{ .Values.actuator.basePath }}/health/liveness
        port: http
      initialDelaySeconds: 10
      periodSeconds: 5
      failureThreshold: 30
    resources:
      {{- toYaml .Values.resources | nindent 6 }}
```

Use all three probe types:
- **startupProbe**: handles slow Spring Boot startup (up to 150s with the config above)
- **livenessProbe**: restarts stuck JVMs after startup completes
- **readinessProbe**: removes pod from service during rolling updates and back-pressure

### Spring Boot Configuration via ConfigMap

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-config
data:
  application-{{ .Values.spring.profiles }}.yml: |
    server:
      port: 8080
    management:
      endpoints:
        web:
          exposure:
            include: health,info,prometheus
      endpoint:
        health:
          probes:
            enabled: true
```

```yaml
# templates/deployment.yaml (volume mount)
volumeMounts:
  - name: spring-config
    mountPath: /app/config
volumes:
  - name: spring-config
    configMap:
      name: {{ .Release.Name }}-config
```

### Spring Boot Admin Integration

```yaml
# values.yaml
admin:
  enabled: false
  url: http://spring-boot-admin:8080

# templates/deployment.yaml (conditional env)
{{- if .Values.admin.enabled }}
- name: SPRING_BOOT_ADMIN_CLIENT_URL
  value: {{ .Values.admin.url | quote }}
- name: SPRING_BOOT_ADMIN_CLIENT_INSTANCE_SERVICE_BASE_URL
  value: "http://{{ .Release.Name }}:8080"
{{- end }}
```

## Scaffolder Patterns

```yaml
patterns:
  chart: "helm/{chart-name}/Chart.yaml"
  values: "helm/{chart-name}/values.yaml"
  values_env: "helm/{chart-name}/values-{env}.yaml"
  deployment: "helm/{chart-name}/templates/deployment.yaml"
  service: "helm/{chart-name}/templates/service.yaml"
  configmap: "helm/{chart-name}/templates/configmap.yaml"
```

## Additional Dos

- DO use `startupProbe` for Spring Boot -- it decouples startup tolerance from liveness checking
- DO map Spring profiles to Helm value files per environment
- DO set `MaxRAMPercentage=75` in JVM opts and configure `resources.limits.memory` accordingly
- DO use ConfigMap for non-secret Spring configuration and Secrets for credentials

## Additional Don'ts

- DON'T set `initialDelaySeconds` on `livenessProbe` too low -- use `startupProbe` instead
- DON'T hardcode Spring profiles in the Docker image -- inject via `SPRING_PROFILES_ACTIVE` env var
- DON'T use `-Xmx` in Helm JVM opts -- use `MaxRAMPercentage` to scale with container memory limits
- DON'T include Spring Boot Admin client in production without network-policy restrictions
