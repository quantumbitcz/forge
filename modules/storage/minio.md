# MinIO — Object Storage Best Practices

## Overview

MinIO is a high-performance, S3-compatible object storage server designed for on-premises and
hybrid cloud deployments. It provides a drop-in S3 API replacement, making it ideal for local
development, self-hosted production, Kubernetes-native storage, and air-gapped environments
where managed cloud storage is not available. MinIO supports erasure coding for durability,
bucket notifications, versioning, and object locking — matching the core S3 feature set.

## Architecture Patterns

### Deployment Modes

**Single-node (development/testing):**
```bash
docker run -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  -v /data/minio:/data \
  quay.io/minio/minio server /data --console-address ":9001"
```

**Distributed mode (production — minimum 4 nodes for erasure coding):**
```bash
# On each node — same command, all nodes listed
minio server \
  http://minio-{1...4}.example.com/data{1...2} \
  --console-address ":9001"
```
Distributed MinIO uses erasure coding to tolerate up to N/2 - 1 drive failures. Minimum viable
production setup: 4 nodes with 1 drive each (EC:2 — tolerates 2 drive losses).

### S3-Compatible API (Drop-In Replacement)
```python
# boto3 pointed at MinIO
import boto3
s3 = boto3.client(
    "s3",
    endpoint_url="http://minio.example.com:9000",
    aws_access_key_id="your-access-key",
    aws_secret_access_key="your-secret-key"
)
# All standard S3 operations work unchanged
s3.create_bucket(Bucket="my-bucket")
s3.put_object(Bucket="my-bucket", Key="hello.txt", Body=b"hello")
```

### Bucket Notifications
```python
# Configure notifications to a webhook endpoint
s3.put_bucket_notification_configuration(
    Bucket="uploads",
    NotificationConfiguration={
        "QueueConfigurations": [{
            "Id": "upload-events",
            "QueueArn": "arn:minio:sqs::primary:webhook",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": { "Key": { "FilterRules": [
                { "Name": "prefix", "Value": "users/" },
                { "Name": "suffix", "Value": ".jpg" }
            ]}}
        }]
    }
)
```
MinIO supports webhook, NATS, Kafka, Redis, PostgreSQL, Elasticsearch as notification targets.
Configure targets in MinIO environment variables:
```bash
MINIO_NOTIFY_WEBHOOK_ENABLE_PRIMARY=on
MINIO_NOTIFY_WEBHOOK_ENDPOINT_PRIMARY=http://my-service:8080/events
MINIO_NOTIFY_WEBHOOK_AUTH_TOKEN_PRIMARY=secret-token
```

### Erasure Coding Configuration
MinIO automatically selects the erasure coding set based on the number of drives. To view:
```bash
mc admin info myminio   # shows erasure set size and parity drives
```
Set explicit parity via `MINIO_STORAGE_CLASS_STANDARD=EC:4` (4 parity drives out of N total).
Higher parity = more durability, less usable storage.

### ILM (Information Lifecycle Management)
```bash
mc ilm rule add myminio/logs \
  --expire-days 90 \
  --transition-days 30 \
  --transition-tier GLACIER_TIER

# Define a remote tier (e.g., transition cold data to S3)
mc admin tier add s3 myminio GLACIER_TIER \
  --bucket glacier-archive --prefix cold/ \
  --access-key AKI... --secret-key ...
```

### Versioning and Object Locking
```bash
# Enable versioning
mc version enable myminio/my-bucket

# Enable object locking (WORM — requires versioning)
mc retention set --default COMPLIANCE "365d" myminio/compliance-bucket

# Lock individual object version
mc retention set COMPLIANCE "2028-01-01" myminio/compliance-bucket/audit-log.json
```

### mc (MinIO Client) CLI
```bash
# Essential mc commands
mc alias set myminio http://minio.example.com:9000 ACCESS_KEY SECRET_KEY
mc ls myminio/my-bucket                       # list objects
mc cp local-file.pdf myminio/my-bucket/       # upload
mc cp myminio/my-bucket/report.pdf .          # download
mc rm myminio/my-bucket/old-file.txt          # delete
mc mirror ./local-dir myminio/my-bucket/      # sync directory to bucket
mc admin info myminio                          # cluster health
mc admin heal myminio/my-bucket               # trigger erasure healing
```

## Configuration

```bash
# Production environment variables
MINIO_ROOT_USER=<admin-user>           # do not use default "minioadmin"
MINIO_ROOT_PASSWORD=<strong-password>  # minimum 8 characters
MINIO_VOLUMES="/data{1...4}"           # drive paths for distributed mode
MINIO_SITE_NAME=production-cluster
MINIO_STORAGE_CLASS_STANDARD=EC:2      # 2 parity drives (N-2 usable)
MINIO_STORAGE_CLASS_RRS=EC:2
```

**TLS configuration:**
```bash
# Place certificates in ~/.minio/certs/
cp server.crt ~/.minio/certs/public.crt
cp server.key ~/.minio/certs/private.key
# MinIO auto-detects and enables TLS
```

## Performance

- Distributed MinIO with 4+ nodes saturates network bandwidth — network is the bottleneck.
- Use `mc mirror --parallel N` for parallel multi-object operations.
- Object size matters: MinIO performs best with objects > 128 KB. For smaller objects, consider
  batching or a key-value store.
- Enable `MINIO_CACHE_DRIVES` for frequently accessed objects to serve from local NVMe cache.

## Security

- Change the root credentials immediately after setup — default credentials are well-known.
- Enable TLS for all MinIO endpoints in production.
- Create per-service access keys with scoped IAM policies; do not use root credentials in apps:
  ```bash
  mc admin user add myminio app-user app-password
  mc admin policy attach myminio readwrite --user app-user
  ```
- Enable audit logging: `MINIO_AUDIT_WEBHOOK_ENABLE=on` with a target webhook.
- Use MinIO's LDAP/OIDC integration for enterprise SSO instead of local users.

## Testing

```python
# MinIO in Docker for integration tests (S3-compatible)
import boto3, subprocess, time

proc = subprocess.Popen(["docker", "run", "-p", "9000:9000",
    "-e", "MINIO_ROOT_USER=test", "-e", "MINIO_ROOT_PASSWORD=testtest",
    "quay.io/minio/minio", "server", "/data"])
time.sleep(2)  # wait for startup
s3 = boto3.client("s3", endpoint_url="http://localhost:9000",
                  aws_access_key_id="test", aws_secret_access_key="testtest")
s3.create_bucket(Bucket="test-bucket")
# run tests...
proc.terminate()
```
Prefer Testcontainers MinIO integration for proper lifecycle management in test suites.

## Dos
- Use distributed mode (4+ nodes) for production — single-node has no redundancy.
- Create per-service IAM users with least-privilege policies; never use root credentials in applications.
- Enable TLS and audit logging in all production deployments.
- Use bucket notifications for event-driven processing instead of polling.
- Use `mc admin heal` proactively after drive replacements to restore full erasure protection.

## Don'ts
- Don't expose the MinIO console (port 9001) to the public internet — restrict to admin network.
- Don't run single-node MinIO for production data without understanding that any drive failure is total loss.
- Don't use the default `minioadmin` credentials in any shared or production environment.
- Don't set erasure parity to EC:0 — it disables fault tolerance entirely.
- Don't use MinIO as a database — it is an object store; there are no atomic multi-object transactions.
