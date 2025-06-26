# SQS Message Format Specification

## Event Queue Message Format

### Message Structure

Messages sent to the event queue follow this JSON structure:

```json
{
  "messageId": "unique-message-id",
  "timestamp": "2025-06-26T10:30:00Z",
  "source": "slack-event-ingest",
  "eventType": "slack.message",
  "data": {
    "slackEvent": {
      "type": "message",
      "channel": "C123ABC",
      "user": "U123ABC",
      "text": "Backlog登録希望 タスクの説明",
      "ts": "1234567890.123456",
      "team": "T123ABC"
    },
    "metadata": {
      "receivedAt": "2025-06-26T10:30:00Z",
      "apiGatewayRequestId": "request-id",
      "signature": "v0=...",
      "signatureTimestamp": "1234567890"
    }
  },
  "retryCount": 0
}
```

### Message Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| eventType | String | Type of event (e.g., "slack.message") |
| priority | Number | Message priority (1-5, default: 3) |
| source | String | Source of the message |
| version | String | Message format version |

### Processing Rules

1. **Message Deduplication**: Based on Slack event_id
2. **Message Ordering**: FIFO not guaranteed (standard queue)
3. **Visibility Timeout**: 60 seconds
4. **Max Receive Count**: 3 (before moving to DLQ)

## Dead Letter Queue Message Format

Messages in the DLQ maintain the same structure with additional error information:

```json
{
  "originalMessage": { /* Original message content */ },
  "errorInfo": {
    "errorType": "ProcessingError",
    "errorMessage": "Failed to create Backlog issue",
    "stackTrace": "...",
    "attemptCount": 3,
    "lastAttemptTime": "2025-06-26T10:35:00Z"
  },
  "dlqMetadata": {
    "sentToDlqAt": "2025-06-26T10:36:00Z",
    "originalQueueArn": "arn:aws:sqs:...",
    "receiveCount": 3
  }
}
```

## Best Practices

1. **Message Size**: Keep messages under 64KB for optimal performance
2. **Batching**: Send messages in batches of up to 10 for efficiency
3. **Error Handling**: Include comprehensive error context for DLQ messages
4. **Monitoring**: Set up alarms for queue depth and message age
5. **Retention**: DLQ messages retained for 14 days for investigation

## Message Flow

```
Slack Event → API Gateway → Lambda (event_ingest) → SQS Event Queue
                                                            ↓
                                                    Lambda (backlog_worker)
                                                            ↓
                                                    Success: Delete message
                                                    Failure: Retry (max 3)
                                                            ↓
                                                    After 3 failures: DLQ
```
