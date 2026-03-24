# Spring gRPC — API Protocol Binding

## Integration Setup
- Add `net.devh:grpc-spring-boot-starter` (server) and/or `net.devh:grpc-client-spring-boot-starter`
- Add `com.google.protobuf:protobuf-gradle-plugin`; configure `protobuf` block in `build.gradle.kts`
- Proto files in `src/main/proto/*.proto`; generated sources auto-added to compile path
- Health check: add `grpc-services` dependency and enable `grpc.server.health-service-enabled=true`

## Framework-Specific Patterns
- Annotate service implementations with `@GrpcService`; extend the generated `*ImplBase`
- Inject gRPC stubs with `@GrpcClient("service-name")`; configure address in `grpc.client.*` properties
- Register interceptors as Spring beans annotated with `@GrpcGlobalServerInterceptor` or `@GrpcGlobalClientInterceptor`
- Use `StreamObserver` for server-streaming and bidirectional streaming RPCs
- Map domain exceptions to `StatusRuntimeException` in a global interceptor or within the service
- For mutual TLS: configure `grpc.server.security.*` and `grpc.client.*.security.*` properties

## Scaffolder Patterns
```
src/main/
  proto/
    user_service.proto         # service + message definitions
  kotlin/com/example/
    grpc/
      UserGrpcService.kt       # @GrpcService extends UserServiceGrpcKt.UserServiceCoroutineImplBase
      GrpcExceptionInterceptor.kt  # @GrpcGlobalServerInterceptor
    config/
      GrpcClientConfig.kt      # stub channel customization if needed
build.gradle.kts               # protobuf plugin + grpc codegen config
```

## Dos
- Use Kotlin coroutine-based generated stubs (`*CoroutineImplBase`) for cleaner async code
- Validate proto messages early in the service before business logic
- Implement `GrpcHealthIndicator` so Spring Actuator and gRPC health protocol both report status
- Use deadline propagation: always set deadlines on outbound client calls

## Don'ts
- Don't expose raw proto types outside the gRPC layer; map to domain objects in the service
- Don't catch all exceptions silently; always map to a `Status` code
- Don't share a single managed channel across different service clients without tuning
- Don't commit generated proto sources to version control
