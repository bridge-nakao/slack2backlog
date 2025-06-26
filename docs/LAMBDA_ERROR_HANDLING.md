# Lambda関数エラーハンドリングガイド

## event_ingest関数のエラーハンドリング

### エラーパターンと対処法

#### 1. 署名検証エラー (401 Unauthorized)

**症状**
```json
{
  "level": "warn",
  "message": "Invalid request signature"
}
```

**原因**
- Slackの署名シークレットが間違っている
- タイムスタンプが古い（5分以上経過）
- リクエストが改ざんされている

**対処法**
1. Secrets Managerの値を確認
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id slack2backlog-slack-secrets-dev \
     --query SecretString
   ```

2. NTPサーバーの時刻同期確認
   ```bash
   timedatectl status
   ```

3. Slackアプリの設定確認

#### 2. JSON解析エラー (400 Bad Request)

**症状**
```json
{
  "level": "error",
  "message": "Invalid JSON in request body",
  "error": "Unexpected token..."
}
```

**原因**
- リクエストボディが正しいJSON形式でない
- Content-Typeヘッダーの誤り

**対処法**
- API Gatewayのログで生のリクエストを確認
- Content-Typeが`application/json`であることを確認

#### 3. SQS送信エラー (500 Internal Server Error)

**症状**
```json
{
  "level": "error",
  "message": "Failed to send to queue",
  "error": "Access Denied"
}
```

**原因**
- IAMロールの権限不足
- SQSキューが存在しない
- ネットワーク接続の問題

**対処法**
1. IAMロールの確認
   ```bash
   aws iam get-role-policy --role-name lambda-role --policy-name policy-name
   ```

2. SQSキューの存在確認
   ```bash
   aws sqs get-queue-attributes --queue-url $QUEUE_URL
   ```

3. VPC設定の確認（使用している場合）

#### 4. Secrets Manager アクセスエラー

**症状**
```json
{
  "level": "error",
  "message": "Failed to retrieve signing secret",
  "error": "AccessDeniedException"
}
```

**原因**
- Secrets Managerへのアクセス権限がない
- シークレットが存在しない
- KMS暗号化キーへのアクセス権限がない

**対処法**
1. シークレットの存在確認
   ```bash
   aws secretsmanager describe-secret --secret-id secret-name
   ```

2. リソースポリシーの確認
   ```bash
   aws secretsmanager get-resource-policy --secret-id secret-name
   ```

### エラー監視設定

#### CloudWatch Logs Insights クエリ

**エラー発生率の確認**
```
fields @timestamp, level, message
| filter level = "error"
| stats count() by bin(5m)
```

**署名検証失敗の詳細**
```
fields @timestamp, message, signature, timestamp
| filter message = "Invalid request signature"
| sort @timestamp desc
| limit 20
```

**レスポンスタイムの分析**
```
fields @timestamp, duration
| filter message = "Request processed successfully"
| stats avg(duration), max(duration), min(duration) by bin(5m)
```

#### CloudWatch Alarms

```yaml
# エラー率アラーム
ErrorRateAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: event-ingest-error-rate
    MetricName: Errors
    Namespace: AWS/Lambda
    Dimensions:
      - Name: FunctionName
        Value: slack2backlog-event-ingest-dev
    Statistic: Average
    Period: 300
    EvaluationPeriods: 1
    Threshold: 0.01  # 1%
    ComparisonOperator: GreaterThanThreshold

# 署名検証失敗アラーム
SignatureFailureAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: event-ingest-signature-failures
    MetricName: SignatureVerificationFailures
    Namespace: CustomMetrics/Lambda
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 1
    Threshold: 10
    ComparisonOperator: GreaterThanThreshold
```

### デバッグ手法

#### 1. ローカルデバッグ

```bash
# SAM Localでのデバッグ
sam local start-api --debug-port 5858

# VS Codeのlaunch.json
{
  "version": "0.2.0",
  "configurations": [{
    "type": "node",
    "request": "attach",
    "name": "Attach to SAM Local",
    "address": "localhost",
    "port": 5858,
    "localRoot": "${workspaceFolder}/src/event_ingest",
    "remoteRoot": "/var/task",
    "protocol": "inspector"
  }]
}
```

#### 2. リモートデバッグ

```javascript
// 一時的なデバッグログ追加
if (process.env.DEBUG === 'true') {
  console.log('DEBUG: Full event', JSON.stringify(event, null, 2));
  console.log('DEBUG: Headers', headers);
  console.log('DEBUG: Computed signature', mySignature);
}
```

#### 3. X-Rayトレーシング

```javascript
const AWSXRay = require('aws-xray-sdk-core');
const AWS = AWSXRay.captureAWS(require('aws-sdk'));

// サブセグメントの追加
const subsegment = AWSXRay.getSegment().addNewSubsegment('signature-verification');
try {
  // 署名検証処理
} finally {
  subsegment.close();
}
```

### パフォーマンスチューニング

#### 1. コールドスタート対策

```javascript
// グローバルスコープで初期化
const sqs = new AWS.SQS();
const secretsManager = new AWS.SecretsManager();
let cachedSecret = null;

// ハンドラー内で再利用
if (!cachedSecret) {
  cachedSecret = await getSigningSecret();
}
```

#### 2. 並行処理の最適化

```javascript
// 非同期処理の並列実行
const [signingSecret, queueUrl] = await Promise.all([
  getSigningSecret(),
  getQueueUrl()
]);
```

#### 3. メモリ使用量の最適化

```javascript
// 大きなオブジェクトの早期解放
let largeObject = processData();
// 使用後
largeObject = null;
```

### エラーリカバリー戦略

#### 1. 自動リトライ

Lambda関数の設定:
- 最大リトライ回数: 2
- 最大イベント年齢: 60秒

#### 2. DLQへの送信

失敗したイベントは自動的にDLQへ送信され、後で調査・再処理が可能。

#### 3. サーキットブレーカー

```javascript
class CircuitBreaker {
  constructor(threshold = 5, timeout = 60000) {
    this.failureCount = 0;
    this.threshold = threshold;
    this.timeout = timeout;
    this.state = 'CLOSED';
    this.nextAttempt = Date.now();
  }

  async call(fn) {
    if (this.state === 'OPEN') {
      if (Date.now() < this.nextAttempt) {
        throw new Error('Circuit breaker is OPEN');
      }
      this.state = 'HALF_OPEN';
    }

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  onSuccess() {
    this.failureCount = 0;
    this.state = 'CLOSED';
  }

  onFailure() {
    this.failureCount++;
    if (this.failureCount >= this.threshold) {
      this.state = 'OPEN';
      this.nextAttempt = Date.now() + this.timeout;
    }
  }
}
```

## まとめ

エラーハンドリングは以下の観点で実装:

1. **早期検証**: 入力検証を最初に実施
2. **詳細なログ**: 問題調査に必要な情報を記録
3. **適切なHTTPステータス**: クライアントが適切に対処可能
4. **監視とアラート**: 問題の早期発見
5. **自動リカバリー**: 一時的な問題への対処

これらの実装により、信頼性の高いLambda関数を実現します。