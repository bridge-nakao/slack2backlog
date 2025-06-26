# IAM セキュリティガイド

## 概要

このドキュメントでは、slack2backlogプロジェクトのIAMセキュリティ設定とベストプラクティスについて説明します。

## IAMロール構成

### Lambda実行ロール

#### 1. Event Ingest Function Role
- **ロール名**: `slack2backlog-event-ingest-role-{stage}`
- **用途**: Slackイベント受信とSQS送信

##### 最小権限セット
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:region:account:slack2backlog-event-queue-*"
    },
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:region:account:secret:slack2backlog-slack-secrets-*"
    }
  ]
}
```

#### 2. Backlog Worker Function Role
- **ロール名**: `slack2backlog-backlog-worker-role-{stage}`
- **用途**: SQS処理とBacklog API呼び出し

##### 最小権限セット
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ChangeMessageVisibility"
      ],
      "Resource": "arn:aws:sqs:region:account:slack2backlog-event-queue-*"
    },
    {
      "Effect": "Allow",
      "Action": "sqs:SendMessage",
      "Resource": "arn:aws:sqs:region:account:slack2backlog-dlq-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query"
      ],
      "Resource": "arn:aws:dynamodb:region:account:table/slack2backlog-idempotency-*"
    }
  ]
}
```

## セキュリティベストプラクティス

### 1. 最小権限の原則

#### DO ✅
- リソースレベルで権限を制限
- 環境（dev/prod）ごとに別のロール
- 定期的な権限レビュー

#### DON'T ❌
- ワイルドカード（*）の過度な使用
- 管理者権限の付与
- 未使用の権限の放置

### 2. 条件付きアクセス

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "lambda:InvokeFunction",
    "Resource": "*",
    "Condition": {
      "StringEquals": {
        "aws:RequestedRegion": "ap-northeast-1"
      },
      "IpAddress": {
        "aws:SourceIp": ["10.0.0.0/8"]
      }
    }
  }]
}
```

### 3. クロスサービス認証

#### API Gateway → Lambda
```yaml
ApiGatewayInvokePolicy:
  Type: AWS::Lambda::Permission
  Properties:
    FunctionName: !Ref EventIngestFunction
    Action: lambda:InvokeFunction
    Principal: apigateway.amazonaws.com
    SourceArn: !Sub 'arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${SlackApi}/*/*'
```

#### SQS → Lambda
```yaml
SQSInvokePolicy:
  Type: AWS::Lambda::Permission
  Properties:
    FunctionName: !Ref BacklogWorkerFunction
    Action: lambda:InvokeFunction
    Principal: sqs.amazonaws.com
    SourceArn: !GetAtt EventQueue.Arn
```

## 監査とモニタリング

### CloudTrail設定
```bash
# IAM API呼び出しの監視
aws cloudtrail create-trail \
  --name slack2backlog-iam-trail \
  --s3-bucket-name audit-bucket \
  --event-selectors '[{
    "ReadWriteType": "All",
    "IncludeManagementEvents": true,
    "DataResources": [{
      "Type": "AWS::IAM::Role",
      "Values": ["arn:aws:iam::*:role/slack2backlog-*"]
    }]
  }]'
```

### Access Advisor活用
```bash
# 最終アクセス情報の取得
aws iam generate-service-last-accessed-details \
  --arn arn:aws:iam::account:role/slack2backlog-event-ingest-role-prod

# レポート取得
aws iam get-service-last-accessed-details \
  --job-id job-id-from-above
```

### CloudWatch Alarms
```yaml
UnusualIAMActivityAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    MetricName: IAMPolicyChanges
    Namespace: CloudTrailMetrics
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 1
    Threshold: 1
    ComparisonOperator: GreaterThanOrEqualToThreshold
```

## トラブルシューティング

### 権限エラーのデバッグ

#### 1. エラーログの確認
```bash
# Lambda関数のエラーログ
aws logs filter-log-events \
  --log-group-name /aws/lambda/function-name \
  --filter-pattern "AccessDenied"
```

#### 2. IAM Policy Simulator
```bash
# 権限のシミュレーション
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::account:role/role-name \
  --action-names dynamodb:PutItem \
  --resource-arns arn:aws:dynamodb:region:account:table/table-name
```

#### 3. AssumeRole失敗
```javascript
// Trust Relationshipの確認
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
```

## 定期的なセキュリティレビュー

### チェックリスト

- [ ] 未使用の権限を削除
- [ ] ワイルドカード使用の見直し
- [ ] クロスアカウントアクセスの確認
- [ ] MFAの必須化（管理作業時）
- [ ] ロール名の命名規則遵守
- [ ] タグによるリソース管理

### 自動化ツール

#### 1. AWS Config Rules
```yaml
RequiredTags:
  Type: AWS::Config::ConfigRule
  Properties:
    ConfigRuleName: required-tags-iam-roles
    Source:
      Owner: AWS
      SourceIdentifier: REQUIRED_TAGS
    Scope:
      ComplianceResourceTypes:
        - AWS::IAM::Role
    InputParameters:
      tag1Key: Environment
      tag2Key: Application
```

#### 2. カスタムスクリプト
```bash
# 90日以上未使用の権限を検出
./scripts/generate-least-privilege-policy.sh role-name 90
```

## インシデント対応

### 不正アクセス検知時

1. **即座にロールを無効化**
```bash
aws iam put-role-policy \
  --role-name compromised-role \
  --policy-name DenyAll \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*"
    }]
  }'
```

2. **CloudTrailで調査**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=UserName,AttributeValue=role-name \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
```

3. **新しいロールの作成とローテーション**

## まとめ

IAMセキュリティは継続的な取り組みです。定期的なレビューと改善により、セキュアな環境を維持しましょう。

### 関連ドキュメント
- [IAMポリシー仕様](./security/iam-policies.md)
- [AWS IAMベストプラクティス](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [最小権限の実装](https://aws.amazon.com/blogs/security/techniques-for-writing-least-privilege-iam-policies/)