# 負荷テストガイド

## 概要

このドキュメントでは、slack2backlogの負荷テストの実行方法と結果の分析について説明します。

## テストツール

### 1. Artillery（推奨）

高度な負荷テストツール。詳細なシナリオ定義とレポート生成が可能。

#### インストール

```bash
npm install -g artillery
```

### 2. Simple Load Test

Node.jsベースのシンプルな負荷テストツール。外部依存なしで動作。

## 負荷テストの実行

### 自動実行

```bash
./scripts/run-load-test.sh
```

このスクリプトは：
- Artilleryがインストールされている場合は、Artilleryを使用
- インストールされていない場合は、Simple Load Testを使用

### 手動実行

#### Artillery使用時

```bash
# SAM Localを起動
sam local start-api --env-vars env.json --port 3000

# 別ターミナルで負荷テストを実行
artillery run tests/performance/artillery-config.yml
```

#### Simple Load Test使用時

```bash
# 直接実行
node tests/performance/simple-load-test.js
```

## テストシナリオ

### 1. 基本シナリオ（Artillery）

| フェーズ | 期間 | RPS | 説明 |
|---------|------|-----|------|
| Warm up | 60秒 | 10 | ウォームアップ |
| Ramp up | 120秒 | 50 | 負荷を徐々に増加 |
| Sustained | 180秒 | 100 | 持続的な高負荷 |

### 2. シナリオ配分

- 80%: Backlog登録希望メッセージ
- 15%: 通常のメッセージ
- 5%: URL検証リクエスト

### 3. 簡易テスト（Simple Load Test）

- デフォルト: 30秒間、20 RPS
- カスタマイズ可能な設定

## パフォーマンス目標

### 必須要件

1. **レスポンスタイム**
   - P95 < 2秒
   - P99 < 3秒

2. **エラー率**
   - < 0.1%

3. **スループット**
   - 最低100 RPS対応

### 推奨目標

1. **レスポンスタイム**
   - P50 < 500ms
   - P95 < 1秒

2. **同時実行数**
   - Lambda同時実行数 < 100

## 結果の分析

### Artillery レポート

HTMLレポートが自動生成されます：
```
tests/performance/performance-report.html
```

レポートには以下が含まれます：
- レスポンスタイムの分布
- RPSの推移
- エラー率
- 各エンドポイントの統計

### Simple Load Test 結果

コンソールに以下が出力されます：
```
📊 Test Results:
================
Total Requests: 600
Successful: 594 (99.00%)
Failed: 6

Response Times:
  Average: 152.34ms
  P50: 145.23ms
  P95: 248.56ms
  P99: 289.12ms
```

## パフォーマンスチューニング

### 1. Lambda設定

```yaml
# template.yaml
Properties:
  MemorySize: 512  # 必要に応じて増加
  Timeout: 30
  ReservedConcurrentExecutions: 100
```

### 2. SQS設定

```yaml
Properties:
  VisibilityTimeout: 300
  ReceiveMessageWaitTimeSeconds: 20  # Long polling
  BatchSize: 10  # Lambda trigger
```

### 3. DynamoDB設定

```yaml
Properties:
  BillingMode: PAY_PER_REQUEST  # オンデマンド
  # または
  ProvisionedThroughput:
    ReadCapacityUnits: 100
    WriteCapacityUnits: 100
```

## トラブルシューティング

### 高レスポンスタイム

1. **Cold Start**
   - Lambda Provisioned Concurrencyの使用を検討
   - MemorySizeの増加

2. **外部API呼び出し**
   - 接続プーリングの最適化
   - タイムアウト設定の調整

### 高エラー率

1. **レート制限**
   - Slack API: 1分あたり60リクエスト
   - Backlog API: プランに依存

2. **同時実行制限**
   - Lambda同時実行数の確認
   - SQSのスロットリング設定

## ベストプラクティス

1. **段階的な負荷増加**
   - 急激な負荷増加を避ける
   - ウォームアップフェーズを設ける

2. **本番環境に近い設定**
   - 同じLambdaメモリサイズ
   - 同じ外部API設定

3. **定期的な実行**
   - デプロイ前の負荷テスト
   - 月次での性能確認

4. **結果の記録**
   - 各テストの結果を保存
   - 性能推移の追跡

## 監視とアラート

### CloudWatch メトリクス

1. **Lambda メトリクス**
   - Duration
   - Error count
   - Concurrent executions

2. **API Gateway メトリクス**
   - 4XX/5XX errors
   - Latency

3. **SQS メトリクス**
   - Messages in queue
   - Message age

### アラート設定例

```yaml
LambdaErrorAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    MetricName: Errors
    Threshold: 10
    EvaluationPeriods: 1
    Period: 300
```