# Cloudflare R2 — Object Storage Best Practices

## Overview
Cloudflare R2 is an S3-compatible object storage service with zero egress fees. Use it for static asset hosting, user uploads, backups, and any storage workload where egress costs dominate (CDN-served content, public downloads, data distribution). R2 excels at cost optimization for read-heavy workloads. Avoid it for workloads requiring S3-specific features not yet in R2 (some lifecycle policies, object lock, cross-region replication), or when your entire stack is on AWS/GCP and a multi-cloud dependency adds complexity without cost savings.

## Architecture Patterns

**S3-compatible API access:**
```javascript
import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";

const r2 = new S3Client({
  region: "auto",
  endpoint: `https://${process.env.CF_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY
  }
});

// Upload
await r2.send(new PutObjectCommand({
  Bucket: "uploads",
  Key: `users/${userId}/${filename}`,
  Body: fileBuffer,
  ContentType: mimeType
}));
```

**Presigned URLs for direct client uploads:**
```javascript
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const url = await getSignedUrl(r2, new PutObjectCommand({
  Bucket: "uploads",
  Key: `users/${userId}/${filename}`,
  ContentType: mimeType
}), { expiresIn: 3600 });
// Return URL to client for direct upload — no proxy overhead
```

**Public bucket with custom domain (via Cloudflare):**
```
Bucket: assets → connected to assets.myapp.com via Cloudflare dashboard
Files served via Cloudflare CDN with zero egress fees
```

**Worker integration (edge processing):**
```javascript
export default {
  async fetch(request, env) {
    const object = await env.MY_BUCKET.get("data/config.json");
    if (!object) return new Response("Not found", { status: 404 });

    const headers = new Headers();
    headers.set("Content-Type", object.httpMetadata.contentType);
    headers.set("Cache-Control", "public, max-age=3600");
    return new Response(object.body, { headers });
  }
};
```

**Anti-pattern — using R2 for frequently mutated small objects:** R2 is optimized for write-once-read-many patterns. Frequent overwrites of small objects add latency compared to a database or cache.

## Configuration

**Wrangler (Cloudflare Workers) binding:**
```toml
# wrangler.toml
[[r2_buckets]]
binding = "MY_BUCKET"
bucket_name = "uploads"
```

**Terraform provisioning:**
```hcl
resource "cloudflare_r2_bucket" "uploads" {
  account_id = var.cloudflare_account_id
  name       = "uploads"
  location   = "ENAM"  # Eastern North America
}
```

**CORS configuration:**
```json
[{
  "AllowedOrigins": ["https://myapp.com"],
  "AllowedMethods": ["GET", "PUT", "HEAD"],
  "AllowedHeaders": ["Content-Type", "Authorization"],
  "MaxAgeSeconds": 3600
}]
```

## Performance

**Multipart upload for large files:**
```javascript
import { Upload } from "@aws-sdk/lib-storage";

const upload = new Upload({
  client: r2,
  params: { Bucket: "uploads", Key: key, Body: stream, ContentType: mimeType },
  partSize: 10 * 1024 * 1024,  // 10 MB parts
  leavePartsOnError: false
});
await upload.done();
```

**Cache-Control headers for CDN caching:**
```javascript
await r2.send(new PutObjectCommand({
  Bucket: "assets",
  Key: "images/hero.webp",
  Body: imageBuffer,
  ContentType: "image/webp",
  CacheControl: "public, max-age=31536000, immutable"
}));
```

**Use conditional requests (ETag/If-None-Match)** to avoid re-downloading unchanged objects.

## Security

**Scoped API tokens:** Create R2-specific API tokens with minimal permissions (read-only for public content, read-write for uploads).

**Never expose R2 credentials in client-side code.** Use presigned URLs or Cloudflare Workers for client access.

**Bucket access control:** R2 buckets are private by default. Use public bucket settings only for truly public content (CDN-served assets).

**Object-level encryption:** R2 encrypts all objects at rest by default (AES-256). For additional security, encrypt at the application layer before upload.

## Testing

```javascript
// Use MinIO as local S3-compatible mock
const testClient = new S3Client({
  region: "us-east-1",
  endpoint: "http://localhost:9000",
  credentials: { accessKeyId: "minioadmin", secretAccessKey: "minioadmin" },
  forcePathStyle: true
});

describe("Storage", () => {
  it("should upload and retrieve files", async () => {
    await testClient.send(new PutObjectCommand({ Bucket: "test", Key: "test.txt", Body: "hello" }));
    const response = await testClient.send(new GetObjectCommand({ Bucket: "test", Key: "test.txt" }));
    const body = await response.Body.transformToString();
    expect(body).toBe("hello");
  });
});
```

Use MinIO for local development and testing — it's S3-compatible and works with R2 client code. Test presigned URL generation and CORS configuration explicitly.

## Dos
- Use presigned URLs for client-side uploads — avoids proxying large files through your server.
- Set appropriate `Cache-Control` headers for CDN-served content — R2 + Cloudflare CDN is zero-egress.
- Use multipart upload for files > 100 MB — it provides resumability and parallelism.
- Use Cloudflare Workers for edge processing of R2 objects — eliminates origin server round trips.
- Use content-addressable keys (hash-based) for immutable assets — enables aggressive caching.
- Store R2 credentials in environment variables or a secrets manager.
- Use lifecycle rules to auto-delete temporary uploads after a retention period.

## Don'ts
- Don't expose R2 API credentials in client-side code — use presigned URLs or Workers.
- Don't use R2 for frequently mutated small objects — use a database or cache instead.
- Don't skip CORS configuration for browser-based uploads — presigned URLs require proper CORS headers.
- Don't assume all S3 features are available — check R2's compatibility docs for missing features.
- Don't store sensitive data without application-level encryption — R2's at-rest encryption uses provider-managed keys.
- Don't use path-style URLs in production — use virtual-hosted-style (`bucket.r2.cloudflarestorage.com`).
- Don't ignore R2's rate limits — Class A (writes) and Class B (reads) operations have different pricing and limits.
