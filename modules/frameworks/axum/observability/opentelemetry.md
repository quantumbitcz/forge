# Axum + OpenTelemetry

> Extends `modules/observability/opentelemetry.md` with Axum/tower-http tracing integration.
> Generic OTel conventions (context propagation, span naming, sampling, exporters) are NOT repeated here.

## Integration Setup

```toml
# Cargo.toml
[dependencies]
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
tracing-opentelemetry = "0.26"
opentelemetry = { version = "0.26", features = ["trace"] }
opentelemetry_sdk = { version = "0.26", features = ["rt-tokio", "trace"] }
opentelemetry-otlp = { version = "0.26", features = ["grpc-tonic", "trace", "metrics"] }
opentelemetry-semantic-conventions = "0.26"
tower-http = { version = "0.6", features = ["trace", "request-id"] }
axum = "0.8"
```

```rust
// telemetry.rs
use opentelemetry::global;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{runtime, trace as sdktrace, Resource};
use opentelemetry::KeyValue;
use opentelemetry_semantic_conventions::resource::{SERVICE_NAME, SERVICE_VERSION};
use tracing_opentelemetry::OpenTelemetryLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

pub fn init_telemetry(service_name: &str, service_version: &str, otlp_endpoint: &str) {
    let resource = Resource::new(vec![
        KeyValue::new(SERVICE_NAME, service_name.to_string()),
        KeyValue::new(SERVICE_VERSION, service_version.to_string()),
    ]);

    let tracer = opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_exporter(
            opentelemetry_otlp::new_exporter()
                .tonic()
                .with_endpoint(otlp_endpoint),
        )
        .with_trace_config(sdktrace::Config::default().with_resource(resource))
        .install_batch(runtime::Tokio)
        .expect("Failed to initialise OTel tracer");

    tracing_subscriber::registry()
        .with(EnvFilter::from_default_env())
        .with(tracing_opentelemetry::layer().with_tracer(tracer))
        .with(tracing_subscriber::fmt::layer().json())
        .init();
}

pub fn shutdown_telemetry() {
    global::shutdown_tracer_provider();
}
```

## Framework-Specific Patterns

### tower-http trace layer on Axum router
```rust
use tower_http::{
    request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer},
    trace::{DefaultMakeSpan, DefaultOnResponse, TraceLayer},
};
use tracing::Level;

let app = Router::new()
    .route("/orders", post(create_order))
    .layer(
        TraceLayer::new_for_http()
            .make_span_with(
                DefaultMakeSpan::new()
                    .level(Level::INFO)
                    .include_headers(false),  // avoid logging auth headers
            )
            .on_response(DefaultOnResponse::new().level(Level::INFO)),
    )
    .layer(PropagateRequestIdLayer::x_request_id())
    .layer(SetRequestIdLayer::x_request_id(MakeRequestUuid));
```

### Manual spans in handlers
```rust
use tracing::instrument;

#[instrument(
    name = "order.create",
    skip(state, payload),
    fields(order.items_count = payload.items.len())
)]
async fn create_order(
    State(state): State<AppState>,
    Json(payload): Json<CreateOrderRequest>,
) -> Result<Json<Order>, AppError> {
    let span = tracing::Span::current();

    let order = state.order_service.create(payload).await.map_err(|e| {
        span.record("error", true);
        span.record("error.message", e.to_string().as_str());
        e
    })?;

    span.record("order.id", order.id.to_string().as_str());
    Ok(Json(order))
}
```

### Prometheus metrics with metrics middleware
```toml
[dependencies]
metrics = "0.23"
metrics-exporter-prometheus = "0.15"
```

```rust
use metrics_exporter_prometheus::PrometheusBuilder;

let recorder = PrometheusBuilder::new()
    .with_http_listener(([0, 0, 0, 0], 9090))  // separate port for /metrics
    .install_recorder()
    .expect("Failed to install Prometheus recorder");

// In handlers:
metrics::counter!("orders_created_total", "region" => region).increment(1);
metrics::histogram!("order_processing_duration_seconds").record(duration.as_secs_f64());
```

## Additional Dos

- Call `shutdown_telemetry()` in the graceful shutdown hook (`SIGTERM`) to flush the BatchSpanProcessor before exit.
- Use `#[instrument]` on handler and service functions with `skip(state)` to avoid recording large state objects in spans.
- Use `fields(...)` in `#[instrument]` to declare span attributes at the call site for type-safe attribute names.
- Expose the Prometheus `/metrics` endpoint on a dedicated port (e.g., 9090) separate from the API port.

## Additional Don'ts

- Don't use `include_headers(true)` in `TraceLayer` — HTTP headers may contain auth tokens or session cookies.
- Don't record user-supplied request body content in span fields — use opaque IDs only.
- Don't block the Tokio runtime during OTel initialisation — use `install_batch(runtime::Tokio)` to avoid this.
- Don't call `tracing_subscriber::registry().init()` more than once — it panics on re-initialisation.
