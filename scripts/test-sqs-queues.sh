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
