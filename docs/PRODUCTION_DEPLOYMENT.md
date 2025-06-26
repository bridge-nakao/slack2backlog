# 本番環境デプロイガイド

## 概要

このドキュメントでは、slack2backlogアプリケーションを本番AWS環境にデプロイする手順を説明します。

## 前提条件

- AWSアカウントへのアクセス権限
- AWS CLI設定済み
- SAM CLIインストール済み
- 本番用のSlack AppとBacklogプロジェクト設定済み

## 1. AWS環境の準備

### 1.1 IAMロールの作成

#### Lambda実行ロール

以下の権限を持つIAMロールを作成します：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:*:*:slack2backlog-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/slack2backlog-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:slack2backlog-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ],
      "Resource": "*"
    }
  ]
}
```

### 1.2 S3バケットの作成

SAMアーティファクト用のS3バケットを作成：

```bash
# バケット名は一意である必要があります
aws s3api create-bucket \
  --bucket slack2backlog-sam-artifacts-$(aws sts get-caller-identity --query Account --output text) \
  --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1
```

### 1.3 Secrets Managerの設定

#### Slack認証情報

```bash
aws secretsmanager create-secret \
  --name slack2backlog-slack-secrets \
  --description "Slack credentials for slack2backlog" \
  --secret-string '{
    "bot_token": "xoxb-your-bot-token",
    "signing_secret": "your-signing-secret"
  }'
```

#### Backlog認証情報

```bash
aws secretsmanager create-secret \
  --name slack2backlog-backlog-secrets \
  --description "Backlog credentials for slack2backlog" \
  --secret-string '{
    "api_key": "your-api-key",
    "space_id": "your-space-id"
  }'
```

## 2. デプロイの実行

### 2.1 初回デプロイ（ガイド付き）

```bash
# 本番環境用の設定でデプロイ
sam deploy --guided --config-env prod
```

以下の項目を設定します：

```
Stack Name [slack2backlog-prod]: slack2backlog-prod
AWS Region [ap-northeast-1]: ap-northeast-1
Parameter Environment [production]: production
Parameter SlackSigningSecret []: slack2backlog-slack-secrets
Parameter SlackBotToken []: slack2backlog-slack-secrets
Parameter BacklogApiKey []: slack2backlog-backlog-secrets
Parameter BacklogSpace []: yourspace.backlog.com
Parameter BacklogProjectId []: 12345
Parameter BacklogIssueTypeId []: 67890
Parameter BacklogPriorityId [3]: 3
Confirm changes before deploy [y/N]: y
Allow SAM CLI IAM role creation [Y/n]: Y
Save arguments to configuration file [Y/n]: Y
SAM configuration file [samconfig.toml]: samconfig.toml
SAM configuration environment [prod]: prod
```

### 2.2 更新デプロイ

設定保存後は以下のコマンドで更新：

```bash
sam deploy --config-env prod
```

### 2.3 デプロイ確認

```bash
# スタックの状態確認
aws cloudformation describe-stacks \
  --stack-name slack2backlog-prod \
  --query 'Stacks[0].StackStatus'

# API Gateway URLの取得
aws cloudformation describe-stacks \
  --stack-name slack2backlog-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
  --output text
```

## 3. Slack Appの設定

### 3.1 Event Subscriptionsの設定

1. [Slack App管理画面](https://api.slack.com/apps)にアクセス
2. 対象のAppを選択
3. 「Event Subscriptions」を開く
4. Request URLに以下を設定：
   ```
   https://your-api-id.execute-api.ap-northeast-1.amazonaws.com/Prod/slack/events
   ```
5. 以下のBot Eventsを追加：
   - `message.channels`
   - `message.groups`
   - `message.im`
   - `message.mpim`

### 3.2 OAuth & Permissionsの設定

必要なBot Token Scopesを確認：
- `chat:write`
- `channels:history`
- `groups:history`
- `im:history`
- `mpim:history`

### 3.3 Slackワークスペースへのインストール

1. 「Install App」から対象ワークスペースにインストール
2. Bot User OAuth Tokenをコピー
3. Secrets Managerを更新

## 4. 動作確認手順

### 4.1 基本動作確認

1. **Slackでテストメッセージ送信**
   ```
   Backlog登録希望 テストタスク
   ```

2. **CloudWatch Logsで処理確認**
   ```bash
   # event_ingest関数のログ確認
   aws logs tail /aws/lambda/slack2backlog-prod-event-ingest --follow
   
   # backlog_worker関数のログ確認
   aws logs tail /aws/lambda/slack2backlog-prod-backlog-worker --follow
   ```

3. **Backlogで課題作成確認**
   - Backlogプロジェクトで新規課題が作成されていることを確認
   - Slackのスレッドに返信が投稿されていることを確認

### 4.2 エラー時の確認手順

#### SQSメッセージの確認

```bash
# キューのメッセージ数確認
aws sqs get-queue-attributes \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/YOUR_ACCOUNT/slack2backlog-prod-queue \
  --attribute-names ApproximateNumberOfMessages

# DLQのメッセージ確認
aws sqs receive-message \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/YOUR_ACCOUNT/slack2backlog-prod-dlq \
  --max-number-of-messages 1
```

#### DynamoDBの確認

```bash
# 処理済みイベントの確認
aws dynamodb scan \
  --table-name slack2backlog-prod-idempotency \
  --limit 10
```

### 4.3 メトリクスの確認

#### Lambda関数のメトリクス

```bash
# エラー率の確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=slack2backlog-prod-event-ingest \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## 5. 監視とアラート

### 5.1 CloudWatch Dashboard

CloudFormationで作成されたダッシュボードを確認：
```
https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=slack2backlog-dashboard
```

### 5.2 アラート通知

以下のアラートが設定されています：
- Lambda関数エラー（5エラー/5分）
- Lambda実行時間（平均3秒以上）
- API Gateway 5XXエラー（10エラー/5分）
- SQSメッセージ滞留（10分以上）

## 6. トラブルシューティング

### よくある問題と解決方法

#### 1. Slack署名検証エラー

**症状**: `Invalid Slack signature`エラー

**対処法**:
- Secrets Managerの`signing_secret`が正しいか確認
- リクエストヘッダーが正しく送信されているか確認

#### 2. Backlog API認証エラー

**症状**: Backlog課題が作成されない

**対処法**:
- APIキーの有効期限を確認
- プロジェクトIDと課題タイプIDが正しいか確認
- Backlog APIの利用制限を確認

#### 3. Lambda関数タイムアウト

**症状**: 関数が30秒でタイムアウト

**対処法**:
- 外部APIへの接続タイムアウトを調整
- Lambdaメモリサイズを増加（512MB推奨）

### ログ分析クエリ

CloudWatch Insights クエリ例：

```sql
-- エラーログの抽出
fields @timestamp, level, message, error.code, error.message
| filter level = "error"
| sort @timestamp desc
| limit 50

-- APIレスポンス時間の分析
fields @timestamp, api.name, api.operation, api.duration
| filter api.duration > 0
| stats avg(api.duration), max(api.duration), min(api.duration) by api.name
```

## 7. メンテナンス

### バージョンアップ

```bash
# 新バージョンのデプロイ
git checkout main
git pull origin main
sam build
sam deploy --config-env prod
```

### ロールバック

```bash
# 前のバージョンにロールバック
aws cloudformation cancel-update-stack --stack-name slack2backlog-prod

# または特定のバージョンにロールバック
git checkout tags/v1.0.0
sam build
sam deploy --config-env prod
```

## 8. セキュリティベストプラクティス

1. **最小権限の原則**
   - Lambda関数には必要最小限の権限のみ付与

2. **シークレット管理**
   - 認証情報は必ずSecrets Managerで管理
   - 定期的なローテーション

3. **監査ログ**
   - CloudTrailで全ての操作を記録
   - 定期的な監査

4. **ネットワークセキュリティ**
   - VPCエンドポイントの使用を検討
   - 必要に応じてプライベートサブネット配置