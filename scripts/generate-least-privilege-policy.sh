#!/bin/bash

# Generate least privilege IAM policy based on CloudTrail events

set -e

echo "=== Generating Least Privilege Policy ==="

ROLE_NAME="${1}"
DAYS="${2:-7}"

if [ -z "$ROLE_NAME" ]; then
    echo "Usage: $0 <role-name> [days-to-analyze]"
    exit 1
fi

echo "Analyzing CloudTrail events for role: $ROLE_NAME"
echo "Looking back $DAYS days"
echo ""

# Get the role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null)

if [ -z "$ROLE_ARN" ]; then
    echo "Error: Role $ROLE_NAME not found"
    exit 1
fi

# Query CloudTrail for API calls made by this role
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_TIME=$(date -u -d "$DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)

echo "Querying CloudTrail events from $START_TIME to $END_TIME"
echo ""

# Get unique API calls
EVENTS=$(aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=UserName,AttributeValue="$ROLE_NAME" \
    --start-time "$START_TIME" \
    --end-time "$END_TIME" \
    --query 'Events[*].[EventName,Resources[0].ResourceName]' \
    --output text | sort -u)

if [ -z "$EVENTS" ]; then
    echo "No CloudTrail events found for this role"
    exit 1
fi

# Generate policy document
echo "Generating policy based on actual usage..."
echo ""

cat > "least-privilege-policy-$ROLE_NAME.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
