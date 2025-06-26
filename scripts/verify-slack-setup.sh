#!/bin/bash

# Slack App setup verification script
# Verifies that the Slack App is properly configured for slack2backlog

set -e

echo "=== Slack App Setup Verification ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if required environment variables or parameters are set
STACK_NAME="${1:-slack2backlog}"
ENVIRONMENT="${2:-production}"
REGION="${AWS_REGION:-ap-northeast-1}"

echo "Stack: $STACK_NAME-$ENVIRONMENT"
echo "Region: $REGION"
echo ""

# Function to check status
check_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        return 1
    fi
}

# 1. Check API Gateway URL
echo "1. Checking API Gateway URL..."
API_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME-$ENVIRONMENT" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [ -n "$API_URL" ]; then
    echo -e "${GREEN}✓${NC} API Gateway URL: $API_URL"
    echo "   Use this URL in Slack App configuration:"
    echo "   ${API_URL}slack/events"
else
    echo -e "${RED}✗${NC} API Gateway URL not found"
    echo "   Make sure the stack is deployed"
fi
echo ""

# 2. Check Secrets Manager
echo "2. Checking Secrets Manager configuration..."
SECRET_EXISTS=$(aws secretsmanager describe-secret \
    --secret-id "$STACK_NAME-slack-secrets" \
    --region "$REGION" &>/dev/null && echo "yes" || echo "no")

if [ "$SECRET_EXISTS" = "yes" ]; then
    echo -e "${GREEN}✓${NC} Slack secrets found in Secrets Manager"
    
    # Check if secrets contain required fields
    SECRET_VALUE=$(aws secretsmanager get-secret-value \
        --secret-id "$STACK_NAME-slack-secrets" \
        --query 'SecretString' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "{}")
    
    if echo "$SECRET_VALUE" | grep -q "bot_token" && echo "$SECRET_VALUE" | grep -q "signing_secret"; then
        echo -e "${GREEN}✓${NC} Required fields (bot_token, signing_secret) present"
    else
        echo -e "${YELLOW}!${NC} Some required fields might be missing"
        echo "   Required fields: bot_token, signing_secret"
    fi
else
    echo -e "${RED}✗${NC} Slack secrets not found in Secrets Manager"
    echo "   Create with: aws secretsmanager create-secret --name $STACK_NAME-slack-secrets"
fi
echo ""

# 3. Check Lambda Functions
echo "3. Checking Lambda functions..."
FUNCTIONS=("event-ingest" "backlog-worker")
for func in "${FUNCTIONS[@]}"; do
    FUNC_NAME="$STACK_NAME-$ENVIRONMENT-$func"
    FUNC_EXISTS=$(aws lambda get-function \
        --function-name "$FUNC_NAME" \
        --region "$REGION" &>/dev/null && echo "yes" || echo "no")
    
    if [ "$FUNC_EXISTS" = "yes" ]; then
        echo -e "${GREEN}✓${NC} Lambda function $FUNC_NAME exists"
        
        # Check environment variables
        ENV_VARS=$(aws lambda get-function-configuration \
            --function-name "$FUNC_NAME" \
            --query 'Environment.Variables' \
            --output json \
            --region "$REGION" 2>/dev/null || echo "{}")
        
        if [ "$func" = "event-ingest" ]; then
            if echo "$ENV_VARS" | grep -q "SLACK_SIGNING_SECRET"; then
                echo -e "  ${GREEN}✓${NC} SLACK_SIGNING_SECRET configured"
            else
                echo -e "  ${RED}✗${NC} SLACK_SIGNING_SECRET not configured"
            fi
        fi
        
        if [ "$func" = "backlog-worker" ]; then
            if echo "$ENV_VARS" | grep -q "SLACK_BOT_TOKEN"; then
                echo -e "  ${GREEN}✓${NC} SLACK_BOT_TOKEN configured"
            else
                echo -e "  ${RED}✗${NC} SLACK_BOT_TOKEN not configured"
            fi
        fi
    else
        echo -e "${RED}✗${NC} Lambda function $FUNC_NAME not found"
    fi
done
echo ""

# 4. Test API Gateway endpoint
echo "4. Testing API Gateway endpoint..."
if [ -n "$API_URL" ]; then
    echo "Testing URL verification endpoint..."
    RESPONSE=$(curl -s -X POST "${API_URL}slack/events" \
        -H "Content-Type: application/json" \
        -d '{"type":"url_verification","challenge":"test123"}' \
        -w "\n%{http_code}" || echo "000")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ] && [ "$BODY" = "test123" ]; then
        echo -e "${GREEN}✓${NC} URL verification endpoint working correctly"
    else
        echo -e "${RED}✗${NC} URL verification endpoint not responding correctly"
        echo "   HTTP Code: $HTTP_CODE"
        echo "   Response: $BODY"
    fi
else
    echo -e "${YELLOW}!${NC} Skipping API test (no URL found)"
fi
echo ""

# 5. Check CloudWatch Logs
echo "5. Checking CloudWatch Logs..."
LOG_GROUPS=(
    "/aws/lambda/$STACK_NAME-$ENVIRONMENT-event-ingest"
    "/aws/lambda/$STACK_NAME-$ENVIRONMENT-backlog-worker"
)

for log_group in "${LOG_GROUPS[@]}"; do
    LOG_EXISTS=$(aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" \
        --query "logGroups[?logGroupName=='$log_group'].logGroupName" \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    if [ -n "$LOG_EXISTS" ]; then
        echo -e "${GREEN}✓${NC} Log group exists: $log_group"
    else
        echo -e "${YELLOW}!${NC} Log group not found: $log_group"
    fi
done
echo ""

# 6. Generate Slack App manifest
echo "6. Generating Slack App manifest..."
if [ -n "$API_URL" ]; then
    MANIFEST_FILE="/tmp/slack-app-manifest-generated.yaml"
    sed "s|REPLACE_WITH_YOUR_API_GATEWAY_URL|${API_URL%/}|g" \
        scripts/slack-app-manifest.yaml > "$MANIFEST_FILE"
    
    echo -e "${GREEN}✓${NC} Manifest generated at: $MANIFEST_FILE"
    echo ""
    echo "   Use this manifest to create/update your Slack App at:"
    echo "   https://api.slack.com/apps"
    echo ""
    echo "   Request URL for Event Subscriptions:"
    echo "   ${API_URL}slack/events"
else
    echo -e "${YELLOW}!${NC} Cannot generate manifest without API Gateway URL"
fi
echo ""

# Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. If API Gateway URL is available, update Slack App with the generated manifest"
echo "2. Ensure Secrets Manager contains bot_token and signing_secret"
echo "3. Install the Slack App to your workspace"
echo "4. Test by sending 'Backlog登録希望 test' in a channel with the bot"
echo ""
echo "For detailed setup instructions, see: docs/SLACK_APP_SETUP_GUIDE.md"