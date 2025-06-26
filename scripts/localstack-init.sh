#!/bin/bash
set -e

echo "Initializing LocalStack resources..."

# Wait for LocalStack to be ready
sleep 5

# Create SQS Queue
echo "Creating SQS Queue..."
awslocal sqs create-queue \
  --queue-name slack2backlog-queue \
  --attributes '{
    "VisibilityTimeout": "300",
    "MessageRetentionPeriod": "1209600",
    "ReceiveMessageWaitTimeSeconds": "20"
  }'

# Create DLQ
echo "Creating DLQ..."
awslocal sqs create-queue \
  --queue-name slack2backlog-dlq \
  --attributes '{
    "MessageRetentionPeriod": "1209600"
  }'

# Create Secrets
echo "Creating Slack secrets..."
awslocal secretsmanager create-secret \
  --name slack2backlog-slack-secrets \
  --secret-string '{
    "bot_token": "xoxb-test-token",
    "signing_secret": "test-signing-secret"
  }'

echo "Creating Backlog secrets..."
awslocal secretsmanager create-secret \
  --name slack2backlog-backlog-secrets \
  --secret-string '{
    "api_key": "test-api-key",
    "space_id": "test-space"
  }'

echo "LocalStack initialization complete!"