# AWS SQS / SNS — Messaging Conventions

## Overview

SQS is a fully managed queue; SNS is a fully managed pub/sub notification service. Use SQS for work queues
and decoupled microservices, SNS for fan-out to multiple downstream systems. Combine them (SNS → SQS
fan-out) to decouple publishers from the number of consumers. Avoid SQS FIFO queues unless strict ordering
is a hard requirement — they have lower throughput limits.

## Architecture Patterns

### FIFO vs Standard Queues

| Attribute | Standard | FIFO |
|-----------|----------|------|
| Throughput | Unlimited (soft limit: 3000 msg/s with batching) | 3000 msg/s with batching, 300 msg/s without |
| Ordering | Best-effort (at-least-once delivery) | Strict per message group (exactly-once within dedup window) |
| Deduplication | None | 5-minute window (content-based or explicit ID) |
| Use cases | High-volume telemetry, email notifications | Financial transactions, order state machines |

```python
# FIFO queue name must end with .fifo
sqs.create_queue(
    QueueName="orders.fifo",
    Attributes={
        "FifoQueue": "true",
        "ContentBasedDeduplication": "false",   # Prefer explicit deduplication IDs
        "DeduplicationScope": "messageGroup",   # Per group, not per queue
        "FifoThroughputLimit": "perMessageGroupId",
    }
)
```

### Message Deduplication
```python
# Explicit deduplication ID — deterministic from your business key
sqs.send_message(
    QueueUrl=fifo_queue_url,
    MessageBody=json.dumps(order_event),
    MessageGroupId=str(order_id),               # All events for one order are ordered
    MessageDeduplicationId=str(event_uuid),     # Idempotency key — deduplicated for 5 min
)

# Content-based deduplication (SHA-256 of body) — simpler but fragile if body varies
# Only enable when message bodies are truly deterministic
```

### Fan-Out via SNS Topics
```python
# One SNS publish → multiple SQS queues receive a copy
sns.create_topic(Name="order-events")

# Subscribe each downstream queue to the topic
sns.subscribe(
    TopicArn=topic_arn,
    Protocol="sqs",
    Endpoint=analytics_queue_arn,
)
sns.subscribe(
    TopicArn=topic_arn,
    Protocol="sqs",
    Endpoint=fulfillment_queue_arn,
)

# SQS queue policy must allow SNS to send messages
queue_policy = {
    "Statement": [{
        "Effect": "Allow", "Principal": {"Service": "sns.amazonaws.com"},
        "Action": "sqs:SendMessage",
        "Condition": {"ArnEquals": {"aws:SourceArn": topic_arn}}
    }]
}
```

### SNS Filter Policies
```python
# Subscribers only receive messages matching their filter — reduces processing overhead
sns.subscribe(
    TopicArn=topic_arn,
    Protocol="sqs",
    Endpoint=high_value_queue_arn,
    Attributes={
        "FilterPolicy": json.dumps({
            "order_value": [{"numeric": [">=", 1000]}],
            "region": ["eu-west-1", "eu-central-1"]
        }),
        "FilterPolicyScope": "MessageAttributes",  # or "MessageBody" for JSON body filtering
    }
)

# Publisher must set matching message attributes
sns.publish(
    TopicArn=topic_arn,
    Message=json.dumps(event),
    MessageAttributes={
        "order_value": {"DataType": "Number", "StringValue": "1500"},
        "region": {"DataType": "String", "StringValue": "eu-west-1"},
    }
)
```

### Visibility Timeout Tuning
```python
# Visibility timeout must exceed your maximum processing time
# Formula: visibility_timeout > p99_processing_time + safety_margin
sqs.create_queue(
    QueueName="orders",
    Attributes={"VisibilityTimeout": "120"}   # 2 minutes; extend dynamically if needed
)

# Extend mid-processing to prevent redelivery
sqs.change_message_visibility(
    QueueUrl=queue_url,
    ReceiptHandle=receipt_handle,
    VisibilityTimeout=120   # Reset clock
)
```

### Dead Letter Queues (DLQ)
```python
# Create DLQ first
dlq = sqs.create_queue(QueueName="orders-dlq")
dlq_arn = sqs.get_queue_attributes(
    QueueUrl=dlq["QueueUrl"], AttributeNames=["QueueArn"]
)["Attributes"]["QueueArn"]

# Attach to main queue with maxReceiveCount
sqs.create_queue(
    QueueName="orders",
    Attributes={
        "RedrivePolicy": json.dumps({
            "deadLetterTargetArn": dlq_arn,
            "maxReceiveCount": "3"   # Move to DLQ after 3 failed deliveries
        })
    }
)
```

### Batch Operations
```python
# Send up to 10 messages in one API call (reduces cost and latency)
sqs.send_message_batch(
    QueueUrl=queue_url,
    Entries=[
        {"Id": str(i), "MessageBody": json.dumps(msg)} for i, msg in enumerate(batch)
    ]
)

# Receive up to 10 messages per poll
response = sqs.receive_message(
    QueueUrl=queue_url,
    MaxNumberOfMessages=10,         # Max allowed
    WaitTimeSeconds=20,             # Long polling — always enable
    AttributeNames=["All"],
    MessageAttributeNames=["All"],
)
```

### Long Polling
```python
# Short polling (WaitTimeSeconds=0) wastes API calls and cost — never use in production
# Long polling waits up to 20 s for a message before returning empty
response = sqs.receive_message(
    QueueUrl=queue_url,
    WaitTimeSeconds=20,   # Always set to 20 in production
)

# Enable at queue level to cover all consumers by default
sqs.set_queue_attributes(
    QueueUrl=queue_url,
    Attributes={"ReceiveMessageWaitTimeSeconds": "20"}
)
```

## Configuration

```python
# Infrastructure as Code baseline (AWS CDK Python)
from aws_cdk import aws_sqs as sqs, aws_sns as sns, Duration

dlq = sqs.Queue(self, "OrdersDLQ", retention_period=Duration.days(14))
queue = sqs.Queue(
    self, "Orders",
    visibility_timeout=Duration.seconds(120),
    receive_message_wait_time=Duration.seconds(20),
    dead_letter_queue=sqs.DeadLetterQueue(max_receive_count=3, queue=dlq),
    encryption=sqs.QueueEncryption.KMS_MANAGED,
)
```

## Security

- Restrict `sqs:SendMessage` and `sqs:ReceiveMessage` to specific IAM roles — never use `*` principal.
- Enable SSE-KMS for queues that carry PII or payment data.
- Use VPC endpoints for SQS/SNS to avoid traffic traversing the public internet.
- Validate SNS subscription ARN in queue resource policies so only your topic can enqueue.

## Testing

```python
# LocalStack provides SQS + SNS locally — use via Testcontainers
from testcontainers.localstack import LocalStackContainer

with LocalStackContainer(image="localstack/localstack:3").with_services("sqs", "sns") as ls:
    boto3_session = boto3.Session(...)
    sqs_client = boto3_session.client("sqs", endpoint_url=ls.get_url())
    # Create queues, publish, consume, assert
```

## Dos

- Always enable long polling (`WaitTimeSeconds=20`) — it reduces empty receives by ~95%.
- Set DLQ with `maxReceiveCount=3–5` on every queue; alert on DLQ depth > 0.
- Use batch send/receive operations to lower cost and improve throughput.
- Set visibility timeout to at least 2× your p99 processing time.
- Use SNS filter policies to avoid fan-out noise reaching uninterested consumers.

## Don'ts

- Don't use FIFO queues for high-throughput pipelines — standard queues are 10× faster.
- Don't delete a message before processing completes — visibility timeout protects you, but delete only on success.
- Don't use short polling in production — it burns API quota and money.
- Don't omit `MessageDeduplicationId` on FIFO producers unless content-based dedup fits your use case exactly.
- Don't put SNS topics and their subscriber queues in different AWS accounts without explicit cross-account policies.
