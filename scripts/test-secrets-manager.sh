#!/bin/bash

# Secrets Manager testing script

set -e

echo "=== Testing Secrets Manager ==="

STACK_NAME="${1:-slack2backlog}"
STAGE="${2:-dev}"
REGION="${3:-ap-northeast-1}"

# Get secret ARNs from CloudFormation outputs
echo "Getting secret ARNs..."
SLACK_SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='SlackSecretsArn'].OutputValue" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

BACKLOG_SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='BacklogSecretsArn'].OutputValue" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

if [ -z "$SLACK_SECRET_ARN" ]; then
    echo "Warning: Could not find secret ARNs. Using default names."
    SLACK_SECRET_ARN="$STACK_NAME-slack-secrets-$STAGE"
    BACKLOG_SECRET_ARN="$STACK_NAME-backlog-secrets-$STAGE"
fi

echo "Slack Secret: $SLACK_SECRET_ARN"
echo "Backlog Secret: $BACKLOG_SECRET_ARN"
echo ""

# Test 1: Describe secrets
echo "Test 1: Describing secrets"
echo "Slack secret metadata:"
aws secretsmanager describe-secret \
    --secret-id "$SLACK_SECRET_ARN" \
    --region $REGION \
    --query '{Name: Name, Description: Description, LastChangedDate: LastChangedDate}' \
    2>/dev/null || echo "Secret not found"

echo ""
echo "Backlog secret metadata:"
aws secretsmanager describe-secret \
    --secret-id "$BACKLOG_SECRET_ARN" \
    --region $REGION \
    --query '{Name: Name, Description: Description, LastChangedDate: LastChangedDate}' \
    2>/dev/null || echo "Secret not found"

# Test 2: Get secret values (only in test mode)
if [ "$4" = "--show-values" ]; then
    echo ""
    echo "Test 2: Getting secret values (TEST MODE)"
    echo "WARNING: This will display sensitive information!"
    echo ""
    
    echo "Slack secrets:"
    aws secretsmanager get-secret-value \
        --secret-id "$SLACK_SECRET_ARN" \
        --region $REGION \
        --query 'SecretString' \
        --output text 2>/dev/null | jq '.' || echo "Failed to retrieve"
    
    echo ""
    echo "Backlog secrets:"
    aws secretsmanager get-secret-value \
        --secret-id "$BACKLOG_SECRET_ARN" \
        --region $REGION \
        --query 'SecretString' \
        --output text 2>/dev/null | jq '.' || echo "Failed to retrieve"
fi

# Test 3: Check secret policies
echo ""
echo "Test 3: Checking resource policies"
aws secretsmanager get-resource-policy \
    --secret-id "$SLACK_SECRET_ARN" \
    --region $REGION \
    --query 'ResourcePolicy' \
    --output text 2>/dev/null | jq '.' || echo "No resource policy"

echo ""
echo "=== Secrets Manager tests complete ==="
