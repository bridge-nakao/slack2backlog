#!/bin/bash
set -e

echo "🚀 Setting up local development environment..."

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting." >&2; exit 1; }
command -v sam >/dev/null 2>&1 || { echo "❌ SAM CLI is required but not installed. Aborting." >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "❌ Node.js is required but not installed. Aborting." >&2; exit 1; }

# Install dependencies
echo "📦 Installing npm dependencies..."
npm install

# Start Docker services
echo "🐳 Starting Docker services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Create DynamoDB table
echo "🗄️ Creating DynamoDB table..."
aws dynamodb create-table \
  --table-name slack2backlog-idempotency \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:8000 \
  --region ap-northeast-1 \
  2>/dev/null || echo "Table already exists"

# Create SQS queues using LocalStack
echo "📬 Creating SQS queues..."
aws sqs create-queue \
  --queue-name slack2backlog-queue \
  --attributes VisibilityTimeout=300,MessageRetentionPeriod=1209600,ReceiveMessageWaitTimeSeconds=20 \
  --endpoint-url http://localhost:4566 \
  --region ap-northeast-1 \
  2>/dev/null || echo "Queue already exists"

aws sqs create-queue \
  --queue-name slack2backlog-dlq \
  --attributes MessageRetentionPeriod=1209600 \
  --endpoint-url http://localhost:4566 \
  --region ap-northeast-1 \
  2>/dev/null || echo "DLQ already exists"

# Create secrets
echo "🔐 Creating secrets..."
aws secretsmanager create-secret \
  --name slack2backlog-slack-secrets \
  --secret-string '{"bot_token":"xoxb-test-token","signing_secret":"test-signing-secret"}' \
  --endpoint-url http://localhost:4566 \
  --region ap-northeast-1 \
  2>/dev/null || echo "Slack secrets already exist"

aws secretsmanager create-secret \
  --name slack2backlog-backlog-secrets \
  --secret-string '{"api_key":"test-api-key","space_id":"test-space"}' \
  --endpoint-url http://localhost:4566 \
  --region ap-northeast-1 \
  2>/dev/null || echo "Backlog secrets already exist"

# Build SAM application
echo "🔨 Building SAM application..."
sam build

echo ""
echo "✅ Local environment setup complete!"
echo ""
echo "📝 Next steps:"
echo "  1. Start SAM Local API: sam local start-api --env-vars env.json"
echo "  2. View DynamoDB data: http://localhost:8001"
echo "  3. Run tests: npm test"
echo ""
echo "🔗 Useful URLs:"
echo "  - DynamoDB Admin: http://localhost:8001"
echo "  - LocalStack: http://localhost:4566"
echo "  - SAM Local API: http://localhost:3000"