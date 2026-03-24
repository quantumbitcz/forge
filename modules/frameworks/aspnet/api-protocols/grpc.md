# ASP.NET gRPC — API Protocol Binding

## Integration Setup
- Add `Grpc.AspNetCore` (server) + `Grpc.Net.ClientFactory` (typed client factory)
- Proto files in `Protos/` directory; add `<Protobuf Include="Protos/*.proto" GrpcServices="Server|Client" />` in `.csproj`
- Health checks: `Grpc.HealthCheck` + `builder.Services.AddGrpcHealthChecks()`
- Register: `builder.Services.AddGrpc()` + `app.MapGrpcService<UserServiceImpl>()`

## Framework-Specific Patterns
- Implement generated base class: `public class UserServiceImpl : UserService.UserServiceBase`; override RPC methods
- Return `Task<T>` for unary; `Task` with `IServerStreamWriter<T>` for server streaming
- `ServerCallContext` provides deadline, cancellation token, metadata (headers); always pass `context.CancellationToken` to async calls
- Interceptors: inherit `Interceptor`; register with `builder.Services.AddGrpc(opt => opt.Interceptors.Add<AuthInterceptor>())`
- Client factory: `builder.Services.AddGrpcClient<UserService.UserServiceClient>(o => o.Address = new Uri(config["GrpcUrl"]))` then inject `UserService.UserServiceClient` via DI
- Health: call `services.MapGrpcHealthChecksService()` and configure with existing ASP.NET health checks

## Scaffolder Patterns
```
src/
  Protos/
    user_service.proto       # service + message definitions
  Services/
    UserServiceImpl.cs       # : UserService.UserServiceBase
  Interceptors/
    AuthInterceptor.cs       # : Interceptor
  Program.cs                 # AddGrpc, MapGrpcService, MapGrpcHealthChecksService
MyProject.csproj             # <Protobuf> ItemGroup
```

## Dos
- Set deadlines on all outbound gRPC calls from the client factory
- Use `context.CancellationToken` throughout — propagate cancellation from the `ServerCallContext`
- Return `RpcException` with meaningful `StatusCode` (e.g., `StatusCode.NotFound`, `StatusCode.InvalidArgument`)
- Enable `grpc-web` middleware (`app.UseGrpcWeb()`) if browser clients need access

## Don'ts
- Don't use HTTP/1.1 for gRPC in production — ensure Kestrel is configured for HTTP/2
- Don't throw arbitrary exceptions from service implementations — always throw `RpcException`
- Don't add proto-generated files to version control — generate at build time
- Don't skip health check registration when deploying to Kubernetes
