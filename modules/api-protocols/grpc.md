# gRPC Conventions

## Overview

gRPC is a high-performance RPC framework using Protocol Buffers for serialization and HTTP/2 for transport.
These conventions cover `.proto` schema design, streaming patterns, error handling, interceptors, and
backward compatibility to produce services that are efficient, observable, and safe to evolve.

## Architecture Patterns

### Protobuf Schema Design

```protobuf
syntax = "proto3";

package myapp.users.v1;

option go_package = "github.com/example/myapp/gen/go/users/v1;usersv1";
option java_package = "com.example.myapp.users.v1";

// Group related services into a single file per domain.
service UserService {
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
  rpc ListUsers(ListUsersRequest) returns (ListUsersResponse);
  rpc CreateUser(CreateUserRequest) returns (CreateUserResponse);
  rpc WatchUserEvents(WatchUserEventsRequest) returns (stream UserEvent);
}

message GetUserRequest {
  string user_id = 1;
}

message GetUserResponse {
  User user = 1;
}

message User {
  string id        = 1;
  string email     = 2;
  string full_name = 3;
  google.protobuf.Timestamp created_at = 4;
}
```

Use wrapper types (`google.protobuf.StringValue`) to distinguish absent from empty. Use `google.protobuf.Timestamp`
for all time values, never string timestamps.

### Service Definition Patterns

- One service file per bounded context
- Use `Request`/`Response` message pairs per RPC — never reuse messages across different RPCs
- Place common types in a `common/v1/` package
- Use `oneof` for discriminated unions inside messages

### Four Streaming Modes

```protobuf
service DataService {
  // Unary — single request, single response (most common)
  rpc GetRecord(GetRecordRequest) returns (GetRecordResponse);

  // Server streaming — single request, stream of responses
  rpc ListLargeDataset(ListRequest) returns (stream DataRecord);

  // Client streaming — stream of requests, single response
  rpc UploadRecords(stream DataRecord) returns (UploadSummary);

  // Bidirectional streaming — stream in, stream out (e.g., chat, real-time sync)
  rpc SyncRecords(stream SyncRequest) returns (stream SyncResponse);
}
```

Prefer unary for most operations. Use server streaming for large paginated reads. Reserve bidirectional
streaming for real-time collaborative features.

## Configuration

### Deadlines and Timeouts

Always set a deadline on the client side; never rely on the server to bound call duration:

```go
// Go client
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()
resp, err := client.GetUser(ctx, &pb.GetUserRequest{UserId: "abc"})
```

```java
// Java client
UserServiceBlockingStub stub = UserServiceGrpc.newBlockingStub(channel)
    .withDeadlineAfter(5, TimeUnit.SECONDS);
```

Propagate deadlines through the call chain — child RPCs inherit the remaining parent deadline.

### Interceptors

Use interceptors (middleware) for cross-cutting concerns rather than duplicating logic in handlers:

```go
// Server interceptor chain (Go)
server := grpc.NewServer(
  grpc.ChainUnaryInterceptor(
    otelgrpc.UnaryServerInterceptor(),  // tracing
    grpczap.UnaryServerInterceptor(logger),  // logging
    grpc_auth.UnaryServerInterceptor(authFunc),  // authentication
    grpc_recovery.UnaryServerInterceptor(),  // panic recovery
  ),
  grpc.ChainStreamInterceptor(
    otelgrpc.StreamServerInterceptor(),
    grpczap.StreamServerInterceptor(logger),
  ),
)
```

### Health Checking Protocol

Implement the standard gRPC health check protocol so load balancers and orchestrators can probe liveness:

```protobuf
// Use grpc.health.v1.Health — do not redefine it
import "grpc/health/v1/health.proto";
```

```go
import "google.golang.org/grpc/health/grpc_health_v1"

healthServer := health.NewServer()
healthServer.SetServingStatus("myapp.users.v1.UserService", grpc_health_v1.HealthCheckResponse_SERVING)
grpc_health_v1.RegisterHealthServer(grpcServer, healthServer)
```

### Server Reflection

Enable server reflection in non-production environments so tools like `grpcurl` and Postman can discover services:

```go
import "google.golang.org/grpc/reflection"
if !isProd {
  reflection.Register(grpcServer)
}
```

## Performance

### Load Balancing

- **Client-side (L7, preferred for microservices):** use pick-first or round-robin with service discovery
- **Proxy-based (L4):** use Envoy or similar; required when clients are untrusted or in different networks

```go
// Client-side round-robin (Go)
conn, _ := grpc.Dial(
  "dns:///users.internal:443",
  grpc.WithDefaultServiceConfig(`{"loadBalancingPolicy":"round_robin"}`),
)
```

## Security

- Authenticate via token in metadata (`authorization: Bearer <token>`), validated in a server interceptor
- Use mTLS for service-to-service communication; TLS for client-to-gateway

```go
authFunc := func(ctx context.Context) (context.Context, error) {
  token, err := grpc_auth.AuthFromMD(ctx, "bearer")
  if err != nil { return nil, status.Errorf(codes.Unauthenticated, "missing token") }
  claims, err := validateToken(token)
  if err != nil { return nil, status.Errorf(codes.Unauthenticated, "invalid token") }
  return context.WithValue(ctx, claimsKey, claims), nil
}
```

## Error Codes and Status Model

Map domain errors to canonical gRPC status codes:

| Status Code | Use Case |
|-------------|---------|
| `OK` | Success |
| `NOT_FOUND` | Resource does not exist |
| `ALREADY_EXISTS` | Unique constraint violation |
| `INVALID_ARGUMENT` | Bad input from caller |
| `PERMISSION_DENIED` | Authenticated but not authorized |
| `UNAUTHENTICATED` | Missing or invalid credentials |
| `RESOURCE_EXHAUSTED` | Rate limit or quota exceeded |
| `DEADLINE_EXCEEDED` | Operation timed out |
| `UNAVAILABLE` | Service temporarily down (retriable) |
| `INTERNAL` | Unexpected server error |

Include rich error details using `google.rpc.Status`:

```go
import "google.golang.org/genproto/googleapis/rpc/errdetails"

st, _ := status.New(codes.InvalidArgument, "validation failed").
  WithDetails(&errdetails.BadRequest{
    FieldViolations: []*errdetails.BadRequest_FieldViolation{
      {Field: "email", Description: "invalid email format"},
    },
  })
return nil, st.Err()
```

## Backward Compatibility

- **Never reuse a field number** — once removed, mark it `reserved`
- **Never change a field's type** — add a new field instead
- New fields added to messages are optional by default in proto3 — safe to add
- Removing an RPC is a breaking change; deprecate with `option deprecated = true` first

```protobuf
message User {
  string id    = 1;
  string email = 2;
  // string old_name = 3;  // removed — keep reserved to prevent reuse
  reserved 3;
  reserved "old_name";
  string full_name = 4;
}
```

## Testing

```
# Unit tests
- Each RPC handler tested in isolation with mock dependencies
- Error path: assert correct status code + errdetails for each failure mode
- Interceptors: auth rejects missing token with UNAUTHENTICATED

# Integration tests
- Use bufconn (in-process listener) to avoid network in CI
- Streaming: assert all messages received, cancel mid-stream, handle error mid-stream

# Contract tests
- Proto schema: reserved fields and field numbers never recycled
- Breaking change detection: run buf breaking in CI against baseline schema
```

## Dos

- Always set a client-side deadline; propagate it through the call chain
- Use one `Request`/`Response` pair per RPC method
- Register the health check service on every gRPC server
- Validate all input in a server interceptor before it reaches handlers
- Use `reserved` for removed field numbers and names
- Enable server reflection in dev/staging; disable in production

## Don'ts

- Don't reuse field numbers — ever
- Don't use `string` for timestamps, IDs, or enums — use proper types
- Don't swallow `context.Canceled` or `DEADLINE_EXCEEDED` — propagate them
- Don't skip TLS in any environment, including staging
- Don't return `INTERNAL` for client input errors — use `INVALID_ARGUMENT`
- Don't implement custom health check endpoints — use the standard protocol
- Don't enable server reflection in production (information disclosure risk)
