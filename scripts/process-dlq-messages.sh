#!/bin/bash

# DLQ message processor script

set -e

echo "=== Processing DLQ Messages ==="

STACK_NAME="${1:-slack2backlog}"
STAGE="${2:-dev}"
ACTION="${3:-view}"  # view, reprocess, or delete
REGION="${4:-ap-northeast-1}"

# Get DLQ URL
DLQ_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='DeadLetterQueueUrl'].OutputValue" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

if [ -z "$DLQ_URL" ]; then
    echo "Error: Could not find DLQ URL"
    exit 1
fi

EVENT_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='EventQueueUrl'].OutputValue" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

echo "DLQ URL: $DLQ_URL"
echo "Action: $ACTION"
echo ""

case "$ACTION" in
    "view")
        echo "Viewing DLQ messages..."
        MESSAGES=$(aws sqs receive-message \
            --queue-url "$DLQ_URL" \
            --max-number-of-messages 10 \
            --visibility-timeout 0 \
            --region $REGION)
        
        if [ -z "$MESSAGES" ] || [ "$(echo "$MESSAGES" | jq '.Messages | length')" -eq 0 ]; then
            echo "No messages in DLQ"
        else
            echo "$MESSAGES" | jq '.Messages[] | {
                MessageId,
                Body: (.Body | fromjson),
                Attributes
            }'
        fi
        ;;
        
    "reprocess")
        echo "Reprocessing DLQ messages..."
        while true; do
            MESSAGES=$(aws sqs receive-message \
                --queue-url "$DLQ_URL" \
                --max-number-of-messages 1 \
                --region $REGION)
            
            if [ -z "$MESSAGES" ] || [ "$(echo "$MESSAGES" | jq '.Messages | length')" -eq 0 ]; then
                echo "No more messages to reprocess"
                break
            fi
            
            MESSAGE=$(echo "$MESSAGES" | jq -r '.Messages[0]')
            BODY=$(echo "$MESSAGE" | jq -r '.Body')
            RECEIPT_HANDLE=$(echo "$MESSAGE" | jq -r '.ReceiptHandle')
            
            echo "Reprocessing message..."
            
            # Send back to main queue
            aws sqs send-message \
                --queue-url "$EVENT_QUEUE_URL" \
                --message-body "$BODY" \
                --region $REGION
            
            # Delete from DLQ
            aws sqs delete-message \
                --queue-url "$DLQ_URL" \
                --receipt-handle "$RECEIPT_HANDLE" \
                --region $REGION
            
            echo "Message reprocessed"
        done
        ;;
        
    "delete")
        echo "Deleting all DLQ messages..."
        aws sqs purge-queue \
            --queue-url "$DLQ_URL" \
            --region $REGION
        echo "DLQ purged"
        ;;
        
    *)
        echo "Usage: $0 [stack-name] [stage] [view|reprocess|delete] [region]"
        exit 1
        ;;
esac

echo ""
echo "=== DLQ processing complete ==="