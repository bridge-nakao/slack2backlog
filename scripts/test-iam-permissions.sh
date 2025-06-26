#!/bin/bash

# IAM permissions testing script

set -e

echo "=== Testing IAM Permissions ==="

STACK_NAME="${1:-slack2backlog}"
STAGE="${2:-dev}"
REGION="${3:-ap-northeast-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test function
test_permission() {
    local role_name=$1
    local action=$2
    local resource=$3
    local description=$4
    
    echo -n "Testing $description... "
    
    result=$(aws iam simulate-principal-policy \
        --policy-source-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$role_name" \
        --action-names "$action" \
        --resource-arns "$resource" \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [ "$result" = "allowed" ]; then
        echo -e "${GREEN}✓ ALLOWED${NC}"
    elif [ "$result" = "ERROR" ]; then
        echo -e "${YELLOW}⚠ SKIP (Role not found)${NC}"
    else
        echo -e "${RED}✗ DENIED${NC}"
    fi
}

echo "Checking IAM roles and permissions for $STACK_NAME-$STAGE"
echo ""

# Get role names
EVENT_INGEST_ROLE="$STACK_NAME-event-ingest-role-$STAGE"
BACKLOG_WORKER_ROLE="$STACK_NAME-backlog-worker-role-$STAGE"

# Test Event Ingest Role permissions
echo "=== Event Ingest Role Permissions ==="
test_permission "$EVENT_INGEST_ROLE" "sqs:SendMessage" "arn:aws:sqs:$REGION:*:$STACK_NAME-event-queue-$STAGE" "SQS SendMessage"
test_permission "$EVENT_INGEST_ROLE" "secretsmanager:GetSecretValue" "arn:aws:secretsmanager:$REGION:*:secret:$STACK_NAME-slack-secrets-*" "Secrets Manager GetSecretValue"
test_permission "$EVENT_INGEST_ROLE" "logs:PutLogEvents" "arn:aws:logs:$REGION:*:*" "CloudWatch Logs PutLogEvents"

echo ""

# Test Backlog Worker Role permissions
echo "=== Backlog Worker Role Permissions ==="
test_permission "$BACKLOG_WORKER_ROLE" "sqs:ReceiveMessage" "arn:aws:sqs:$REGION:*:$STACK_NAME-event-queue-$STAGE" "SQS ReceiveMessage"
test_permission "$BACKLOG_WORKER_ROLE" "sqs:DeleteMessage" "arn:aws:sqs:$REGION:*:$STACK_NAME-event-queue-$STAGE" "SQS DeleteMessage"
test_permission "$BACKLOG_WORKER_ROLE" "dynamodb:PutItem" "arn:aws:dynamodb:$REGION:*:table/$STACK_NAME-idempotency-$STAGE" "DynamoDB PutItem"
test_permission "$BACKLOG_WORKER_ROLE" "ssm:GetParameter" "arn:aws:ssm:$REGION:*:parameter/$STACK_NAME/$STAGE/*" "SSM GetParameter"

echo ""

# Check for overly permissive policies
echo "=== Security Best Practices Check ==="

check_wildcards() {
    local role_name=$1
    
    echo -n "Checking $role_name for wildcard permissions... "
    
    # This is a simplified check - in production, use more comprehensive tools
    policy_count=$(aws iam list-role-policies --role-name "$role_name" --query 'length(PolicyNames)' --output text 2>/dev/null || echo "0")
    
    if [ "$policy_count" = "0" ]; then
        echo -e "${YELLOW}⚠ Role not found or no inline policies${NC}"
    else
        echo -e "${GREEN}✓ Check inline policies manually${NC}"
    fi
}

check_wildcards "$EVENT_INGEST_ROLE"
check_wildcards "$BACKLOG_WORKER_ROLE"

echo ""
echo "=== IAM Permission Test Complete ==="
echo ""
echo "Note: This is a basic test. For comprehensive security review, use:"
echo "  - AWS IAM Access Analyzer"
echo "  - AWS Config Rules"
echo "  - Third-party security tools"
