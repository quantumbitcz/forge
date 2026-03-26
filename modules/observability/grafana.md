# Grafana — Observability Best Practices

## Overview

Grafana is an open-source visualization and dashboarding platform supporting 100+ data sources
(Prometheus, InfluxDB, Elasticsearch, PostgreSQL, CloudWatch, Datadog). Use it for creating
operational dashboards, alerting, and visualizing metrics, logs (via Loki), and traces (via Tempo).
Grafana excels at unifying multiple data sources in a single pane of glass. Avoid using it as a
data store — Grafana queries external sources and does not store metrics itself.

## Architecture Patterns

### Dashboard-as-Code (Jsonnet/Grafonnet)
```jsonnet
local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local prometheus = grafana.prometheus;
local graphPanel = grafana.graphPanel;

dashboard.new('API Latency', tags=['api', 'sre'])
.addPanel(
  graphPanel.new('Request Duration (p99)', datasource='Prometheus')
  .addTarget(prometheus.target(
    'histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{service="$service"}[5m]))',
    legendFormat='{{method}} {{path}}'
  )), gridPos={ h: 8, w: 12, x: 0, y: 0 }
)
```

### Terraform Provisioning
```hcl
resource "grafana_dashboard" "api" {
  config_json = file("dashboards/api.json")
  folder      = grafana_folder.sre.id
}

resource "grafana_alert_rule" "high_error_rate" {
  name      = "High Error Rate"
  folder_uid = grafana_folder.sre.uid
  rule_group = "api-alerts"
  condition  = "C"

  data {
    ref_id = "A"
    datasource_uid = grafana_data_source.prometheus.uid
    model = jsonencode({
      expr = "rate(http_requests_total{status=~'5..'}[5m]) / rate(http_requests_total[5m])"
    })
  }
}
```

### Anti-pattern — creating dashboards manually in the UI for production: Manual dashboards can't be versioned, reviewed, or reproduced. Use dashboard-as-code (Jsonnet, Terraform, or provisioned JSON).

## Configuration

```yaml
# docker-compose.yml
grafana:
  image: grafana/grafana:11
  ports: ["3000:3000"]
  volumes:
    - grafana-data:/var/lib/grafana
    - ./provisioning:/etc/grafana/provisioning
  environment:
    GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
    GF_AUTH_ANONYMOUS_ENABLED: "false"
    GF_USERS_ALLOW_SIGN_UP: "false"
```

## Dos
- Use dashboard-as-code (Jsonnet/Terraform/provisioned JSON) for all production dashboards.
- Use variables (`$service`, `$environment`) to make dashboards reusable across services.
- Use Grafana Alerting (unified alerting) for alert rules — it centralizes notifications.
- Use folders and RBAC to organize dashboards by team and restrict access.
- Include SLO dashboards with error budget burn rate for every critical service.
- Use annotations to mark deployments, incidents, and config changes on dashboards.
- Export dashboards as JSON and version-control them alongside application code.

## Don'ts
- Don't create production dashboards manually in the UI — they can't be versioned or reviewed.
- Don't use Grafana as a data store — it queries external data sources only.
- Don't skip authentication — Grafana's default admin credentials are well-known.
- Don't create dashboards with too many panels (> 20) — they become slow and unreadable.
- Don't use Grafana alerting without notification channels — alerts need to reach people.
- Don't ignore dashboard loading time — queries across long time ranges or many series cause timeouts.
- Don't hardcode data source UIDs — use provisioned data sources with consistent naming.
