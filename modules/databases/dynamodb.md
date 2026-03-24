# DynamoDB Best Practices

## Overview
DynamoDB is a fully managed, serverless key-value and document database with single-digit millisecond latency at any scale. Use it when you need predictable low-latency access, automatic scaling, and minimal operational overhead for well-defined access patterns. Avoid DynamoDB when your access patterns are not known upfront, when you need ad-hoc queries across multiple attributes, or when you have complex relational data with many join patterns — the design cost is high and migrations are painful.

## Architecture Patterns

**Single-table design — one table for the entire application:**
```
PK (partition key)     SK (sort key)           Attributes
─────────────────────  ──────────────────────  ──────────────────────────────
USER#alice             PROFILE                 name, email, createdAt
USER#alice             ORDER#2026-03-01#001    total, status, items
USER#alice             ORDER#2026-03-01#002    total, status, items
ORDER#2026-03-01#001   ITEM#WIDGET-1           qty, price
```
Single-table design co-locates related entities in one partition, enabling retrieval of parent + children in a single `Query` call. Use a compound sort key pattern (`TYPE#timestamp#id`) for hierarchical relationships.

**GSI (Global Secondary Index) for alternate access patterns:**
```python
# Table: PK=USER#id, SK=ORDER#date#id
# GSI: PK=status, SK=createdAt  → query all PENDING orders sorted by date
table.query(
    IndexName="StatusByDate",
    KeyConditionExpression=Key("status").eq("PENDING") & Key("createdAt").begins_with("2026-03")
)
```
GSIs have their own capacity; provision or set them to on-demand independently.

**Sparse GSI for optional attributes:**
```
# Only items with 'expiresAt' attribute appear in the GSI
# Effectively filters out items without expiration automatically
```
If a GSI key attribute is absent from an item, that item is simply not indexed in the GSI — a powerful pattern for subset queries.

**DynamoDB Streams for event-driven processing:**
```python
# Lambda trigger on NEW_AND_OLD_IMAGES stream view
def handler(event, context):
    for record in event["Records"]:
        if record["eventName"] == "INSERT":
            process_new_order(record["dynamodb"]["NewImage"])
```

**Anti-pattern — hot partition key:** Using a timestamp or sequential counter as the partition key routes all writes to the same partition (limited to 1,000 WCU / 3,000 RCU per second). Add a random suffix (write sharding) or use a UUID-based key for high-write tables.

## Configuration

**On-demand vs provisioned capacity:**
```python
# On-demand: pay-per-request, auto-scales, best for unpredictable traffic
TableBillingMode = "PAY_PER_REQUEST"

# Provisioned with auto-scaling: lower cost at steady predictable load
ProvisionedThroughput = {
    "ReadCapacityUnits": 100,
    "WriteCapacityUnits": 50
}
# Always pair with auto-scaling policies for both read and write
```

**DynamoDB Accelerator (DAX) for read-heavy workloads:**
```python
# DAX is an in-memory cache in front of DynamoDB — microsecond reads
# Compatible API: swap DynamoDB client for DAX client
import amazondax
dax = amazondax.AmazonDaxClient(endpoints=["dax-cluster.abc.dax.us-east-1.amazonaws.com:8111"])
```
Only use DAX for strongly consistent read-heavy patterns. DAX does not cache `Query` with `FilterExpression` results efficiently.

**Point-in-time recovery (always enable):**
```python
table.update(BillingMode="PAY_PER_REQUEST",
             PointInTimeRecoverySpecification={"PointInTimeRecoveryEnabled": True})
```

## Performance

**Use `Query` over `Scan` for all application access patterns:**
```python
# FAST: targeted Query using partition key
table.query(KeyConditionExpression=Key("PK").eq("USER#alice") & Key("SK").begins_with("ORDER#"))

# SLOW: Scan reads every item — acceptable only for migrations, backups
table.scan(FilterExpression=Attr("status").eq("PENDING"))
```

**Projection expressions to reduce consumed capacity:**
```python
table.get_item(
    Key={"PK": "USER#alice", "SK": "PROFILE"},
    ProjectionExpression="email, #n",
    ExpressionAttributeNames={"#n": "name"}
)
```
Reading a 10 KB item when you need 100 bytes consumes the full item's RCUs.

**Batch operations for multi-item reads/writes:**
```python
# BatchGetItem: up to 100 items, parallel across partitions
dynamodb.batch_get_item(RequestItems={
    "MyTable": {"Keys": [{"PK": k} for k in keys]}
})
# BatchWriteItem: up to 25 writes in one call
```

**Exponential backoff for `ProvisionedThroughputExceededException`:** The AWS SDK retries automatically with jitter — never implement your own retry loop that ignores backoff.

## Security

**IAM least-privilege per microservice:**
```json
{
  "Effect": "Allow",
  "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"],
  "Resource": "arn:aws:dynamodb:us-east-1:123:table/MyTable",
  "Condition": {
    "ForAllValues:StringEquals": {
      "dynamodb:LeadingKeys": ["USER#${aws:PrincipalTag/userId}"]
    }
  }
}
```
Use `dynamodb:LeadingKeys` condition to restrict each service/user to their own partition.

**Encryption at rest:** DynamoDB encrypts all data at rest by default (AWS-managed key). For stricter compliance, use a customer-managed KMS key:
```python
SSESpecification={"Enabled": True, "SSEType": "KMS", "KMSMasterKeyId": "arn:aws:kms:..."}
```

**VPC Endpoint:** Route DynamoDB traffic through a VPC endpoint to avoid traversing the public internet — required for compliance workloads.

**Never log full item content in CloudWatch** — items may contain PII. Log only keys and operation metadata.

## Testing

Use **DynamoDB Local** (official AWS Docker image) for integration tests:
```java
@Container
static GenericContainer<?> dynamoLocal = new GenericContainer<>("amazon/dynamodb-local:latest")
    .withExposedPorts(8000)
    .withCommand("-jar DynamoDBLocal.jar -sharedDb -inMemory");

AmazonDynamoDB client = AmazonDynamoDBClientBuilder.standard()
    .withEndpointConfiguration(new AwsClientBuilder.EndpointConfiguration(
        "http://localhost:" + dynamoLocal.getMappedPort(8000), "us-east-1"))
    .build();
```
Create tables with the same `CreateTable` parameters as production (same key schema, GSIs). Test `Query` patterns rather than `Scan` — verifies your access pattern design works. Use `BatchWriteItem` to seed test data efficiently.

## Dos
- Design access patterns first, then design the table schema — there is no way to query DynamoDB ad-hoc efficiently after the fact.
- Use single-table design to co-locate related entities and avoid cross-table transactions.
- Enable Point-in-Time Recovery (PITR) on all production tables — recovery from accidental bulk deletes is otherwise impossible.
- Use sparse GSIs to implement conditional indexing on optional attributes.
- Use `TransactWriteItems` for operations that must be atomic across multiple items (e.g., order + inventory decrement).
- Set a TTL attribute for data that should expire — DynamoDB deletes expired items automatically without consuming write capacity.
- Tag all DynamoDB tables with environment, service, and cost-center tags for cost allocation.

## Don'ts
- Don't use sequential integers or timestamps as partition keys — they create hot partitions; use UUIDs or composite keys with sufficient cardinality.
- Don't rely on `Scan` in application code — it reads every item in the table, consumes full read capacity, and does not scale.
- Don't over-index with GSIs — each GSI replicates data and consumes separate capacity; limit to access patterns that cannot be served by the base table.
- Don't use `FilterExpression` as a substitute for proper key design — filters are applied after reading (and charging for) all matching items.
- Don't use `DescribeTable` or `ListTables` in hot paths — these are control-plane calls with separate rate limits.
- Don't put items larger than 400 KB in DynamoDB — store large blobs in S3 and keep only the reference in DynamoDB.
- Don't use strongly consistent reads (`ConsistentRead=True`) for every operation — they cost 2x RCUs; use eventual consistency for non-critical reads.
