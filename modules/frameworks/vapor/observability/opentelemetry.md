# OpenTelemetry with Vapor

## Integration Setup

```swift
// Package.swift
.package(url: "https://github.com/swift-otel/swift-otel.git", from: "0.11.0"),
.package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
// targets:
.product(name: "OTel", package: "swift-otel"),
.product(name: "OTLPGRPC", package: "swift-otel"),
.product(name: "Logging", package: "swift-log"),
```

```swift
// configure.swift
import OTel, OTLPGRPC, Logging

let exporter = try OTLPGRPCSpanExporter(
    configuration: .init(endpoint: Environment.get("OTEL_EXPORTER_OTLP_ENDPOINT") ?? "http://localhost:4317")
)
let processor  = OTelBatchSpanProcessor(exporter: exporter, configuration: .init())
let provider   = OTelTracerProvider(
    resource: .init(attributes: [
        "service.name":    .string(Environment.get("SERVICE_NAME") ?? "vapor-app"),
        "service.version": .string(Environment.get("APP_VERSION") ?? "0.0.0"),
    ]),
    processor: processor
)
InstrumentationSystem.bootstrap(provider)
LoggingSystem.bootstrap(StreamLogHandler.standardOutput)   // structured JSON logging
```

## Framework-Specific Patterns

### Middleware for Tracing
```swift
struct TracingMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let tracer = InstrumentationSystem.tracer
        let span   = tracer.startSpan(
            "\(req.method.rawValue) \(req.url.path)",
            baggage:    .current ?? .topLevel,
            ofKind:     .server,
            at:         DefaultTracerClock.now
        )
        span.attributes["http.request.method"]  = .string(req.method.rawValue)
        span.attributes["url.path"]             = .string(req.url.path)
        span.attributes["server.address"]       = .string(req.headers.first(name: "host") ?? "")

        defer { span.end(at: DefaultTracerClock.now) }
        do {
            let response = try await next.respond(to: req)
            span.attributes["http.response.status_code"] = .int(Int(response.status.code))
            return response
        } catch {
            span.recordError(error)
            span.status = .error(description: error.localizedDescription)
            throw error
        }
    }
}
```

### Structured Logging with swift-log
```swift
var logger = req.logger
logger[metadataKey: "user_id"]  = "\(userID)"
logger[metadataKey: "trace_id"] = "\(span.context.traceID)"
logger.info("Processing order", metadata: ["order_id": "\(orderID)"])
```

## Scaffolder Patterns

```yaml
patterns:
  configure:  "Sources/App/configure.swift"
  middleware: "Sources/App/Middleware/TracingMiddleware.swift"
```

## Additional Dos/Don'ts

- DO register `TracingMiddleware` before route handlers in the middleware stack
- DO propagate trace context via W3C `traceparent` header using baggage extraction
- DO add `service.name` and `service.version` resource attributes at SDK initialization
- DO use `OTelBatchSpanProcessor` in production; `OTelSimpleSpanProcessor` in tests only
- DON'T log PII or tokens in span attributes or log metadata
- DON'T block the EventLoop in span processors — swift-otel runs async batch export
- DON'T hardcode the OTLP endpoint; read from `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable
