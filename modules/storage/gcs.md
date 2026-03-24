# Google Cloud Storage — Best Practices

## Overview

Google Cloud Storage (GCS) is Google's unified object storage service offering high durability,
multi-region redundancy, and tight integration with Google Cloud services (BigQuery, Pub/Sub,
Cloud Functions, Dataflow). Use GCS for user uploads, ML training data, backups, static assets,
and event-driven pipelines. Like S3, GCS uses a flat key namespace — folders are a UI abstraction.
Prefer signed URLs for client-side access; never expose service account keys in frontend code.

## Architecture Patterns

### Uniform Bucket-Level Access (Recommended)
Disable legacy ACLs — use IAM exclusively for access control:
```bash
gcloud storage buckets create gs://my-bucket --uniform-bucket-level-access
# Retroactively enable on existing bucket:
gcloud storage buckets update gs://my-bucket --uniform-bucket-level-access
```
Uniform bucket-level access simplifies permission auditing and prevents ACL and IAM conflicts.
Once enabled, per-object ACLs are ignored — IAM controls everything.

### Signed URLs (V4)
```python
from google.cloud import storage
from datetime import timedelta

client = storage.Client()
bucket = client.bucket("my-private-bucket")
blob = bucket.blob(f"users/{user_id}/report.pdf")

# Signed download URL (V4 — required for requests from outside GCP)
signed_url = blob.generate_signed_url(
    version="v4",
    expiration=timedelta(hours=1),
    method="GET",
    response_disposition="attachment; filename=report.pdf"
)

# Signed upload URL (client uploads directly to GCS)
upload_url = blob.generate_signed_url(
    version="v4",
    expiration=timedelta(minutes=15),
    method="PUT",
    content_type="image/jpeg"
)
```
Use a service account with the `roles/storage.objectViewer` role for signed URL generation.
Never embed service account JSON credentials in frontend clients.

### Object Lifecycle Management
```json
{
  "lifecycle": {
    "rule": [
      {
        "action": { "type": "SetStorageClass", "storageClass": "NEARLINE" },
        "condition": { "age": 30, "matchesPrefix": ["logs/"] }
      },
      {
        "action": { "type": "SetStorageClass", "storageClass": "COLDLINE" },
        "condition": { "age": 90 }
      },
      {
        "action": { "type": "Delete" },
        "condition": { "age": 365, "isLive": false }   // delete old versions
      }
    ]
  }
}
```
Storage classes: Standard → Nearline (30-day min) → Coldline (90-day min) → Archive (365-day min).
Retrieval costs increase down the hierarchy — match class to access frequency.

### Pub/Sub Notifications
```bash
# Trigger a Pub/Sub message on every object creation in a prefix
gcloud storage buckets notifications create gs://my-uploads \
  --topic=projects/my-project/topics/upload-events \
  --event-types=OBJECT_FINALIZE \
  --object-prefix=users/
```
Pub/Sub notifications enable event-driven processing (image resizing, virus scanning, indexing)
without polling. `OBJECT_FINALIZE` fires after a complete, successful upload.

### Dual-Region and Multi-Region Buckets
```bash
# Multi-region bucket (highest durability, highest cost)
gcloud storage buckets create gs://my-global-bucket --location=us

# Dual-region bucket (lower latency than multi-region, turbo replication option)
gcloud storage buckets create gs://my-dr-bucket --location=us-east1+us-central1 \
  --rpo=ASYNC_TURBO   # replicate within 15 min RPO guarantee
```
Use multi-region for globally accessed static assets (CDN origin). Use dual-region for
disaster recovery with a defined RPO. Single-region is appropriate for cost-sensitive workloads
where regional failure is acceptable.

### Customer-Managed Encryption Keys (CMEK)
```bash
# Create a Cloud KMS key
gcloud kms keys create my-storage-key \
  --keyring=my-keyring --location=us-east1 --purpose=encryption

# Apply CMEK to a bucket (all objects encrypted with this key)
gcloud storage buckets update gs://my-bucket \
  --default-kms-key=projects/my-project/locations/us-east1/keyRings/my-keyring/cryptoKeys/my-storage-key
```
CMEK enables key revocation (effectively deleting all encrypted data) and audit logs for every
cryptographic operation via Cloud Audit Logs.

### Transfer Service (Large Migrations)
```bash
# Schedule a transfer from S3 to GCS
gcloud transfer jobs create \
  --source-agent-pool=projects/my-project/agentPools/default \
  --source-s3-bucket=source-bucket \
  --destination=gs://destination-bucket \
  --schedule-repeats-every=1d
```

## Configuration

**IAM roles (principle of least privilege):**
```
roles/storage.objectViewer     — read-only for signed URL generation
roles/storage.objectCreator    — write-only (upload without read or delete)
roles/storage.objectAdmin      — full object control (upload, download, delete)
roles/storage.admin            — bucket-level management (avoid for service accounts)
```

**Recommended bucket settings:**
- Enable uniform bucket-level access (required for new projects).
- Enable versioning for critical data buckets.
- Enable audit logging: `DATA_READ`, `DATA_WRITE` log types in Cloud Audit Logs.
- Set retention policy for compliance buckets (prevents deletion before retention period).

## Performance

- Use the XML API or JSON API with connection reuse for high-throughput workloads.
- Parallel composite uploads: split files > 150 MB into parallel parts using `gcloud storage cp --parallel-composite-upload-threshold`.
- Use `gsutil -m` or the transfer service for parallel multi-object operations.
- Read large objects with byte-range requests to parallelize downloads.
- Place buckets in the same region as the compute that accesses them to eliminate egress costs.

## Security

- Enable uniform bucket-level access on all new buckets — legacy ACLs are error-prone.
- Use Workload Identity for GKE workloads instead of service account key files.
- Enable object versioning and retention policies for compliance buckets.
- Use VPC Service Controls to restrict GCS access to within a defined security perimeter.
- Rotate signed URLs frequently — short expiry (15 min for uploads, 1 hour for downloads).

## Testing

```python
# Use the GCS emulator (fake-gcs-server) for integration tests
import subprocess, requests, google.cloud.storage

proc = subprocess.Popen(["fake-gcs-server", "-scheme", "http", "-port", "4443"])
client = storage.Client(project="test", client_options={"api_endpoint": "http://localhost:4443"})
bucket = client.create_bucket("test-bucket")
blob = bucket.blob("test.txt")
blob.upload_from_string("hello world")
assert blob.download_as_text() == "hello world"
proc.terminate()
```

## Dos
- Enable uniform bucket-level access — it simplifies IAM and eliminates ACL/IAM conflicts.
- Use V4 signed URLs for all client-direct access — V2 is deprecated and less secure.
- Apply lifecycle rules to automatically tier cold data to Nearline/Coldline/Archive.
- Use Pub/Sub notifications for event-driven processing instead of polling for new objects.
- Use Workload Identity (GKE) or Application Default Credentials to avoid service account key files.

## Don'ts
- Don't grant `roles/storage.admin` to application service accounts — use the narrowest role needed.
- Don't use allUsers or allAuthenticatedUsers ACLs unless serving a public static site.
- Don't store service account JSON keys in application code, Docker images, or source control.
- Don't choose Archive storage class for data accessed more than once a year — retrieval costs dominate.
- Don't skip versioning on buckets storing user data — unversioned deletion is irreversible.
