#!/bin/bash
set -e

echo "🚀 Starting integration test environment..."

# Start Docker services
echo "📦 Starting Docker services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Initialize DynamoDB table
echo "🗄️ Creating DynamoDB table..."
aws dynamodb create-table \
  --table-name slack2backlog-idempotency \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:8000 \
  --region ap-northeast-1 \
  2>/dev/null || echo "Table already exists"

# Build SAM application
echo "🔨 Building SAM application..."
sam build

# Start SAM Local API Gateway
echo "🌐 Starting SAM Local API Gateway..."
sam local start-api \
  --env-vars env.json \
  --docker-network bridge \
  --host 0.0.0.0 \
  --port 3000 &

SAM_PID=$!

# Wait for SAM Local to start
echo "⏳ Waiting for SAM Local to start..."
sleep 10

# Run integration tests
echo "🧪 Running integration tests..."
npm test -- tests/integration/integration.test.js

# Capture test result
TEST_RESULT=$?

# Cleanup
echo "🧹 Cleaning up..."
kill $SAM_PID 2>/dev/null || true
docker-compose down

# Exit with test result
if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ Integration tests passed!"
else
    echo "❌ Integration tests failed!"
fi

exit $TEST_RESULT