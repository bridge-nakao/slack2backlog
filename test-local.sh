#!/bin/bash

echo "🚀 Starting slack2backlog local test..."

# 1. Check if SAM is built
if [ ! -d ".aws-sam" ]; then
  echo "Building SAM application..."
  sam build
fi

# 2. Start SAM Local API
echo "Starting SAM Local API..."
sam local start-api --env-vars env.local.json &
SAM_PID=$!

# Wait for SAM to start
echo "Waiting for SAM Local to start..."
sleep 10

# 3. Test URL verification
echo ""
echo "Testing URL verification..."
curl -X POST http://localhost:3000/slack/events \
  -H "Content-Type: application/json" \
  -d '{"type":"url_verification","challenge":"test-123"}'
echo ""

# 4. Test message event
echo ""
echo "Testing message event..."
node scripts/test-with-correct-signature.js

# 5. Clean up
echo ""
echo "Press Ctrl+C to stop SAM Local..."
wait $SAM_PID