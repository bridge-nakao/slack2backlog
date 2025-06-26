# API Gateway設定ガイド

## 概要

このドキュメントでは、slack2backlogプロジェクトのAPI Gateway設定について説明します。

## エンドポイント構成

### 本番環境
- **URL**: `https://api.example.com/prod/slack/events`
- **メソッド**: POST
- **認証**: Slack署名検証（X-Slack-Signature）

### 開発環境
- **URL**: `http://localhost:3000/slack/events`
- **メソッド**: POST

## リクエスト/レスポンス仕様

### リクエストヘッダー

| ヘッダー名 | 必須 | 説明 |
|-----------|------|------|
| Content-Type | Yes | `application/json` |
| X-Slack-Signature | Yes | HMAC-SHA256署名 |
| X-Slack-Request-Timestamp | Yes | リクエストのUnixタイムスタンプ |

### リクエストボディ

#### URL検証
```json
{
  "type": "url_verification",
  "challenge": "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P",
  "token": "verification_token"
}
```

#### メッセージイベント
```json
{
  "token": "verification_token",
  "team_id": "T123",
  "api_app_id": "A123",
  "event": {
    "type": "message",
    "channel": "C123",
    "user": "U123",
    "text": "Backlog登録希望 タスクの説明",
    "ts": "1234567890.123456"
  },
  "type": "event_callback",
  "event_id": "Ev123",
  "event_time": 1234567890
}
```

### レスポンス

#### 成功時（200 OK）
```json
{
  "ok": true
}
```

#### URL検証時（200 OK）
```json
{
  "challenge": "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P"
}
```

#### エラー時（400/500）
```json
{
  "error": "Invalid signature",
  "details": {
    "reason": "Signature verification failed"
  }
}
```

## セキュリティ設定

### 署名検証
- すべてのリクエストでX-Slack-Signatureヘッダーを検証
- タイムスタンプは5分以内のものしか受け付けない
- HMAC-SHA256アルゴリズムを使用

### レート制限
- **Rate**: 100 requests/second
- **Burst**: 200 requests
- **月間クォータ**: 1,000,000 requests

### CORS設定
- **Allowed Origins**: `*`（本番環境では制限推奨）
- **Allowed Methods**: POST, OPTIONS
- **Allowed Headers**: Content-Type, X-Slack-Signature, X-Slack-Request-Timestamp
- **Max Age**: 86400秒（24時間）

## モニタリング

### CloudWatchメトリクス
- **4XXError**: クライアントエラー数
- **5XXError**: サーバーエラー数
- **Count**: 総リクエスト数
- **Latency**: レスポンス時間

### アラーム設定
1. **高4XXエラー率**: 5分間で10エラー以上
2. **5XXエラー発生**: 1分間で1エラー以上
3. **高レイテンシ**: 平均1000ms以上が10分継続

### ログ
- **ログ保持期間**: 7日間
- **ログレベル**: INFO（本番環境）
- **データトレース**: 有効（開発環境のみ推奨）

## テスト方法

### ローカルテスト
```bash
# SAM Localを起動
sam local start-api

# テストスクリプトを実行
./scripts/test-api-gateway.sh local
```

### 本番環境テスト
```bash
# デプロイ後にテスト
./scripts/test-api-gateway.sh prod
```

### cURLでの手動テスト
```bash
# URL検証
curl -X POST http://localhost:3000/slack/events \
  -H "Content-Type: application/json" \
  -H "X-Slack-Signature: v0=dummy" \
  -H "X-Slack-Request-Timestamp: $(date +%s)" \
  -d '{"type":"url_verification","challenge":"test123"}'

# メッセージイベント
curl -X POST http://localhost:3000/slack/events \
  -H "Content-Type: application/json" \
  -H "X-Slack-Signature: v0=dummy" \
  -H "X-Slack-Request-Timestamp: $(date +%s)" \
  -d @events/slack-event.json
```

## トラブルシューティング

### よくある問題

#### 1. 403 Forbidden
- **原因**: 署名検証失敗
- **対処**: Signing Secretが正しく設定されているか確認

#### 2. 504 Gateway Timeout
- **原因**: Lambda関数のタイムアウト
- **対処**: Lambda関数のタイムアウト設定を確認（現在10秒）

#### 3. CORS エラー
- **原因**: ブラウザからの直接アクセス
- **対処**: Slack Events APIは直接呼び出しのみ対応

### デバッグ方法

1. **CloudWatch Logs確認**
```bash
aws logs tail /aws/api-gateway/slack2backlog-dev --follow
```

2. **X-Ray トレース確認**
```bash
aws xray get-trace-summaries --time-range-type LastHour
```

3. **メトリクス確認**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --dimensions Name=ApiName,Value=slack2backlog-api \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## ベストプラクティス

1. **本番環境では必ずカスタムドメインを使用**
2. **APIキーや署名検証を適切に実装**
3. **レート制限を適切に設定**
4. **エラーレスポンスに機密情報を含めない**
5. **定期的にログとメトリクスを確認**

## 関連ドキュメント

- [OpenAPI仕様書](./api/openapi.yaml)
- [リクエストモデル定義](./api/models.json)
- [AWS API Gateway公式ドキュメント](https://docs.aws.amazon.com/apigateway/)
- [Slack Events API](https://api.slack.com/apis/events-api)