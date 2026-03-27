# OpenShift with Kubernetes

> Extends `modules/container-orchestration/openshift.md` with Kubernetes infrastructure management patterns.
> Generic OpenShift conventions (DeploymentConfig, Routes, BuildConfig) are NOT repeated here.

## Integration Setup

```yaml
# Helm chart values for OpenShift-specific settings
# values-openshift.yaml
route:
  enabled: true
  tls:
    termination: edge
securityContext:
  runAsNonRoot: true
  # Do NOT set runAsUser -- OpenShift assigns arbitrary UIDs
```

## Framework-Specific Patterns

### OpenShift Route vs Ingress

```yaml
# OpenShift Route (preferred on OpenShift)
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: my-app
spec:
  to:
    kind: Service
    name: my-app
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

OpenShift Routes are the native ingress mechanism. While standard Kubernetes Ingress objects work on OpenShift via the HAProxy-based router, Routes offer features like re-encryption TLS termination and cookie-based sticky sessions that Ingress does not.

### Security Context Constraints (SCCs)

```yaml
# SCC for restricted workloads (default on OpenShift 4.x)
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: app-restricted
allowPrivilegedContainer: false
runAsUser:
  type: MustRunAsRange
seLinuxContext:
  type: MustRunAs
fsGroup:
  type: MustRunAs
volumes:
  - configMap
  - downwardAPI
  - emptyDir
  - persistentVolumeClaim
  - projected
  - secret
```

SCCs replace PodSecurityPolicies on OpenShift. The `restricted` SCC is the default -- it enforces non-root, drops all capabilities, and restricts volume types.

### Helm Chart Compatibility

```yaml
# templates/_helpers.tpl -- detect OpenShift
{{- define "isOpenShift" -}}
{{- if .Capabilities.APIVersions.Has "route.openshift.io/v1" -}}true{{- end -}}
{{- end -}}

# templates/route.yaml (conditional)
{{- if include "isOpenShift" . }}
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: {{ .Release.Name }}
spec:
  to:
    kind: Service
    name: {{ .Release.Name }}
  tls:
    termination: edge
{{- end }}
```

Detect OpenShift at template time to conditionally create Routes instead of Ingresses. This makes Helm charts portable across vanilla Kubernetes and OpenShift.

### ImageStream for Build Pipeline

```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: my-app
spec:
  lookupPolicy:
    local: true
```

ImageStreams provide an abstraction over container registries. `lookupPolicy.local: true` enables Deployments to reference ImageStreamTags directly without the full registry URL.

## Scaffolder Patterns

```yaml
patterns:
  route: "deploy/openshift/route.yaml"
  scc: "deploy/openshift/scc.yaml"
  imagestream: "deploy/openshift/imagestream.yaml"
```

## Additional Dos

- DO use OpenShift Routes instead of Ingress for TLS termination
- DO detect OpenShift in Helm charts using `Capabilities.APIVersions`
- DO use `restricted` SCC as the baseline -- escalate only when justified
- DO use ImageStreams for build pipeline image management

## Additional Don'ts

- DON'T set `runAsUser` to a specific UID -- OpenShift assigns arbitrary UIDs
- DON'T use `privileged` SCC unless absolutely necessary (e.g., CNI plugins)
- DON'T create Ingress objects when Routes provide the same functionality with better integration
- DON'T hardcode the internal registry URL -- use ImageStream references
