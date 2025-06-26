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
