#!/bin/bash

# SQS Queue setup script for slack2backlog

set -e  # Exit on error

echo "=== Setting up SQS Queues for slack2backlog ==="

# Create enhanced SQS configuration
echo "Creating enhanced SQS queue configuration..."
cat > template-sqs-enhanced.yaml << 'EOF'
# Enhanced SQS Queue configurations to be integrated with main template
Resources:
  # Standard Queue with enhanced settings
  EventQueue:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub ${AWS::StackName}-event-queue-${Stage}
      VisibilityTimeout: 60  # 60 seconds for Lambda processing
      MessageRetentionPeriod: 345600  # 4 days (in seconds)
      MaximumMessageSize: 262144  # 256 KB
      ReceiveMessageWaitTimeSeconds: 20  # Long polling enabled
      RedrivePolicy:
        deadLetterTargetArn: !GetAtt DeadLetterQueue.Arn
        maxReceiveCount: 3
      KmsMasterKeyId: alias/aws/sqs  # Server-side encryption
      Tags:
        - Key: Environment
          Value: !Ref Stage
        - Key: Application
          Value: slack2backlog

  # Dead Letter Queue with enhanced settings
  DeadLetterQueue:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub ${AWS::StackName}-dlq-${Stage}
      MessageRetentionPeriod: 1209600  # 14 days (maximum)
      MaximumMessageSize: 262144  # 256 KB
      KmsMasterKeyId: alias/aws/sqs
      Tags:
        - Key: Environment
          Value: !Ref Stage
        - Key: Application
          Value: slack2backlog
        - Key: Type
          Value: DLQ

  # Queue Policy for access control
  EventQueuePolicy:
    Type: AWS::SQS::QueuePolicy
    Properties:
      Queues:
        - !Ref EventQueue
      PolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Sid: AllowLambdaAccess
            Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action:
              - sqs:SendMessage
              - sqs:ReceiveMessage
              - sqs:DeleteMessage
              - sqs:GetQueueAttributes
            Resource: !GetAtt EventQueue.Arn
            Condition:
              ArnEquals:
                aws:SourceArn: 
                  - !GetAtt EventIngestFunction.Arn
                  - !GetAtt BacklogWorkerFunction.Arn

  # DLQ Policy
  DLQPolicy:
    Type: AWS::SQS::QueuePolicy
    Properties:
      Queues:
        - !Ref DeadLetterQueue
      PolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Sid: AllowSQSRedrivePolicy
            Effect: Allow
            Principal:
              Service: sqs.amazonaws.com
            Action:
              - sqs:SendMessage
            Resource: !GetAtt DeadLetterQueue.Arn
            Condition:
              ArnEquals:
                aws:SourceArn: !GetAtt EventQueue.Arn

  # CloudWatch Alarms for Queue monitoring
  EventQueueDepthAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: !Sub ${AWS::StackName}-${Stage}-EventQueue-Depth
      AlarmDescription: Alert when event queue has too many messages
      MetricName: ApproximateNumberOfMessagesVisible
      Namespace: AWS/SQS
      Statistic: Average
      Period: 300
      EvaluationPeriods: 1
      Threshold: 100
      ComparisonOperator: GreaterThanThreshold
      Dimensions:
        - Name: QueueName
          Value: !GetAtt EventQueue.QueueName
      TreatMissingData: notBreaching

  EventQueueAgeAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: !Sub ${AWS::StackName}-${Stage}-EventQueue-Age
      AlarmDescription: Alert when messages are too old in event queue
      MetricName: ApproximateAgeOfOldestMessage
      Namespace: AWS/SQS
      Statistic: Maximum
      Period: 300
      EvaluationPeriods: 1
      Threshold: 600  # 10 minutes
      ComparisonOperator: GreaterThanThreshold
      Dimensions:
        - Name: QueueName
          Value: !GetAtt EventQueue.QueueName
      TreatMissingData: notBreaching

  DLQDepthAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: !Sub ${AWS::StackName}-${Stage}-DLQ-Messages
      AlarmDescription: Alert when messages arrive in DLQ
      MetricName: ApproximateNumberOfMessagesVisible
      Namespace: AWS/SQS
      Statistic: Sum
      Period: 300
      EvaluationPeriods: 1
      Threshold: 1
      ComparisonOperator: GreaterThanOrEqualToThreshold
      Dimensions:
        - Name: QueueName
          Value: !GetAtt DeadLetterQueue.QueueName
      TreatMissingData: notBreaching

  # Dashboard for Queue monitoring
  QueueDashboard:
    Type: AWS::CloudWatch::Dashboard
    Properties:
      DashboardName: !Sub ${AWS::StackName}-${Stage}-queue-dashboard
      DashboardBody: !Sub |
        {
          "widgets": [
            {
              "type": "metric",
              "properties": {
                "metrics": [
                  ["AWS/SQS", "ApproximateNumberOfMessagesVisible", {"QueueName": "${EventQueue.QueueName}"}],
                  [".", "ApproximateNumberOfMessagesNotVisible", {"QueueName": "${EventQueue.QueueName}"}],
                  [".", "ApproximateNumberOfMessagesDelayed", {"QueueName": "${EventQueue.QueueName}"}]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS::Region}",
                "title": "Event Queue Messages"
              }
            },
            {
              "type": "metric",
              "properties": {
                "metrics": [
                  ["AWS/SQS", "ApproximateAgeOfOldestMessage", {"QueueName": "${EventQueue.QueueName}"}]
                ],
                "period": 300,
                "stat": "Maximum",
                "region": "${AWS::Region}",
                "title": "Message Age"
              }
            },
            {
              "type": "metric",
              "properties": {
                "metrics": [
                  ["AWS/SQS", "NumberOfMessagesSent", {"QueueName": "${EventQueue.QueueName}", "stat": "Sum"}],
                  [".", "NumberOfMessagesReceived", {"QueueName": "${EventQueue.QueueName}", "stat": "Sum"}],
                  [".", "NumberOfMessagesDeleted", {"QueueName": "${EventQueue.QueueName}", "stat": "Sum"}]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS::Region}",
                "title": "Queue Operations"
              }
            },
            {
              "type": "metric",
              "properties": {
                "metrics": [
                  ["AWS/SQS", "ApproximateNumberOfMessagesVisible", {"QueueName": "${DeadLetterQueue.QueueName}"}]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS::Region}",
                "title": "Dead Letter Queue"
              }
            }
          ]
        }

Outputs:
  EventQueueUrl:
    Description: URL of the event queue
    Value: !Ref EventQueue
    Export:
      Name: !Sub ${AWS::StackName}-EventQueueUrl

  EventQueueArn:
    Description: ARN of the event queue
    Value: !GetAtt EventQueue.Arn
    Export:
      Name: !Sub ${AWS::StackName}-EventQueueArn

  DeadLetterQueueUrl:
    Description: URL of the dead letter queue
    Value: !Ref DeadLetterQueue
    Export:
      Name: !Sub ${AWS::StackName}-DeadLetterQueueUrl

  DeadLetterQueueArn:
    Description: ARN of the dead letter queue
    Value: !GetAtt DeadLetterQueue.Arn
    Export:
      Name: !Sub ${AWS::StackName}-DeadLetterQueueArn
EOF

# Create SQS message format documentation
echo "Creating SQS message format documentation..."
mkdir -p docs/sqs
cat > docs/sqs/message-format.md << 'EOF'
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
EOF

# Create SQS testing script
echo "Creating SQS testing script..."
cat > scripts/test-sqs-queues.sh << 'EOF'
#!/bin/bash

# SQS Queue testing script

set -e

echo "=== Testing SQS Queues ==="

STACK_NAME="${1:-slack2backlog}"
STAGE="${2:-dev}"
REGION="${3:-ap-northeast-1}"

# Get queue URLs from CloudFormation outputs
echo "Getting queue URLs..."
EVENT_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='EventQueueUrl'].OutputValue" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

DLQ_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='DeadLetterQueueUrl'].OutputValue" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

if [ -z "$EVENT_QUEUE_URL" ]; then
    echo "Warning: Could not find queue URLs. Using local testing mode."
    EVENT_QUEUE_URL="http://localhost:4566/000000000000/slack2backlog-event-queue-dev"
    DLQ_URL="http://localhost:4566/000000000000/slack2backlog-dlq-dev"
fi

echo "Event Queue URL: $EVENT_QUEUE_URL"
echo "DLQ URL: $DLQ_URL"
echo ""

# Test 1: Send a test message
echo "Test 1: Sending test message to event queue"
TEST_MESSAGE=$(cat <<EOF
{
  "messageId": "test-$(date +%s)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": "test-script",
  "eventType": "slack.message",
  "data": {
    "slackEvent": {
      "type": "message",
      "channel": "C123TEST",
      "user": "U123TEST",
      "text": "Backlog登録希望 SQSテストメッセージ",
      "ts": "$(date +%s).000000"
    }
  }
}
EOF
)

MESSAGE_ID=$(aws sqs send-message \
    --queue-url "$EVENT_QUEUE_URL" \
    --message-body "$TEST_MESSAGE" \
    --message-attributes "eventType={StringValue=slack.message,DataType=String}" \
    --query 'MessageId' \
    --output text \
    --region $REGION)

echo "Message sent with ID: $MESSAGE_ID"
echo ""

# Test 2: Receive the message
echo "Test 2: Receiving message from queue"
RECEIVED=$(aws sqs receive-message \
    --queue-url "$EVENT_QUEUE_URL" \
    --max-number-of-messages 1 \
    --wait-time-seconds 5 \
    --region $REGION)

if [ -n "$RECEIVED" ]; then
    echo "Message received successfully"
    RECEIPT_HANDLE=$(echo "$RECEIVED" | jq -r '.Messages[0].ReceiptHandle')
    
    # Test 3: Delete the message
    echo ""
    echo "Test 3: Deleting message from queue"
    aws sqs delete-message \
        --queue-url "$EVENT_QUEUE_URL" \
        --receipt-handle "$RECEIPT_HANDLE" \
        --region $REGION
    echo "Message deleted successfully"
else
    echo "No message received (might have been processed by Lambda)"
fi

# Test 4: Check queue attributes
echo ""
echo "Test 4: Checking queue attributes"
ATTRIBUTES=$(aws sqs get-queue-attributes \
    --queue-url "$EVENT_QUEUE_URL" \
    --attribute-names All \
    --region $REGION)

echo "Queue Configuration:"
echo "$ATTRIBUTES" | jq '.Attributes | {
    VisibilityTimeout,
    MessageRetentionPeriod,
    MaximumMessageSize,
    ApproximateNumberOfMessages,
    RedrivePolicy: (.RedrivePolicy | fromjson)
}'

# Test 5: Check DLQ
echo ""
echo "Test 5: Checking Dead Letter Queue"
DLQ_ATTRIBUTES=$(aws sqs get-queue-attributes \
    --queue-url "$DLQ_URL" \
    --attribute-names ApproximateNumberOfMessages \
    --region $REGION)

DLQ_COUNT=$(echo "$DLQ_ATTRIBUTES" | jq -r '.Attributes.ApproximateNumberOfMessages')
echo "Messages in DLQ: $DLQ_COUNT"

if [ "$DLQ_COUNT" -gt "0" ]; then
    echo "Warning: There are messages in the DLQ that need investigation"
fi

echo ""
echo "=== SQS Queue tests complete ==="
EOF

chmod +x scripts/test-sqs-queues.sh

# Create DLQ message processor script
echo "Creating DLQ message processor..."
cat > scripts/process-dlq-messages.sh << 'EOF'
#!/bin/bash

# DLQ message processor script

set -e

echo "=== Processing DLQ Messages ==="

STACK_NAME="${1:-slack2backlog}"
STAGE="${2:-dev}"
ACTION="${3:-view}"  # view, reprocess, or delete
REGION="${4:-ap-northeast-1}"

# Get DLQ URL
DLQ_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='DeadLetterQueueUrl'].OutputValue" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

if [ -z "$DLQ_URL" ]; then
    echo "Error: Could not find DLQ URL"
    exit 1
fi

EVENT_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='EventQueueUrl'].OutputValue" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

echo "DLQ URL: $DLQ_URL"
echo "Action: $ACTION"
echo ""

case "$ACTION" in
    "view")
        echo "Viewing DLQ messages..."
        MESSAGES=$(aws sqs receive-message \
            --queue-url "$DLQ_URL" \
            --max-number-of-messages 10 \
            --visibility-timeout 0 \
            --region $REGION)
        
        if [ -z "$MESSAGES" ] || [ "$(echo "$MESSAGES" | jq '.Messages | length')" -eq 0 ]; then
            echo "No messages in DLQ"
        else
            echo "$MESSAGES" | jq '.Messages[] | {
                MessageId,
                Body: (.Body | fromjson),
                Attributes
            }'
        fi
        ;;
        
    "reprocess")
        echo "Reprocessing DLQ messages..."
        while true; do
            MESSAGES=$(aws sqs receive-message \
                --queue-url "$DLQ_URL" \
                --max-number-of-messages 1 \
                --region $REGION)
            
            if [ -z "$MESSAGES" ] || [ "$(echo "$MESSAGES" | jq '.Messages | length')" -eq 0 ]; then
                echo "No more messages to reprocess"
                break
            fi
            
            MESSAGE=$(echo "$MESSAGES" | jq -r '.Messages[0]')
            BODY=$(echo "$MESSAGE" | jq -r '.Body')
            RECEIPT_HANDLE=$(echo "$MESSAGE" | jq -r '.ReceiptHandle')
            
            echo "Reprocessing message..."
            
            # Send back to main queue
            aws sqs send-message \
                --queue-url "$EVENT_QUEUE_URL" \
                --message-body "$BODY" \
                --region $REGION
            
            # Delete from DLQ
            aws sqs delete-message \
                --queue-url "$DLQ_URL" \
                --receipt-handle "$RECEIPT_HANDLE" \
                --region $REGION
            
            echo "Message reprocessed"
        done
        ;;
        
    "delete")
        echo "Deleting all DLQ messages..."
        aws sqs purge-queue \
            --queue-url "$DLQ_URL" \
            --region $REGION
        echo "DLQ purged"
        ;;
        
    *)
        echo "Usage: $0 [stack-name] [stage] [view|reprocess|delete] [region]"
        exit 1
        ;;
esac

echo ""
echo "=== DLQ processing complete ==="
EOF

chmod +x scripts/process-dlq-messages.sh

echo "=== SQS Queue configuration complete! ==="
echo ""
echo "Created files:"
echo "  - template-sqs-enhanced.yaml     : Enhanced SQS configurations"
echo "  - docs/sqs/message-format.md     : Message format documentation"
echo "  - scripts/test-sqs-queues.sh     : Queue testing script"
echo "  - scripts/process-dlq-messages.sh : DLQ processor script"
echo ""
echo "Next steps:"
echo "1. Review the enhanced SQS configuration"
echo "2. Deploy with 'sam deploy'"
echo "3. Test queues with './scripts/test-sqs-queues.sh'"
echo "4. Monitor DLQ with './scripts/process-dlq-messages.sh'"