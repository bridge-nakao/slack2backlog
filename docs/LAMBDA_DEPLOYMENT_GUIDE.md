# Lambda関数デプロイメントガイド

## event_ingest関数

### 概要
Slackからのイベントを受信し、SQSキューに送信するLambda関数です。

### 主な機能
- Slack署名検証
- URLチャレンジ応答
- "Backlog登録希望"キーワード検出
- SQSへのメッセージ送信
- 構造化ログ出力

### 環境変数

| 変数名 | 説明 | 例 |
|--------|------|-----|
| SQS_QUEUE_URL | SQSキューのURL | https://sqs.region.amazonaws.com/account/queue |
| SLACK_SIGNING_SECRET | Slackシークレットの参照 | arn:aws:secretsmanager:region:account:secret:name |
| AWS_REGION | AWSリージョン | ap-northeast-1 |
| LOG_LEVEL | ログレベル | info |

### ローカルテスト

```bash
# 単体テスト実行
npm test tests/unit/event_ingest.test.js

# カバレッジ付きテスト
npm run test:coverage -- tests/unit/event_ingest.test.js

# ローカル実行
sam local start-api
```

### デプロイ

```bash
# ビルド
sam build

# デプロイ（開発環境）
sam deploy --config-env dev

# デプロイ（本番環境）
sam deploy --config-env prod --parameter-overrides Stage=prod
```

### ログ確認

```bash
# CloudWatch Logsの確認
aws logs tail /aws/lambda/slack2backlog-event-ingest-dev --follow

# 特定のエラーを検索
aws logs filter-log-events \
  --log-group-name /aws/lambda/slack2backlog-event-ingest-dev \
  --filter-pattern '{ $.level = "error" }'
```

### パフォーマンスチューニング

1. **メモリ設定**: 512MB（デフォルト）
   - 署名検証とJSON処理には十分
   - 必要に応じて256MB-1024MBで調整

2. **タイムアウト**: 10秒
   - Slackの3秒制限に対応
   - SQS送信を含めても十分な余裕

3. **同時実行数**: 制限なし
   - スパイクに対応可能
   - 必要に応じてリザーブドコンカレンシー設定

### トラブルシューティング

#### 署名検証エラー
```javascript
// ログで以下を確認
{ 
  "level": "warn", 
  "message": "Invalid request signature"
}
```
- Signing Secretが正しいか確認
- タイムスタンプのずれを確認（NTPサーバー同期）

#### SQS送信エラー
```javascript
{
  "level": "error",
  "message": "Failed to send to queue",
  "error": "Access Denied"
}
```
- IAMロールの権限確認
- SQSキューURLの確認

#### タイムアウト
- Lambda関数のタイムアウト設定確認
- SQSエンドポイントの接続性確認
- VPC設定の確認（使用している場合）

## 監視設定

### CloudWatchメトリクス
- Invocations: 呼び出し回数
- Errors: エラー率
- Duration: 実行時間
- Throttles: スロットリング

### アラーム推奨設定
```yaml
ErrorRateAlarm:
  MetricName: Errors
  Threshold: 1
  EvaluationPeriods: 1
  Period: 60

HighLatencyAlarm:
  MetricName: Duration
  Threshold: 3000  # 3秒
  EvaluationPeriods: 2
  Period: 60
```
