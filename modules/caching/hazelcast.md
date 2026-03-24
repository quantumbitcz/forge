# Hazelcast — Distributed Caching Best Practices

## Overview

Hazelcast is an in-memory data grid providing distributed maps, queues, locks, and caches across
a JVM cluster. Use it for distributed caching with near-cache L1 acceleration, distributed locks
and semaphores, session clustering, and shared computation state. Compared to Redis, Hazelcast is
JVM-native, embedded-capable, and provides stronger consistency options via its CP subsystem.
Choose Hazelcast when you need distributed data structures, JVM affinity, or strong consistency
guarantees beyond what Redis offers.

## Architecture Patterns

### Distributed Map (IMap) — Primary Cache Structure
```java
HazelcastInstance hz = Hazelcast.newHazelcastInstance(config);
IMap<String, User> userMap = hz.getMap("users");

// Async get — non-blocking
CompletableFuture<User> future = userMap.getAsync("user-42").toCompletableFuture();

// Put with TTL
userMap.put("user-42", user, 5, TimeUnit.MINUTES);
// Put with max idle (evict if not accessed for N seconds)
userMap.put("user-42", user, 5, TimeUnit.MINUTES, 2, TimeUnit.MINUTES);
```

### Near Cache (L1 In-Process Cache)
Near cache stores a local copy of frequently accessed entries in the member's heap, eliminating
network round-trips for hot keys:
```java
NearCacheConfig nearCacheConfig = new NearCacheConfig("users")
    .setMaxIdleSeconds(120)
    .setTimeToLiveSeconds(300)
    .setInvalidateOnChange(true)   // invalidation messages on remote updates
    .setInMemoryFormat(InMemoryFormat.OBJECT)  // deserialized — fastest read, more heap
    .setEvictionConfig(new EvictionConfig()
        .setSize(50_000)
        .setEvictionPolicy(EvictionPolicy.LFU));

MapConfig mapConfig = new MapConfig("users").setNearCacheConfig(nearCacheConfig);
```
Near cache is most effective for read-heavy, rarely-mutated reference data. For frequently updated
maps, invalidation overhead can outweigh the benefit.

### Entry Processors (Atomic In-Place Updates)
```java
// Execute logic on the server where the entry lives — zero serialization of the value
userMap.executeOnKey("user-42", entry -> {
    User user = entry.getValue();
    user.incrementLoginCount();
    entry.setValue(user);
    return user.getLoginCount();
});
```
Entry processors run on the partition owner — no value serialization across the wire, and the
update is atomic without distributed locks for single-key operations.

### Distributed Locks (CP Subsystem)
```java
// CP subsystem provides Raft-based linearizable locks (requires 3+ CP members)
CPSubsystem cp = hz.getCPSubsystem();
FencedLock lock = cp.getLock("inventory-lock");
try {
    lock.lock();
    // critical section
} finally {
    lock.unlock();
}

// Bounded wait
if (lock.tryLock(10, TimeUnit.SECONDS)) {
    try { /* ... */ } finally { lock.unlock(); }
} else {
    throw new LockTimeoutException("Could not acquire lock in time");
}
```

### WAN Replication (Multi-Datacenter)
```xml
<wan-replication name="eu-to-us">
    <batch-publisher>
        <cluster-name>us-cluster</cluster-name>
        <target-endpoints>10.1.0.10:5701,10.1.0.11:5701</target-endpoints>
        <queue-capacity>100000</queue-capacity>
        <queue-full-behavior>THROW_EXCEPTION</queue-full-behavior>
        <acknowledge-type>ACK_ON_OPERATION_COMPLETE</acknowledge-type>
    </batch-publisher>
</wan-replication>
```

### Split-Brain Protection and Merge Policies
```java
SplitBrainProtectionConfig quorumConfig = new SplitBrainProtectionConfig()
    .setName("quorum-2")
    .setEnabled(true)
    .setMinimumClusterSize(2);  // writes rejected when cluster shrinks below 2

// Merge policy after split-brain healing
MergePolicyConfig mergePolicy = new MergePolicyConfig()
    .setPolicy(LatestUpdateMergePolicy.class.getName());  // or PassThroughMergePolicy, PutIfAbsentMergePolicy
```

## Configuration

```yaml
# hazelcast.yaml
hazelcast:
  network:
    port:
      port: 5701
    join:
      kubernetes:        # recommended for K8s deployments
        enabled: true
        namespace: production
        service-name: hazelcast-service
  cp-subsystem:
    cp-member-count: 3   # minimum 3 for Raft quorum; 0 disables CP
    session-heartbeat-interval-seconds: 5
  map:
    users:
      time-to-live-seconds: 300
      max-idle-seconds: 120
      eviction:
        eviction-policy: LFU
        max-size-policy: PER_NODE
        size: 100000
      backup-count: 1     # synchronous backups; increase for higher durability
```

## Performance

- Near cache is the single highest-impact optimization for read-heavy workloads — enable it on hot maps.
- Use `InMemoryFormat.OBJECT` in near cache for fastest reads (deserialized objects, more heap usage).
- Use `InMemoryFormat.BINARY` in the distributed map for less GC pressure on the owning member.
- Entry processors eliminate serialization overhead for read-modify-write operations.
- Partition awareness: co-locate related data using `PartitionAware` key wrappers to reduce network hops.
- Monitor via Management Center or JMX: watch `getOperationCount`, `putOperationCount`, `evictionCount`.

## Security

```yaml
hazelcast:
  security:
    enabled: true
    client-permissions:
      map:
        - name: "users"
          actions: [ read, put, remove ]
          endpoints: [ "10.0.0.*" ]
  tls:
    enabled: true
    factory-class-name: com.hazelcast.nio.ssl.BasicSSLContextFactory
    properties:
      javax.net.ssl.keyStore: /etc/hazelcast/keystore.jks
      javax.net.ssl.trustStore: /etc/hazelcast/truststore.jks
```
- Always enable TLS for member-to-member and client-to-member communication in production.
- Use security realms to authenticate clients — do not rely on network-level access control alone.

## Testing

```java
// Embedded Hazelcast for unit/integration tests (no Docker required)
@BeforeEach
void setUp() {
    Config config = new Config().setClusterName("test-cluster");
    hz = Hazelcast.newHazelcastInstance(config);
    userMap = hz.getMap("users");
}

@AfterEach
void tearDown() {
    hz.shutdown();
}

@Test
void nearCacheServesCachedValue() {
    userMap.put("u-1", testUser, 5, TimeUnit.MINUTES);
    User result = userMap.get("u-1");   // populates near cache
    User cached = userMap.get("u-1");   // served from near cache
    assertEquals(testUser, cached);
}
```

## Dos
- Enable near cache on maps accessed frequently from the same member — it eliminates network round-trips.
- Use the CP subsystem (Raft) for distributed locks and semaphores requiring linearizability.
- Set split-brain protection (`min-cluster-size`) on maps that must reject writes during partition.
- Use entry processors for atomic read-modify-write — avoid separate get → mutate → put cycles.
- Monitor Management Center; alert on eviction rate, near-cache invalidation rate, and WAN queue depth.

## Don'ts
- Don't use `ILock` (AP lock) for critical sections requiring strict linearizability — use CP `FencedLock`.
- Don't set `backup-count` to 0 in production — one backup protects against single-member failure.
- Don't enable near cache on frequently mutated maps — invalidation traffic can exceed the benefit.
- Don't store very large objects (> 1 MB) in IMap without measuring GC impact across all members.
- Don't use Hazelcast in embedded mode for microservices that scale independently — use client-server mode.
