#!/bin/bash

# API Gateway testing script

set -e

echo "=== Testing API Gateway endpoints ==="

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for this script. Please install it."
    exit 1
fi

# Get API endpoint from CloudFormation stack
STACK_NAME="slack2backlog"
STAGE="${1:-dev}"

echo "Getting API endpoint for stage: $STAGE"

# For local testing
if [ "$STAGE" == "local" ]; then
    API_ENDPOINT="http://localhost:3000"
else
    # Get from CloudFormation outputs
    API_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$API_ENDPOINT" ]; then
        echo "Error: Could not find API endpoint. Is the stack deployed?"
        exit 1
    fi
fi

echo "API Endpoint: $API_ENDPOINT"
echo ""

# Test 1: URL Verification
echo "Test 1: URL Verification Challenge"
echo "--------------------------------"
CHALLENGE="test_challenge_string_12345"
RESPONSE=$(curl -s -X POST $API_ENDPOINT \
    -H "Content-Type: application/json" \
    -H "X-Slack-Signature: v0=dummy_signature" \
    -H "X-Slack-Request-Timestamp: $(date +%s)" \
    -d "{\"type\":\"url_verification\",\"challenge\":\"$CHALLENGE\"}")

echo "Response: $RESPONSE"
echo ""

# Test 2: Message Event
echo "Test 2: Message Event"
echo "--------------------"
TIMESTAMP=$(date +%s)
EVENT_JSON=$(cat <<EOF
{
  "token": "verification_token",
  "team_id": "T123",
  "api_app_id": "A123",
  "event": {
    "type": "message",
    "channel": "C123",
    "user": "U123",
    "text": "Backlog登録希望 API Gateway Test",
    "ts": "$TIMESTAMP.000000"
  },
  "type": "event_callback",
  "event_id": "Ev123TEST",
  "event_time": $TIMESTAMP
}
