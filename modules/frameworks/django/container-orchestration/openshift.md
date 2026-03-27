# OpenShift with Django

> Extends `modules/container-orchestration/openshift.md` with Django deployment patterns.
> Generic OpenShift conventions (DeploymentConfig, Routes, BuildConfig) are NOT repeated here.

## Integration Setup

```yaml
# openshift/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: django-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: django-app
  template:
    spec:
      containers:
        - name: django-app
          image: image-registry.openshift-image-registry.svc:5000/myproject/django-app:latest
          ports:
            - containerPort: 8000
          env:
            - name: DJANGO_SETTINGS_MODULE
              value: config.settings.production
            - name: ALLOWED_HOSTS
              value: "*"
          command: ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "4"]
          livenessProbe:
            httpGet:
              path: /health/
              port: 8000
          readinessProbe:
            httpGet:
              path: /health/
              port: 8000
```

## Framework-Specific Patterns

### Source-to-Image (S2I) Build

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: django-app
spec:
  source:
    type: Git
    git:
      uri: https://github.com/org/django-app
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: django-app:latest
```

### OpenShift Route

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: django-app
spec:
  to:
    kind: Service
    name: django-app
  port:
    targetPort: 8000
  tls:
    termination: edge
```

### Arbitrary UID Compliance

Django's file-based operations (media uploads, collectstatic) need writable directories under arbitrary UIDs:

```dockerfile
RUN mkdir -p /app/staticfiles /app/media && chmod -R g=u /app/staticfiles /app/media
```

### Django Migration Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: django-app-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: image-registry.openshift-image-registry.svc:5000/myproject/django-app:latest
          command: ["python", "manage.py", "migrate", "--noinput"]
          envFrom:
            - secretRef:
                name: django-app-db
      restartPolicy: Never
```

### Static Files Collection

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: django-app-collectstatic
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/sync-wave: "-2"
spec:
  template:
    spec:
      containers:
        - name: collectstatic
          image: image-registry.openshift-image-registry.svc:5000/myproject/django-app:latest
          command: ["python", "manage.py", "collectstatic", "--noinput"]
      restartPolicy: Never
```

## Scaffolder Patterns

```yaml
patterns:
  deployment: "openshift/deployment.yaml"
  route: "openshift/route.yaml"
  buildconfig: "openshift/buildconfig.yaml"
```

## Additional Dos

- DO use Gunicorn as the WSGI server -- never use Django's development server in production
- DO run `collectstatic` as a pre-deploy job
- DO run `migrate --noinput` before app deployment
- DO make `staticfiles/` and `media/` group-writable for arbitrary UID compliance

## Additional Don'ts

- DON'T use `DEBUG=True` in production -- it leaks sensitive information
- DON'T listen on ports below 1024
- DON'T skip readiness probes -- Routes depend on them for traffic routing
- DON'T hardcode `ALLOWED_HOSTS` to specific domains in the image -- inject via environment
