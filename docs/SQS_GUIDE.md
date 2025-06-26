# SQSキュー設定ガイド

## 概要

このドキュメントでは、slack2backlogプロジェクトのSQSキュー設定とベストプラクティスについて説明します。

## キュー構成

### 1. イベントキュー（メインキュー）
- **名前**: `slack2backlog-event-queue-{stage}`
- **タイプ**: 標準キュー
- **用途**: SlackイベントをLambda間で非同期に受け渡し

#### 設定値
| パラメータ | 値 | 説明 |
|-----------|-----|------|
| VisibilityTimeout | 60秒 | Lambda関数の処理時間を考慮 |
| MessageRetentionPeriod | 4日間 | メッセージ保持期間 |
| MaximumMessageSize | 256KB | 最大メッセージサイズ |
| ReceiveMessageWaitTimeSeconds | 20秒 | ロングポーリング有効 |
| MaxReceiveCount | 3回 | DLQへ移動するまでの最大受信回数 |

### 2. デッドレターキュー（DLQ）
- **名前**: `slack2backlog-dlq-{stage}`
- **タイプ**: 標準キュー
- **用途**: 処理に失敗したメッセージの保管

#### 設定値
| パラメータ | 値 | 説明 |
|-----------|-----|------|
| MessageRetentionPeriod | 14日間 | 最大保持期間 |
| MaximumMessageSize | 256KB | メインキューと同じ |

## セキュリティ設定

### 暗号化
- **KMS暗号化**: 有効（aws/sqs エイリアス使用）
- **保管時の暗号化**: 自動的に有効

### アクセス制御
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLambdaAccess",
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:*:*:*",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": [
            "arn:aws:lambda:*:*:function:*-event-ingest-*",
            "arn:aws:lambda:*:*:function:*-backlog-worker-*"
          ]
        }
      }
    }
  ]
}
```

## メッセージフォーマット

### 標準メッセージ構造
```json
{
  "messageId": "unique-message-id",
  "timestamp": "2025-06-26T10:30:00Z",
  "source": "slack-event-ingest",
  "eventType": "slack.message",
  "data": {
    "slackEvent": {
      "type": "message",
      "channel": "C123ABC",
      "user": "U123ABC",
      "text": "Backlog登録希望 タスクの説明",
      "ts": "1234567890.123456"
    },
    "metadata": {
      "receivedAt": "2025-06-26T10:30:00Z",
      "apiGatewayRequestId": "request-id"
    }
  },
  "retryCount": 0
}
```

### メッセージ属性
- **eventType**: イベントの種類（例: "slack.message"）
- **priority**: 優先度（1-5、デフォルト: 3）
- **source**: メッセージの送信元
- **version**: メッセージフォーマットバージョン

## モニタリング

### CloudWatchメトリクス

#### 主要メトリクス
1. **ApproximateNumberOfMessagesVisible**: キュー内の処理待ちメッセージ数
2. **ApproximateAgeOfOldestMessage**: 最古メッセージの経過時間
3. **NumberOfMessagesSent**: 送信されたメッセージ数
4. **NumberOfMessagesReceived**: 受信されたメッセージ数
5. **NumberOfMessagesDeleted**: 削除されたメッセージ数

### アラーム設定

| アラーム名 | 条件 | 閾値 | アクション |
|-----------|------|------|------------|
| EventQueue-Depth | メッセージ数過多 | 100件以上 | 通知 |
| EventQueue-Age | メッセージ滞留 | 10分以上 | 通知 |
| DLQ-Messages | DLQメッセージ発生 | 1件以上 | 即時通知 |

## 運用手順

### メッセージ送信
```bash
# メッセージ送信
aws sqs send-message \
  --queue-url https://sqs.region.amazonaws.com/account/queue-name \
  --message-body '{"data": "test"}' \
  --message-attributes "eventType={StringValue=test,DataType=String}"
```

### メッセージ受信
```bash
# メッセージ受信（ロングポーリング）
aws sqs receive-message \
  --queue-url https://sqs.region.amazonaws.com/account/queue-name \
  --wait-time-seconds 20 \
  --max-number-of-messages 10
```

### DLQメッセージ処理
```bash
# DLQメッセージ確認
./scripts/process-dlq-messages.sh slack2backlog dev view

# DLQメッセージ再処理
./scripts/process-dlq-messages.sh slack2backlog dev reprocess

# DLQクリア（注意）
./scripts/process-dlq-messages.sh slack2backlog dev delete
```

## ベストプラクティス

### 1. メッセージサイズ最適化
- メッセージは64KB以下に保つ（パフォーマンス最適）
- 大きなデータはS3に保存し、参照のみメッセージに含める

### 2. バッチ処理
- 送信時は最大10メッセージまでバッチ化
- 受信時も最大10メッセージまで一括取得

### 3. エラーハンドリング
```javascript
// リトライロジック例
const maxRetries = 3;
let retryCount = 0;

while (retryCount < maxRetries) {
  try {
    await processMessage(message);
    await deleteMessage(message);
    break;
  } catch (error) {
    retryCount++;
    if (retryCount >= maxRetries) {
      // DLQへ自動的に移動
      throw error;
    }
    await sleep(Math.pow(2, retryCount) * 1000); // Exponential backoff
  }
}
```

### 4. 冪等性の確保
- メッセージIDを使用して重複処理を防ぐ
- DynamoDBに処理済みメッセージIDを記録

### 5. モニタリング
- CloudWatchダッシュボードで常時監視
- DLQメッセージは即座に調査
- メトリクスの異常値に対してアラーム設定

## トラブルシューティング

### 問題: メッセージが処理されない
1. **Lambda関数のエラー確認**
   ```bash
   aws logs tail /aws/lambda/backlog-worker --follow
   ```

2. **キューのメトリクス確認**
   ```bash
   aws sqs get-queue-attributes \
     --queue-url $QUEUE_URL \
     --attribute-names All
   ```

3. **DLQ確認**
   ```bash
   ./scripts/process-dlq-messages.sh slack2backlog dev view
   ```

### 問題: メッセージ重複
1. **VisibilityTimeout確認**: 処理時間より長く設定
2. **冪等性キーの確認**: DynamoDBでevent_idを確認
3. **削除処理の確認**: 正常終了時にdeleteMessageが呼ばれているか

### 問題: 高レイテンシ
1. **ロングポーリング設定確認**: 20秒に設定
2. **Lambda同時実行数確認**: リザーブドコンカレンシー設定
3. **メッセージサイズ確認**: 大きすぎるメッセージがないか

## コスト最適化

### 料金体系
- **リクエスト料金**: $0.40 / 100万リクエスト
- **データ転送料金**: 同一リージョン内は無料
- **メッセージ保持**: 無料（標準キュー）

### コスト削減Tips
1. **バッチ処理**: 1リクエストで最大10メッセージ
2. **ロングポーリング**: 空のレスポンスを削減
3. **適切な保持期間**: 必要最小限に設定
4. **DLQ定期クリーンアップ**: 古いメッセージを削除

## 関連ドキュメント

- [メッセージフォーマット仕様](./sqs/message-format.md)
- [AWS SQS公式ドキュメント](https://docs.aws.amazon.com/sqs/)
- [SQSベストプラクティス](https://docs.aws.amazon.com/sqs/latest/dg/sqs-best-practices.html)