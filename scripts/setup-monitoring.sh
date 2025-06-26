#!/bin/bash

# Comprehensive monitoring setup for slack2backlog
# Sets up CloudWatch alarms, dashboards, and SNS notifications

set -e

echo "=== Setting up comprehensive monitoring for slack2backlog ==="

# Configuration
STACK_NAME="${1:-slack2backlog}"
ENVIRONMENT="${2:-production}"
ALARM_EMAIL="${3:-nakao@bridge.vc}"
REGION="${AWS_REGION:-ap-northeast-1}"

# Check prerequisites
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured"
    exit 1
fi

echo "Stack Name: $STACK_NAME"
echo "Environment: $ENVIRONMENT"
echo "Alarm Email: $ALARM_EMAIL"
echo "Region: $REGION"
echo ""

# Deploy monitoring stack
echo "1. Deploying monitoring CloudFormation stack..."
aws cloudformation deploy \
    --template-file cloudformation/monitoring.yaml \
    --stack-name "${STACK_NAME}-monitoring-${ENVIRONMENT}" \
    --parameter-overrides \
        ServiceName="${STACK_NAME}-${ENVIRONMENT}" \
        AlarmEmail="$ALARM_EMAIL" \
    --capabilities CAPABILITY_IAM \
    --region "$REGION"

echo "✓ Monitoring stack deployed"

# Get stack outputs
echo ""
echo "2. Getting stack outputs..."
TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}-monitoring-${ENVIRONMENT}" \
    --query 'Stacks[0].Outputs[?OutputKey==`AlarmTopicArn`].OutputValue' \
    --output text \
    --region "$REGION")

DASHBOARD_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}-monitoring-${ENVIRONMENT}" \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
    --output text \
    --region "$REGION")

echo "✓ SNS Topic ARN: $TOPIC_ARN"
echo "✓ Dashboard URL: $DASHBOARD_URL"

# Create additional custom alarms
echo ""
echo "3. Creating custom alarms..."

# DLQ Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${STACK_NAME}-${ENVIRONMENT}-dlq-messages" \
    --alarm-description "Messages in DLQ" \
    --metric-name ApproximateNumberOfMessagesVisible \
    --namespace AWS/SQS \
    --statistic Maximum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --evaluation-periods 1 \
    --alarm-actions "$TOPIC_ARN" \
    --dimensions Name=QueueName,Value="${STACK_NAME}-${ENVIRONMENT}-dlq" \
    --region "$REGION" 2>/dev/null || echo "DLQ alarm already exists or queue not found"

# DynamoDB Throttle Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${STACK_NAME}-${ENVIRONMENT}-dynamodb-throttles" \
    --alarm-description "DynamoDB throttling detected" \
    --metric-name UserErrors \
    --namespace AWS/DynamoDB \
    --statistic Sum \
    --period 300 \
    --threshold 5 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions "$TOPIC_ARN" \
    --dimensions Name=TableName,Value="${STACK_NAME}-${ENVIRONMENT}-idempotency" \
    --region "$REGION" 2>/dev/null || echo "DynamoDB alarm already exists or table not found"

# Secrets Manager Access Errors
aws cloudwatch put-metric-alarm \
    --alarm-name "${STACK_NAME}-${ENVIRONMENT}-secrets-errors" \
    --alarm-description "Secrets Manager access errors" \
    --metric-name 4XXError \
    --namespace AWS/SecretsManager \
    --statistic Sum \
    --period 300 \
    --threshold 5 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions "$TOPIC_ARN" \
    --region "$REGION" 2>/dev/null || echo "Secrets Manager alarm already exists"

echo "✓ Custom alarms created"

# Setup CloudWatch Logs Insights queries
echo ""
echo "4. Creating CloudWatch Logs Insights queries..."

# Create query for error analysis
cat > /tmp/error-analysis-query.json <<EOF
{
    "name": "${STACK_NAME}-${ENVIRONMENT}-error-analysis",
    "logGroupNames": [
        "/aws/lambda/${STACK_NAME}-${ENVIRONMENT}-event-ingest",
        "/aws/lambda/${STACK_NAME}-${ENVIRONMENT}-backlog-worker"
    ],
    "queryString": "fields @timestamp, @message, level, error.code, error.message | filter level = 'error' | stats count() by error.code | sort count desc"
}
EOF

# Create query for performance analysis
cat > /tmp/performance-query.json <<EOF
{
    "name": "${STACK_NAME}-${ENVIRONMENT}-performance",
    "logGroupNames": [
        "/aws/lambda/${STACK_NAME}-${ENVIRONMENT}-event-ingest",
        "/aws/lambda/${STACK_NAME}-${ENVIRONMENT}-backlog-worker"
    ],
    "queryString": "fields @timestamp, @duration, @type, @memorySize, @maxMemoryUsed | filter @type = 'REPORT' | stats avg(@duration), max(@duration), min(@duration), avg(@maxMemoryUsed/@memorySize*100) as avg_memory_percentage by bin(5m)"
}
EOF

echo "✓ CloudWatch Logs Insights queries prepared"

# Create monitoring documentation
echo ""
echo "5. Creating monitoring documentation..."
cat > docs/MONITORING_GUIDE.md <<'EOF'
# 監視・アラート設定ガイド

## 概要

このドキュメントでは、slack2backlogアプリケーションの監視とアラート設定について説明します。

## アーキテクチャ

### 監視コンポーネント

1. **CloudWatch Alarms**
   - Lambda関数のエラー率とレイテンシ
   - API Gatewayのエラー率
   - SQSキューの滞留メッセージ
   - DynamoDBのスロットリング

2. **CloudWatch Dashboard**
   - リアルタイムメトリクスの可視化
   - エラーログの集約表示
   - パフォーマンス分析

3. **SNS通知**
   - Email通知
   - Slack通知（オプション）

4. **CloudWatch Logs Insights**
   - エラー分析クエリ
   - パフォーマンス分析クエリ

## セットアップ手順

### 1. 自動セットアップ

```bash
# 本番環境の監視設定
./scripts/setup-monitoring.sh slack2backlog production your-email@example.com

# ステージング環境の監視設定
./scripts/setup-monitoring.sh slack2backlog staging your-email@example.com
```

### 2. 手動セットアップ

#### CloudFormationスタックのデプロイ

```bash
aws cloudformation deploy \
    --template-file cloudformation/monitoring.yaml \
    --stack-name slack2backlog-monitoring-prod \
    --parameter-overrides \
        ServiceName=slack2backlog-prod \
        AlarmEmail=your-email@example.com \
    --capabilities CAPABILITY_IAM
```

## アラート一覧

### Lambda関数アラート

| アラート名 | 説明 | 閾値 | 対応方法 |
|-----------|------|------|----------|
| lambda-errors | エラー率が高い | 5エラー/5分 | CloudWatch Logsでエラー詳細確認 |
| lambda-duration | 実行時間が長い | 平均3秒以上 | メモリ増設、コード最適化 |
| lambda-throttles | スロットリング発生 | 1回以上 | 同時実行数の上限確認 |

### API Gatewayアラート

| アラート名 | 説明 | 閾値 | 対応方法 |
|-----------|------|------|----------|
| api-4xx | クライアントエラー多発 | 10エラー/5分 | リクエスト内容確認 |
| api-5xx | サーバーエラー発生 | 1エラー以上 | Lambda関数のエラー確認 |
| api-latency | レスポンス遅延 | 平均1秒以上 | Lambda関数の処理確認 |

### SQSアラート

| アラート名 | 説明 | 閾値 | 対応方法 |
|-----------|------|------|----------|
| sqs-message-age | メッセージ滞留 | 最大10分以上 | Worker関数の処理確認 |
| dlq-messages | DLQにメッセージ | 1件以上 | 失敗メッセージの調査 |

### DynamoDBアラート

| アラート名 | 説明 | 閾値 | 対応方法 |
|-----------|------|------|----------|
| dynamodb-throttles | スロットリング | 5回/5分 | 読み書き容量の調整 |
| dynamodb-errors | システムエラー | 1回以上 | AWSサポート確認 |

## ダッシュボード

### アクセス方法

1. AWS CloudWatchコンソールを開く
2. ダッシュボード > `slack2backlog-dashboard`を選択

### ウィジェット構成

1. **Lambda関数メトリクス**
   - 呼び出し回数
   - エラー数
   - 実行時間

2. **API Gatewayメトリクス**
   - リクエスト数
   - 4XXエラー
   - 5XXエラー

3. **SQSキューメトリクス**
   - 送信メッセージ数
   - 受信メッセージ数
   - 可視メッセージ数

4. **最近のエラーログ**
   - エラーレベルのログ表示

## CloudWatch Logs Insights

### よく使うクエリ

#### エラー分析

```sql
fields @timestamp, level, message, error.code, error.message
| filter level = "error"
| stats count() by error.code
| sort count desc
```

#### パフォーマンス分析

```sql
fields @timestamp, @duration, @type, @memorySize, @maxMemoryUsed
| filter @type = "REPORT"
| stats avg(@duration), max(@duration), min(@duration),
        avg(@maxMemoryUsed/@memorySize*100) as avg_memory_percentage
by bin(5m)
```

#### 特定ユーザーの追跡

```sql
fields @timestamp, message, user.id, user.name
| filter user.id = "U1234567890"
| sort @timestamp desc
```

#### API呼び出し分析

```sql
fields @timestamp, api.name, api.operation, api.duration, api.status
| filter api.name = "backlog"
| stats count() by api.status
```

## アラート対応手順

### 1. Lambda関数エラー

```bash
# エラーログの確認
aws logs tail /aws/lambda/slack2backlog-prod-event-ingest --follow

# 最近のエラーを検索
aws logs filter-log-events \
    --log-group-name /aws/lambda/slack2backlog-prod-event-ingest \
    --filter-pattern '"[ERROR]"' \
    --start-time $(date -d '1 hour ago' +%s)000
```

### 2. API Gateway 5XXエラー

```bash
# X-Rayトレースの確認
aws xray get-trace-summaries \
    --time-range-type LastHour \
    --filter-expression 'responseCode >= 500'
```

### 3. SQSメッセージ滞留

```bash
# キューの状態確認
aws sqs get-queue-attributes \
    --queue-url https://sqs.region.amazonaws.com/account/queue-name \
    --attribute-names All

# DLQメッセージの確認
aws sqs receive-message \
    --queue-url https://sqs.region.amazonaws.com/account/dlq-name \
    --max-number-of-messages 10
```

## カスタムメトリクス

### 実装例

```javascript
// Lambda関数内でカスタムメトリクスを送信
const AWS = require('aws-sdk');
const cloudwatch = new AWS.CloudWatch();

async function putCustomMetric(metricName, value, unit = 'Count') {
    const params = {
        Namespace: 'slack2backlog',
        MetricData: [{
            MetricName: metricName,
            Value: value,
            Unit: unit,
            Timestamp: new Date(),
            Dimensions: [
                {
                    Name: 'Environment',
                    Value: process.env.ENVIRONMENT || 'dev'
                }
            ]
        }]
    };
    
    await cloudwatch.putMetricData(params).promise();
}

// 使用例
await putCustomMetric('BacklogIssuesCreated', 1);
await putCustomMetric('ProcessingTime', processingTime, 'Milliseconds');
```

## 通知のカスタマイズ

### Slack通知の追加

```bash
# SNS TopicにSlack通知を追加
aws sns subscribe \
    --topic-arn arn:aws:sns:region:account:slack2backlog-alarms \
    --protocol https \
    --notification-endpoint https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

### アラート条件の調整

```bash
# 閾値の変更
aws cloudwatch put-metric-alarm \
    --alarm-name slack2backlog-prod-lambda-errors \
    --threshold 10  # 5から10に変更
```

## トラブルシューティング

### アラームが発火しない

1. **メトリクスの確認**
   ```bash
   aws cloudwatch get-metric-statistics \
       --namespace AWS/Lambda \
       --metric-name Errors \
       --dimensions Name=FunctionName,Value=function-name \
       --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
       --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
       --period 300 \
       --statistics Sum
   ```

2. **アラーム状態の確認**
   ```bash
   aws cloudwatch describe-alarms \
       --alarm-names slack2backlog-prod-lambda-errors
   ```

### 通知が届かない

1. **SNS Subscription確認**
   ```bash
   aws sns list-subscriptions-by-topic \
       --topic-arn arn:aws:sns:region:account:slack2backlog-alarms
   ```

2. **Email確認**
   - 迷惑メールフォルダを確認
   - AWS通知メールの承認リンクをクリック

## ベストプラクティス

1. **アラート疲労の防止**
   - 重要度に応じた閾値設定
   - 一時的なスパイクを無視する評価期間設定

2. **定期的なレビュー**
   - 月次でアラート発火状況を確認
   - 閾値の調整

3. **ドキュメント化**
   - アラート対応手順を明文化
   - インシデント後の振り返り実施

4. **自動化**
   - 可能な限り自動復旧を実装
   - ランブックの作成
EOF

echo "✓ Monitoring documentation created"

# Summary
echo ""
echo "=========================================="
echo "Monitoring setup completed!"
echo "=========================================="
echo ""
echo "Dashboard URL: $DASHBOARD_URL"
echo "SNS Topic ARN: $TOPIC_ARN"
echo ""
echo "Next steps:"
echo "1. Check your email and confirm SNS subscription"
echo "2. Access the CloudWatch dashboard"
echo "3. Review docs/MONITORING_GUIDE.md for usage instructions"
echo ""
echo "To test alarms:"
echo "  aws sns publish --topic-arn '$TOPIC_ARN' --message 'Test alarm notification'"