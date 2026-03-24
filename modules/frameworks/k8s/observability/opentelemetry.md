# OpenTelemetry on Kubernetes

## Integration Setup

```bash
# Install OTel Operator via Helm
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace observability --create-namespace \
  --set "manager.collectorImage.repository=otel/opentelemetry-collector-k8s"
```

## Framework-Specific Patterns

### OTel Collector DaemonSet
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: observability
spec:
  mode: daemonset        # one pod per node for log/metric collection
  config: |
    receivers:
      otlp:
        protocols:
          grpc: { endpoint: "0.0.0.0:4317" }
          http: { endpoint: "0.0.0.0:4318" }
      prometheus:
        config:
          scrape_configs:
            - job_name: "k8s-pods"
              kubernetes_sd_configs:
                - role: pod
              relabel_configs:
                - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                  action: keep
                  regex: "true"
      filelog:
        include: ["/var/log/pods/*/*/*.log"]
        operators:
          - type: json_parser
            timestamp: { parse_from: attributes.time, layout: "%Y-%m-%dT%H:%M:%S.%LZ" }
    processors:
      batch: { timeout: 5s, send_batch_size: 1024 }
      memory_limiter: { limit_mib: 400, spike_limit_mib: 100 }
      k8sattributes:
        auth_type: serviceAccount
        passthrough: false
        extract:
          metadata: [k8s.pod.name, k8s.namespace.name, k8s.deployment.name, k8s.node.name]
    exporters:
      otlp/jaeger:   { endpoint: "jaeger-collector.observability:4317", tls: { insecure: true } }
      prometheus:    { endpoint: "0.0.0.0:8889" }
      loki:          { endpoint: "http://loki.observability:3100/loki/api/v1/push" }
    service:
      pipelines:
        traces:  { receivers: [otlp], processors: [memory_limiter, k8sattributes, batch], exporters: [otlp/jaeger] }
        metrics: { receivers: [otlp, prometheus], processors: [memory_limiter, batch], exporters: [prometheus] }
        logs:    { receivers: [filelog, otlp], processors: [memory_limiter, k8sattributes, batch], exporters: [loki] }
```

### Auto-Instrumentation Injection
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: java-instrumentation
  namespace: default
spec:
  exporter:
    endpoint: http://otel-collector.observability:4317
  propagators: [tracecontext, baggage, b3]
  sampler:
    type: parentbased_traceidratio
    argument: "0.1"       # 10% sampling in production
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:2.6.0
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.53.0
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.48b0

---
# Enable per-namespace or per-pod via annotation
# Namespace level:
apiVersion: v1
kind: Namespace
metadata:
  name: production
  annotations:
    instrumentation.opentelemetry.io/inject-java: "observability/java-instrumentation"

# Pod level:
# annotations:
#   instrumentation.opentelemetry.io/inject-java: "observability/java-instrumentation"
```

### Prometheus ServiceMonitor
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp-monitor
  namespace: production
  labels:
    release: kube-prometheus-stack   # must match Prometheus operator selector
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
```

### FluentBit Log Collection (alternative to OTel filelog receiver)
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: observability
spec:
  selector:
    matchLabels:
      app: fluent-bit
  template:
    spec:
      serviceAccountName: fluent-bit
      containers:
        - name: fluent-bit
          image: fluent/fluent-bit:3.1
          volumeMounts:
            - name: varlog
              mountPath: /var/log
              readOnly: true
          env:
            - name: LOKI_HOST
              value: "http://loki.observability:3100"
      volumes:
        - name: varlog
          hostPath: { path: /var/log }
```

## Scaffolder Patterns

```yaml
patterns:
  collector:        "k8s/observability/otel-collector.yaml"
  instrumentation:  "k8s/observability/instrumentation.yaml"
  service_monitor:  "k8s/observability/{service}-service-monitor.yaml"
  grafana_dashboard: "k8s/observability/dashboards/{service}-dashboard.json"
```

## Additional Dos/Don'ts

- DO use `k8sattributes` processor to enrich all signals with pod/namespace/deployment metadata
- DO configure `memory_limiter` processor to prevent OOM kills under traffic spikes
- DO use `daemonset` mode Collector for log collection; `deployment` or `sidecar` for trace/metric aggregation
- DO set sampler `argument` to 0.01–0.1 in production; `1.0` only in dev/staging
- DO pin Collector and auto-instrumentation image versions for reproducible deployments
- DON'T route OTLP traffic from pods directly to the backend — always go through the Collector
- DON'T grant `cluster-admin` to the Collector ServiceAccount; use only `get/list/watch` on pods/nodes
- DON'T log Kubernetes secrets or environment variables containing credentials via filelog receiver
