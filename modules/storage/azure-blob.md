# Azure Blob Storage — Best Practices

## Overview

Azure Blob Storage is Microsoft's object storage service for unstructured data. It integrates
natively with Azure services (Event Grid, Service Bus, Functions, CDN, Data Factory) and supports
hot, cool, cold, and archive access tiers within a single storage account. Use Blob Storage for
user uploads, backups, static assets, data lake (ADLS Gen2), and compliance workloads requiring
immutability. Prefer SAS tokens or managed identity for access — never share storage account keys.

## Architecture Patterns

### Container Organization
```
Storage Account
├── containers/
│   ├── uploads/         # user-uploaded files (private)
│   ├── assets/          # public static assets (CDN-backed)
│   ├── backups/         # automated backups (private)
│   └── exports/         # generated reports (private, short TTL)
```
Storage accounts have a flat namespace — use containers as logical partitions. Name containers
with lowercase letters, numbers, and hyphens (3–63 characters).

### SAS Tokens — Service, Account, and User Delegation
```python
from azure.storage.blob import (
    BlobServiceClient, BlobSasPermissions,
    generate_blob_sas, UserDelegationKey
)
from datetime import datetime, timedelta, timezone

# User delegation SAS (preferred — no account key required)
blob_service = BlobServiceClient(account_url="https://myaccount.blob.core.windows.net",
                                 credential=DefaultAzureCredential())
delegation_key: UserDelegationKey = blob_service.get_user_delegation_key(
    key_start_time=datetime.now(timezone.utc),
    key_expiry_time=datetime.now(timezone.utc) + timedelta(hours=1)
)

sas_token = generate_blob_sas(
    account_name="myaccount",
    container_name="uploads",
    blob_name=f"users/{user_id}/avatar.jpg",
    user_delegation_key=delegation_key,
    permission=BlobSasPermissions(write=True, create=True),
    expiry=datetime.now(timezone.utc) + timedelta(minutes=15),
    content_type="image/jpeg"
)
upload_url = f"https://myaccount.blob.core.windows.net/uploads/users/{user_id}/avatar.jpg?{sas_token}"
```
User delegation SAS tokens are signed by Azure AD credentials, not storage account keys — they
can be revoked by revoking the underlying credential.

### Access Tiers (Hot / Cool / Cold / Archive)
```python
from azure.storage.blob import StandardBlobTier

# Set tier at upload time
blob_client.upload_blob(data, standard_blob_tier=StandardBlobTier.COOL)

# Change tier on existing blob
blob_client.set_standard_blob_tier(StandardBlobTier.ARCHIVE)

# Rehydrate from Archive (can take hours)
blob_client.set_standard_blob_tier(
    StandardBlobTier.HOT,
    rehydrate_priority=RehydratePriority.HIGH   # 1-hour SLA vs 15-hour standard
)
```
Tier selection: Hot (frequently accessed, highest cost per GB), Cool (infrequent, 30-day min),
Cold (rarely accessed, 90-day min), Archive (offline, 180-day min, hours to rehydrate).

### Lifecycle Management Rules
```json
{
  "rules": [
    {
      "name": "tier-and-delete-logs",
      "enabled": true,
      "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["logs/"] },
      "actions": {
        "baseBlob": {
          "tierToCool":    { "daysAfterModificationGreaterThan": 30 },
          "tierToArchive": { "daysAfterModificationGreaterThan": 90 },
          "delete":        { "daysAfterModificationGreaterThan": 365 }
        },
        "snapshot": { "delete": { "daysAfterCreationGreaterThan": 90 } }
      }
    }
  ]
}
```

### Immutability Policies (WORM)
```python
from azure.storage.blob import BlobImmutabilityPolicy, ImmutabilityPolicyMode

# Time-based immutability (version-level)
blob_client.set_immutability_policy(
    immutability_policy=BlobImmutabilityPolicy(
        expiry_time=datetime.now(timezone.utc) + timedelta(days=2555),
        policy_mode=ImmutabilityPolicyMode.LOCKED   # cannot be shortened after lock
    )
)
```
Immutability policies are required for SEC 17a-4, FINRA, CFTC compliance. Use `UNLOCKED` mode
during evaluation; switch to `LOCKED` for production compliance.

### Change Feed (Audit Log of All Operations)
```python
# Enable change feed on the storage account, then read events
change_feed_client = blob_service.get_change_feed_client()
for event in change_feed_client.list_changes(
    start_time=datetime(2026, 1, 1, tzinfo=timezone.utc)
):
    print(event.event_type, event.subject)   # BlobCreated, BlobDeleted, etc.
```
Change feed provides an ordered, durable log of all blob operations — useful for audit trails and
downstream synchronization without polling.

### Soft Delete (Accidental Deletion Recovery)
```python
# Enable soft delete (retention: 7 days) on the storage account
blob_service.set_service_properties(
    delete_retention_policy=RetentionPolicy(enabled=True, days=7),
    container_delete_retention_policy=RetentionPolicy(enabled=True, days=7)
)
```

## Configuration

**Managed identity (recommended for Azure-hosted services):**
```python
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

# No keys in code — uses managed identity in Azure, developer auth locally
client = BlobServiceClient(
    account_url="https://myaccount.blob.core.windows.net",
    credential=DefaultAzureCredential()
)
```

## Performance

- Use block blobs for large files — block parallel uploads via the `max_concurrency` parameter.
- Set `max_concurrency` on uploads: `blob_client.upload_blob(data, max_concurrency=8)`.
- Use CDN (Azure CDN or Front Door) in front of public containers to reduce latency and egress cost.
- Enable `transfer_size` tuning for SDK uploads: the default block size is 4 MB; increase to 64 MB
  for large files to reduce the number of HTTP requests.

## Security

- Disable storage account key access when managed identity is available:
  `az storage account update --allow-shared-key-access false`
- Enable Azure Defender for Storage to detect anomalous access patterns.
- Use private endpoints to prevent public internet access to storage accounts.
- Enable soft delete and versioning on all production containers.
- Grant RBAC roles (Storage Blob Data Reader/Contributor) instead of account key access.

## Testing

```python
# Azurite (official local emulator) for integration tests
from azure.storage.blob import BlobServiceClient

AZURITE_CONN_STR = "AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;DefaultEndpointsProtocol=http;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;"
client = BlobServiceClient.from_connection_string(AZURITE_CONN_STR)
client.create_container("test-container")
blob = client.get_blob_client("test-container", "test.txt")
blob.upload_blob(b"hello")
assert blob.download_blob().readall() == b"hello"
```

## Dos
- Use user delegation SAS tokens (Azure AD-backed) over account key-signed SAS tokens.
- Enable managed identity for all Azure-hosted services — eliminates key management.
- Set lifecycle rules to automatically tier cold data and delete expired blobs.
- Enable soft delete and change feed for data recovery and audit trail requirements.
- Use private endpoints in production to restrict blob access to the virtual network.

## Don'ts
- Don't share storage account keys — they grant full access to all containers; use RBAC + SAS.
- Don't skip soft delete — accidental blob deletion without it is permanent and unrecoverable.
- Don't store Archive-tier data you need to access more than once every 180 days — rehydration is slow and costly.
- Don't use container-level public access unless serving a static website with no sensitive content.
- Don't set SAS token expiry longer than the maximum session length — short expiry limits blast radius on theft.
