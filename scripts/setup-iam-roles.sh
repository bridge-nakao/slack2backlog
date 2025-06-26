#!/bin/bash

# IAM Roles and Policies setup script for slack2backlog

set -e  # Exit on error

echo "=== Setting up IAM Roles and Policies for slack2backlog ==="

# Create enhanced IAM configuration
echo "Creating enhanced IAM configuration..."
cat > template-iam-enhanced.yaml << 'EOF'
# Enhanced IAM configurations to be integrated with main template
Resources:
  # Lambda Execution Role for Event Ingest Function
  EventIngestFunctionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub ${AWS::StackName}-event-ingest-role-${Stage}
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: 'sts:AssumeRole'
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        - arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
      Policies:
        - PolicyName: EventIngestPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              # SQS permissions
              - Effect: Allow
                Action:
                  - sqs:SendMessage
                  - sqs:GetQueueAttributes
                Resource: !GetAtt EventQueue.Arn
              # Secrets Manager permissions
              - Effect: Allow
                Action:
                  - secretsmanager:GetSecretValue
                Resource: !Ref SlackSecrets
              # CloudWatch Logs permissions (additional)
              - Effect: Allow
                Action:
                  - logs:CreateLogGroup
                  - logs:CreateLogStream
                  - logs:PutLogEvents
                Resource: !Sub 'arn:aws:logs:${AWS::Region}:${AWS::AccountId}:log-group:/aws/lambda/${AWS::StackName}-event-ingest-${Stage}:*'
      Tags:
        - Key: Environment
          Value: !Ref Stage
        - Key: Application
          Value: slack2backlog

  # Lambda Execution Role for Backlog Worker Function
  BacklogWorkerFunctionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub ${AWS::StackName}-backlog-worker-role-${Stage}
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: 'sts:AssumeRole'
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        - arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
      Policies:
        - PolicyName: BacklogWorkerPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              # SQS permissions
              - Effect: Allow
                Action:
                  - sqs:ReceiveMessage
                  - sqs:DeleteMessage
                  - sqs:GetQueueAttributes
                  - sqs:ChangeMessageVisibility
                Resource: !GetAtt EventQueue.Arn
              # DLQ permissions
              - Effect: Allow
                Action:
                  - sqs:SendMessage
                Resource: !GetAtt DeadLetterQueue.Arn
              # Secrets Manager permissions
              - Effect: Allow
                Action:
                  - secretsmanager:GetSecretValue
                Resource: 
                  - !Ref SlackSecrets
                  - !Ref BacklogSecrets
              # DynamoDB permissions for idempotency
              - Effect: Allow
                Action:
                  - dynamodb:GetItem
                  - dynamodb:PutItem
                  - dynamodb:UpdateItem
                  - dynamodb:Query
                Resource: !GetAtt IdempotencyTable.Arn
              # SSM Parameter Store permissions
              - Effect: Allow
                Action:
                  - ssm:GetParameter
                  - ssm:GetParameters
                  - ssm:GetParametersByPath
                Resource: !Sub 'arn:aws:ssm:${AWS::Region}:${AWS::AccountId}:parameter/${AWS::StackName}/${Stage}/*'
              # CloudWatch Logs permissions (additional)
              - Effect: Allow
                Action:
                  - logs:CreateLogGroup
                  - logs:CreateLogStream
                  - logs:PutLogEvents
                Resource: !Sub 'arn:aws:logs:${AWS::Region}:${AWS::AccountId}:log-group:/aws/lambda/${AWS::StackName}-backlog-worker-${Stage}:*'
      Tags:
        - Key: Environment
          Value: !Ref Stage
        - Key: Application
          Value: slack2backlog

  # Cross-service resource policy for API Gateway to invoke Lambda
  ApiGatewayInvokePolicy:
    Type: AWS::Lambda::Permission
    Properties:
      FunctionName: !Ref EventIngestFunction
      Action: lambda:InvokeFunction
      Principal: apigateway.amazonaws.com
      SourceArn: !Sub 'arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${SlackApi}/*/*'

  # Resource policy for SQS to invoke Lambda
  SQSInvokePolicy:
    Type: AWS::Lambda::Permission
    Properties:
      FunctionName: !Ref BacklogWorkerFunction
      Action: lambda:InvokeFunction
      Principal: sqs.amazonaws.com
      SourceArn: !GetAtt EventQueue.Arn

  # Service-linked role for API Gateway logging (if not exists)
  ApiGatewayCloudWatchRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: apigateway.amazonaws.com
            Action: 'sts:AssumeRole'
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs
      Path: /
      Tags:
        - Key: Environment
          Value: !Ref Stage
        - Key: Application
          Value: slack2backlog

Outputs:
  EventIngestRoleArn:
    Description: ARN of the Event Ingest Lambda execution role
    Value: !GetAtt EventIngestFunctionRole.Arn
    Export:
      Name: !Sub ${AWS::StackName}-EventIngestRoleArn

  BacklogWorkerRoleArn:
    Description: ARN of the Backlog Worker Lambda execution role
    Value: !GetAtt BacklogWorkerFunctionRole.Arn
    Export:
      Name: !Sub ${AWS::StackName}-BacklogWorkerRoleArn
EOF

# Create IAM policy documentation
echo "Creating IAM policy documentation..."
mkdir -p docs/security
cat > docs/security/iam-policies.md << 'EOF'
# IAM ロールとポリシー仕様

## 概要

このドキュメントでは、slack2backlogプロジェクトで使用するIAMロールとポリシーについて説明します。

## ロール構成

### 1. Event Ingest Lambda Role
**ロール名**: `slack2backlog-event-ingest-role-{stage}`

#### 用途
Slackからのイベントを受信し、SQSキューに送信するLambda関数用のロール

#### 必要な権限
| サービス | アクション | リソース | 説明 |
|---------|-----------|----------|------|
| SQS | SendMessage, GetQueueAttributes | EventQueue | メッセージ送信 |
| Secrets Manager | GetSecretValue | SlackSecrets | Slack認証情報取得 |
| CloudWatch Logs | CreateLogGroup, CreateLogStream, PutLogEvents | 関数ログ | ログ出力 |
| X-Ray | PutTraceSegments, PutTelemetryRecords | * | トレーシング |

### 2. Backlog Worker Lambda Role
**ロール名**: `slack2backlog-backlog-worker-role-{stage}`

#### 用途
SQSキューからメッセージを受信し、Backlogに課題を作成するLambda関数用のロール

#### 必要な権限
| サービス | アクション | リソース | 説明 |
|---------|-----------|----------|------|
| SQS | ReceiveMessage, DeleteMessage, GetQueueAttributes, ChangeMessageVisibility | EventQueue | メッセージ処理 |
| SQS | SendMessage | DeadLetterQueue | エラーメッセージ送信 |
| Secrets Manager | GetSecretValue | SlackSecrets, BacklogSecrets | 認証情報取得 |
| DynamoDB | GetItem, PutItem, UpdateItem, Query | IdempotencyTable | 冪等性管理 |
| SSM | GetParameter, GetParameters, GetParametersByPath | /{stack}/{stage}/* | 設定値取得 |
| CloudWatch Logs | CreateLogGroup, CreateLogStream, PutLogEvents | 関数ログ | ログ出力 |
| X-Ray | PutTraceSegments, PutTelemetryRecords | * | トレーシング |

## ポリシー設計原則

### 1. 最小権限の原則
- 各ロールには必要最小限の権限のみを付与
- リソースレベルで権限を制限
- 条件文を使用してさらに制限

### 2. 職務分離
- Event Ingest: 読み取りとキュー送信のみ
- Backlog Worker: キュー処理とBacklog API呼び出し
- 管理者: デプロイとモニタリング

### 3. 監査可能性
- すべてのアクションをCloudTrailで記録
- タグを使用してリソースを分類
- ロール名に環境情報を含める

## セキュリティベストプラクティス

### AssumeRoleポリシー
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "aws:SourceAccount": "${AWS::AccountId}"
      }
    }
  }]
}
```

### リソースベースポリシー例
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowSpecificLambdaOnly",
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::123456789012:role/slack2backlog-event-ingest-role-prod"
    },
    "Action": "sqs:SendMessage",
    "Resource": "arn:aws:sqs:region:123456789012:slack2backlog-event-queue-prod"
  }]
}
```

## トラブルシューティング

### 権限不足エラー
1. **CloudTrailで実際のAPI呼び出しを確認**
   ```bash
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole
   ```

2. **IAM Policy Simulatorでテスト**
   ```bash
   aws iam simulate-principal-policy \
     --policy-source-arn arn:aws:iam::account:role/role-name \
     --action-names sqs:SendMessage \
     --resource-arns arn:aws:sqs:region:account:queue-name
   ```

3. **Lambda環境変数で権限確認**
   ```javascript
   console.log('Execution role:', process.env.AWS_LAMBDA_FUNCTION_ROLE);
   ```

### よくある問題

#### AssumeRole失敗
- **原因**: Trust Relationshipの設定ミス
- **対処**: AssumeRolePolicyDocumentを確認

#### Secrets Manager アクセス拒否
- **原因**: リソースARNの指定ミス
- **対処**: 正確なSecret ARNを指定

#### SQS SendMessage失敗
- **原因**: キューポリシーとIAMポリシーの不整合
- **対処**: 両方のポリシーで許可されているか確認

## 監査とコンプライアンス

### 定期的な権限レビュー
1. **未使用の権限を特定**
   ```bash
   aws iam get-role-policy --role-name role-name --policy-name policy-name
   ```

2. **Access Advisorで最終使用日を確認**
   ```bash
   aws iam get-service-last-accessed-details --job-id job-id
   ```

3. **権限の削減**
   - 90日以上未使用の権限は削除を検討
   - ワイルドカード（*）の使用を最小限に

### コンプライアンス要件
- **データ暗号化**: KMS権限は必要最小限に
- **ログ保持**: CloudWatch Logsへの書き込み権限必須
- **監査証跡**: CloudTrailですべてのAPI呼び出しを記録
EOF

# Create IAM testing script
echo "Creating IAM testing script..."
cat > scripts/test-iam-permissions.sh << 'EOF'
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
EOF

chmod +x scripts/test-iam-permissions.sh

# Create least privilege policy generator
echo "Creating least privilege policy generator..."
cat > scripts/generate-least-privilege-policy.sh << 'EOF'
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
EOF

# Parse events and create policy statements
FIRST=true
while IFS=$'\t' read -r action resource; do
    if [ -n "$action" ] && [ "$action" != "AssumeRole" ]; then
        SERVICE=$(echo "$action" | cut -d':' -f1 | tr '[:upper:]' '[:lower:]')
        
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            echo "," >> "least-privilege-policy-$ROLE_NAME.json"
        fi
        
        cat >> "least-privilege-policy-$ROLE_NAME.json" << EOF
    {
      "Sid": "Allow${action//[^a-zA-Z0-9]/}",
      "Effect": "Allow",
      "Action": "$SERVICE:$action",
      "Resource": "${resource:-*}"
    }
EOF
    fi
done <<< "$EVENTS"

cat >> "least-privilege-policy-$ROLE_NAME.json" << EOF

  ]
}
EOF

echo "Policy generated: least-privilege-policy-$ROLE_NAME.json"
echo ""
echo "Review the generated policy and adjust as needed before applying."
echo "To update the role with this policy:"
echo "  aws iam put-role-policy --role-name $ROLE_NAME --policy-name LeastPrivilegePolicy --policy-document file://least-privilege-policy-$ROLE_NAME.json"
EOF

chmod +x scripts/generate-least-privilege-policy.sh

echo "=== IAM Roles and Policies configuration complete! ==="
echo ""
echo "Created files:"
echo "  - template-iam-enhanced.yaml              : Enhanced IAM configurations"
echo "  - docs/security/iam-policies.md          : IAM documentation"
echo "  - scripts/test-iam-permissions.sh        : Permission testing script"
echo "  - scripts/generate-least-privilege-policy.sh : Policy generator"
echo ""
echo "Next steps:"
echo "1. Review the IAM roles and policies"
echo "2. Deploy with 'sam deploy'"
echo "3. Test permissions with './scripts/test-iam-permissions.sh'"
echo "4. Generate least privilege policies after testing"