# Varnish Best Practices

## Overview
Varnish is an HTTP reverse-proxy cache (web accelerator) that sits in front of your web server and caches HTTP responses. Use it for caching API responses, static assets, and full-page HTML where TTL-based invalidation suffices. Varnish excels at handling massive read traffic with sub-millisecond response times. Avoid it for authenticated/personalized content without careful VCL logic, WebSocket connections, or when a CDN (Cloudflare, Fastly) provides equivalent functionality with less operational overhead.

## Architecture Patterns

**Basic VCL configuration:**
```vcl
vcl 4.1;

backend default {
    .host = "app";
    .port = "8080";
    .connect_timeout = 5s;
    .first_byte_timeout = 30s;
    .between_bytes_timeout = 5s;
    .probe = {
        .url = "/health";
        .interval = 5s;
        .timeout = 2s;
        .threshold = 3;
        .window = 5;
    }
}

sub vcl_recv {
    # Strip cookies for static assets
    if (req.url ~ "\.(css|js|png|jpg|gif|svg|woff2)$") {
        unset req.http.Cookie;
        return (hash);
    }

    # Cache API responses without auth
    if (req.url ~ "^/api/public/") {
        unset req.http.Cookie;
        return (hash);
    }

    # Never cache authenticated requests by default
    if (req.http.Authorization || req.http.Cookie ~ "session=") {
        return (pass);
    }
}

sub vcl_backend_response {
    # Cache public API for 5 minutes
    if (bereq.url ~ "^/api/public/") {
        set beresp.ttl = 5m;
        set beresp.grace = 30m;
        unset beresp.http.Set-Cookie;
    }

    # Cache static assets for 1 day
    if (bereq.url ~ "\.(css|js|png|jpg|gif|svg|woff2)$") {
        set beresp.ttl = 1d;
        set beresp.grace = 7d;
    }
}

sub vcl_deliver {
    # Debug header (remove in production)
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
}
```

**Cache invalidation (purge):**
```vcl
sub vcl_recv {
    if (req.method == "PURGE") {
        if (!client.ip ~ purge_acl) { return (synth(403, "Forbidden")); }
        return (purge);
    }
}

acl purge_acl {
    "10.0.0.0"/8;
    "172.16.0.0"/12;
}
```

### Anti-pattern — caching responses with `Set-Cookie` headers: Cached responses with `Set-Cookie` serve the same session cookie to all users, causing session hijacking. Always strip `Set-Cookie` from cached responses.

## Configuration

```yaml
# docker-compose.yml
varnish:
  image: varnish:7
  ports: ["80:80"]
  volumes: ["./default.vcl:/etc/varnish/default.vcl:ro"]
  command: >
    -a :80
    -s malloc,256m
    -p default_ttl=120
    -p default_grace=3600
```

## Performance

**Monitor cache hit ratio:**
```bash
varnishstat -1 | grep -E "MAIN.cache_hit|MAIN.cache_miss"
# Target: > 80% hit ratio for cacheable traffic
```

**Grace mode for availability:** Set `beresp.grace` to serve stale content during backend outages — users get slightly stale data instead of errors.

**Tune thread pools:** Adjust `thread_pool_min`, `thread_pool_max`, and `thread_pool_timeout` for your workload.

## Security

**Restrict management port (6082):** Never expose the Varnish CLI port to the internet — it allows arbitrary VCL changes and cache purging.

**ACLs for PURGE/BAN operations:** Restrict cache invalidation to trusted internal IPs only.

**Strip sensitive headers:**
```vcl
sub vcl_deliver {
    unset resp.http.X-Powered-By;
    unset resp.http.Server;
}
```

## Testing

```bash
# Test cache behavior
curl -sI http://localhost | grep X-Cache
# X-Cache: HIT or MISS
```

Use `varnishtest` (VTC files) for automated VCL testing:
```vtc
varnishtest "Cache static assets"
server s1 { rxreq; txresp -body "hello" } -start
varnish v1 -vcl+backend { } -start
client c1 { txreq -url "/style.css"; rxresp; expect resp.http.X-Cache == "MISS" } -run
client c2 { txreq -url "/style.css"; rxresp; expect resp.http.X-Cache == "HIT" } -run
```

## Dos
- Use grace mode (`beresp.grace`) to serve stale content during backend outages — improves availability.
- Strip `Set-Cookie` from cached responses — prevents session hijacking via shared cookies.
- Use `X-Cache: HIT/MISS` headers in development to debug caching behavior.
- Use ACLs to restrict PURGE requests to trusted internal IPs.
- Cache static assets with long TTLs and use cache-busting URLs (content hashes) for invalidation.
- Use health checks (`.probe`) to automatically remove unhealthy backends from the pool.
- Monitor cache hit ratio — target > 80% for cacheable traffic.

## Don'ts
- Don't cache responses with `Set-Cookie` headers — it serves the same cookie to all users.
- Don't cache authenticated responses without varying by user — use `Vary: Authorization` or pass to backend.
- Don't set TTLs too long without a purge mechanism — stale content frustrates users.
- Don't use Varnish for WebSocket connections — it doesn't support persistent connections.
- Don't skip `Vary` headers — without `Vary: Accept-Encoding`, gzipped and non-gzipped responses collide.
- Don't use `return(pass)` as a catch-all fix — understand why caching fails and fix the VCL logic.
- Don't expose the Varnish management port (6082) to the internet — it allows remote VCL changes.
