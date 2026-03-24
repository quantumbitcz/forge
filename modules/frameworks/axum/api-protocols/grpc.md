# Axum + Tonic gRPC — API Protocol Binding

## Integration Setup
- `tonic` + `tonic-build` (build.rs codegen) + `prost` for protobuf serialization
- `tonic-health` for gRPC health protocol; `tonic-reflection` for server reflection
- Compose with Axum: use `tonic_web` or route tonic service alongside Axum routes via `Router::merge`

## Framework-Specific Patterns
- Implement the generated `*Server` trait on a struct: `#[tonic::async_trait] impl UserService for UserServiceImpl`
- Serve: `Server::builder().add_service(UserServiceServer::new(impl)).serve(addr).await`
- Compose with Axum on the same port: `axum::Router` + `tonic_web::enable(svc)` via `tower` service composition
- Interceptors: implement `tonic::service::Interceptor`; add with `.add_service(svc.with_interceptor(interceptor))`
- Health: `let (mut health_reporter, health_service) = tonic_health::server::health_reporter()`; set status per service
- Reflection: `tonic_reflection::server::Builder::configure().register_encoded_file_descriptor_set(...).build()`
- Streaming: use `tonic::Streaming<T>` for request streaming and `tokio_stream::wrappers::ReceiverStream` for server streaming

## Scaffolder Patterns
```
src/
  grpc/
    user_service.rs          # #[tonic::async_trait] impl UserService
    interceptors/
      auth.rs                # Interceptor impl
  proto/
    user.proto               # service + message definitions
build.rs                     # tonic_build::compile_protos(...)
Cargo.toml                   # tonic, tonic-build, prost deps
```

## Dos
- Define proto files in `proto/` directory; configure `build.rs` with `tonic_build::configure().build_server(true)`
- Map tonic `Status` codes semantically: `Status::not_found`, `Status::invalid_argument`, not generic `Status::internal`
- Enable `gzip` compression for large payloads: `Server::builder().accept_compressed(CompressionEncoding::Gzip)`
- Use `tonic_health` to report readiness; integrate with Kubernetes liveness/readiness probes

## Don'ts
- Don't commit generated protobuf code to version control; generate at build time via `build.rs`
- Don't use `tonic::transport::Channel` without configuring timeouts and keep-alive
- Don't panic on request handling errors — map all errors to appropriate `tonic::Status`
- Don't expose reflection in production without access controls
