---
name: implement-webhook
description: Implement a webhook handler with validation, idempotency, and retry handling
version: "1.0"
mode: standard
parameters:
  - name: direction
    description: Whether the webhook is incoming (received from external service) or outgoing (sent to external endpoint)
    type: enum
    required: true
    allowed_values: [incoming, outgoing]
  - name: event_type
    description: The event type this webhook handles (e.g., payment.completed, user.created, order.shipped)
    type: string
    required: true
  - name: payload_format
    description: Payload serialization format
    type: enum
    default: json
    allowed_values: [json, xml, form_urlencoded]
  - name: source_service
    description: The external service sending or receiving the webhook (e.g., Stripe, GitHub, Slack)
    type: string
    required: false
stages:
  skip: []
  focus:
    REVIEWING:
      review_agents: [fg-410-code-reviewer, fg-411-security-reviewer]
review:
  focus_categories: ["SEC-*", "ARCH-*", "TEST-*", "CONTRACT-*"]
  min_score: 90
scoring:
  critical_weight: 20
  warning_weight: 5
acceptance_criteria:
  - "GIVEN a valid {{event_type}} webhook payload WHEN received THEN the handler processes it and returns 200/202"
  - "GIVEN an invalid payload WHEN received THEN the handler returns 400 with error details"
  - "GIVEN a duplicate delivery (same idempotency key) WHEN received THEN the handler returns 200 without reprocessing"
  - "GIVEN a webhook with invalid signature WHEN received THEN the handler returns 401/403"
  - "GIVEN the handler WHEN processing fails THEN the error is logged and an appropriate retry status is returned"
  - "Integration tests cover valid payload, invalid payload, duplicate delivery, and signature validation scenarios"
tags: [webhook, api, integration, events, async]
---

## Requirement Template

Implement {{#if (eq direction "incoming")}}an incoming{{else}}an outgoing{{/if}} webhook handler for **{{event_type}}** events{{#if source_service}} from/to **{{source_service}}**{{/if}}.

### Webhook Details
- **Direction:** {{direction}}
- **Event type:** {{event_type}}
- **Payload format:** {{payload_format}}
{{#if source_service}}
- **External service:** {{source_service}}
{{/if}}

### Requirements

{{#if (eq direction "incoming")}}
#### Incoming Webhook Handler
- Create a webhook endpoint at an appropriate URL path (e.g., `/webhooks/{{event_type | kebab-case}}`)
- Parse the {{payload_format}} payload and validate its structure
- Verify the webhook signature/secret using the project's standard mechanism
{{#if source_service}}
- Follow {{source_service}}'s webhook verification documentation
{{/if}}
- Process the event asynchronously if the operation is long-running (return 202 immediately, process in background)

#### Security
- Validate the webhook signature before any processing
- Reject payloads that exceed a reasonable size limit
- Log the raw payload for debugging but redact any sensitive fields (PII, secrets)
- Rate-limit the webhook endpoint to prevent abuse
{{else}}
#### Outgoing Webhook Sender
- Create a service that sends {{payload_format}} payloads to a configurable target URL
- Include a signature header for the receiving service to verify authenticity
- Implement exponential backoff retry logic (3 retries: 1s, 5s, 30s)
- Store webhook delivery attempts and their outcomes for audit

#### Reliability
- Queue outgoing webhooks for async delivery (do not block the triggering operation)
- Record delivery status (pending, success, failed, retrying) per webhook
- Provide a manual retry mechanism for failed deliveries
{{/if}}

#### Idempotency
- Include an idempotency key in each webhook (event ID or generated UUID)
- Track processed webhook IDs to detect and skip duplicate deliveries
- Idempotency window should match the retry policy (at least 24 hours)

#### Error Handling
- Distinguish between retryable errors (5xx, timeout) and permanent errors (4xx, validation)
- Log processing errors with the webhook ID and event type for correlation
- Return appropriate HTTP status codes: 200 (processed), 202 (accepted for async processing), 400 (bad payload), 401 (bad signature), 429 (rate limited)

#### Testing
- Integration tests cover: valid payload processing, invalid payload rejection, duplicate detection, signature validation
- Mock the external service for testing (do not make real HTTP calls in tests)
