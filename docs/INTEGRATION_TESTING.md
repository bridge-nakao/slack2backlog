# 統合テストガイド

## 概要

このドキュメントでは、slack2backlogの統合テスト環境のセットアップと実行方法について説明します。

## 前提条件

- Docker及びDocker Composeがインストールされていること
- AWS CLIがインストールされていること
- SAM CLIがインストールされていること
- Node.js 18以上がインストールされていること

## テスト環境の構成

### Docker Services

1. **LocalStack** - AWS サービスのモック環境
   - SQS
   - Secrets Manager
   - Lambda
   - Port: 4566

2. **DynamoDB Local** - ローカルDynamoDB
   - Port: 8000

3. **DynamoDB Admin** - DynamoDB管理UI
   - Port: 8001
   - URL: http://localhost:8001

### SAM Local

- API Gateway のローカル実行環境
- Port: 3000
- エンドポイント: http://localhost:3000/slack/events

## 統合テストの実行

### 自動実行

```bash
# すべての統合テストを実行
./scripts/run-integration-tests.sh
```

このスクリプトは以下を自動的に実行します：
1. Docker サービスの起動
2. リソースの初期化
3. SAM アプリケーションのビルド
4. SAM Local API Gateway の起動
5. 統合テストの実行
6. クリーンアップ

### 手動実行

#### 1. 環境の起動

```bash
# Docker サービスの起動
docker-compose up -d

# DynamoDB テーブルの作成
aws dynamodb create-table \
  --table-name slack2backlog-idempotency \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:8000 \
  --region ap-northeast-1
```

#### 2. SAM Local の起動

```bash
# アプリケーションのビルド
sam build

# API Gateway の起動
sam local start-api --env-vars env.json --docker-network bridge
```

#### 3. テストの実行

```bash
# 統合テストの実行
npm test -- tests/integration/integration.test.js
```

#### 4. クリーンアップ

```bash
# Docker サービスの停止
docker-compose down
```

## テストケース

### API Gateway → Lambda 統合

1. **URL検証チャレンジ**
   - Slack の URL 検証に正しく応答することを確認

2. **署名検証**
   - 無効な署名を拒否することを確認
   - 有効な署名を受け入れることを確認

3. **イベント処理**
   - Slack イベントが正しく処理されることを確認

### SQS ワークフロー

1. **メッセージ送信**
   - SQS にメッセージが送信されることを確認

2. **メッセージ受信**
   - SQS からメッセージを受信できることを確認

### DynamoDB 冪等性

1. **キーの保存**
   - 冪等性キーが保存されることを確認

2. **重複検出**
   - 重複イベントが検出されることを確認

### Secrets Manager

1. **Slack シークレット**
   - Slack の認証情報を取得できることを確認

2. **Backlog シークレット**
   - Backlog の認証情報を取得できることを確認

## トラブルシューティング

### ポートの競合

既に使用されているポートがある場合は、`docker-compose.yml` でポートを変更してください。

### LocalStack の初期化エラー

LocalStack の初期化に失敗した場合は、以下を試してください：

```bash
# LocalStack のデータをクリア
rm -rf ./docker/localstack/*

# Docker ボリュームをクリア
docker-compose down -v
```

### SAM Local の起動エラー

SAM Local が起動しない場合は、Docker が正しく動作していることを確認してください：

```bash
docker ps
docker info
```

## デバッグ

### ログの確認

```bash
# LocalStack のログ
docker logs slack2backlog-localstack

# DynamoDB のログ
docker logs slack2backlog-dynamodb

# SAM Local のログは直接ターミナルに表示されます
```

### DynamoDB の内容確認

DynamoDB Admin UI (http://localhost:8001) で、テーブルの内容を確認できます。

### LocalStack のリソース確認

```bash
# SQS キューの一覧
aws sqs list-queues --endpoint-url http://localhost:4566

# Secrets の一覧
aws secretsmanager list-secrets --endpoint-url http://localhost:4566
```