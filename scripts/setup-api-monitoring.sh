#!/bin/bash

# API Gateway monitoring setup

set -e

echo "=== Setting up API Gateway monitoring ==="

STACK_NAME="${1:-slack2backlog}"
STAGE="${2:-dev}"

# Create CloudWatch alarms
echo "Creating CloudWatch alarms..."

# 4XX Error Rate Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${STACK_NAME}-${STAGE}-4XX-Errors" \
    --alarm-description "Alert on high 4XX error rate" \
    --metric-name 4XXError \
    --namespace AWS/ApiGateway \
    --statistic Sum \
    --period 300 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --treat-missing-data notBreaching \
    --dimensions Name=ApiName,Value="${STACK_NAME}-api" Name=Stage,Value=$STAGE

# 5XX Error Rate Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${STACK_NAME}-${STAGE}-5XX-Errors" \
    --alarm-description "Alert on any 5XX errors" \
    --metric-name 5XXError \
    --namespace AWS/ApiGateway \
    --statistic Sum \
    --period 60 \
    --threshold 1 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --treat-missing-data notBreaching \
    --dimensions Name=ApiName,Value="${STACK_NAME}-api" Name=Stage,Value=$STAGE

# High Latency Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${STACK_NAME}-${STAGE}-High-Latency" \
    --alarm-description "Alert on high API latency" \
    --metric-name Latency \
    --namespace AWS/ApiGateway \
    --statistic Average \
    --period 300 \
    --threshold 1000 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --treat-missing-data notBreaching \
    --dimensions Name=ApiName,Value="${STACK_NAME}-api" Name=Stage,Value=$STAGE

echo "CloudWatch alarms created successfully!"
echo ""
echo "To view alarms:"
echo "  aws cloudwatch describe-alarms --alarm-name-prefix '${STACK_NAME}-${STAGE}'"