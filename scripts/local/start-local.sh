#!/bin/bash

echo "Starting local development services..."

# Start Docker services
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 5

# Create local DynamoDB table
aws dynamodb create-table \
  --table-name slack2backlog-idempotency-dev \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:8000 \
  2>/dev/null || echo "Table already exists"

# Create local SQS queues
aws sqs create-queue \
  --queue-name slack2backlog-event-queue-dev \
  --endpoint-url http://localhost:4566 \
  2>/dev/null || echo "Queue already exists"

aws sqs create-queue \
  --queue-name slack2backlog-dlq-dev \
  --endpoint-url http://localhost:4566 \
  2>/dev/null || echo "DLQ already exists"

echo "Local services are ready!"
echo ""
echo "To start SAM local API:"
echo "  sam local start-api"
echo ""
echo "To invoke a function directly:"
echo "  sam local invoke EventIngestFunction -e events/slack-event.json"
