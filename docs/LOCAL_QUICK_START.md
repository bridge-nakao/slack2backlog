# ローカル環境クイックスタートガイド

このガイドでは、slack2backlogをローカル環境で素早く動作確認する手順を説明します。

## 📋 前提条件

以下がインストールされていること：
- Docker & Docker Compose
- Node.js (v18以上)
- AWS CLI
- SAM CLI

## 🚀 5分でセットアップ

### 1. リポジトリのクローンと依存関係インストール

**注意: このリポジトリはPrivateです。アクセス権限が必要です。**

```bash
# Personal Access Token (PAT) を使用する場合
git clone https://<YOUR_PAT>@github.com/bridge-nakao/slack2backlog.git

# SSH を使用する場合（推奨）
git clone git@github.com:bridge-nakao/slack2backlog.git

cd slack2backlog
npm install

# Lambda関数の依存関係もインストール
cd src/event_ingest && npm install && cd ../..
cd src/backlog_worker && npm install && cd ../..
```

### 2. ローカル環境の自動セットアップ

```bash
# このスクリプトが全ての準備を行います
./scripts/setup-local.sh
```

このスクリプトは以下を自動実行：
- ✅ Docker環境の起動（DynamoDB, LocalStack）
- ✅ DynamoDBテーブルの作成
- ✅ SQSキューの作成
- ✅ テスト用シークレットの作成
- ✅ SAMアプリケーションのビルド

### 3. 環境変数の準備（オプション）

デフォルト設定で動作しますが、カスタマイズする場合：

```bash
# env.local.jsonを作成
cp env.json env.local.json

# 必要に応じて編集
# - BACKLOG_SPACE: 実際のBacklogスペース
# - PROJECT_ID: 実際のプロジェクトID
# - ISSUE_TYPE_ID: 実際の課題タイプID
```

### 4. SAM Localでアプリケーション起動

```bash
# ターミナル1で実行
sam local start-api --env-vars env.json
```

## 🧪 動作確認

### 方法1: URL検証テスト（最も簡単）

```bash
# ターミナル2で実行
curl -X POST http://localhost:3000/slack/events \
  -H "Content-Type: application/json" \
  -d '{"type":"url_verification","challenge":"test-123"}'
```

期待される応答: `test-123`

### 方法2: メッセージイベントテスト

```bash
# Slackメッセージイベントをシミュレート
node scripts/send-test-event.js
```

### 方法3: 統合テスト実行

```bash
# 全てのテストを実行
./scripts/test-local.sh
```

## 📊 結果の確認

### DynamoDB Admin UI
ブラウザで http://localhost:8001 を開く
- テーブル: `slack2backlog-idempotency`
- 処理済みイベントのレコードが表示される

### CloudWatch Logs（SAM Local）
SAM Localを実行しているターミナルに直接ログが出力される

### SQSメッセージ確認
```bash
aws sqs receive-message \
  --queue-url http://localhost:4566/000000000000/slack2backlog-queue \
  --endpoint-url http://localhost:4566 \
  --region ap-northeast-1
```

## 🛠️ トラブルシューティング

### Dockerが起動しない
```bash
# Dockerサービスの確認
docker ps

# 再起動
docker-compose down
docker-compose up -d
```

### ポートが使用中
```bash
# 使用中のポートを確認
lsof -i :3000  # SAM Local
lsof -i :8000  # DynamoDB
lsof -i :4566  # LocalStack
```

### テストが失敗する
```bash
# クリーンインストール
rm -rf node_modules package-lock.json
npm install
npm test -- --clearCache
```

## 📝 次のステップ

1. **本格的な開発**: `docs/DEVELOPMENT_GUIDE.md`を参照
2. **本番デプロイ**: `docs/PRODUCTION_DEPLOYMENT.md`を参照
3. **Slack App設定**: `docs/SLACK_APP_SETUP_GUIDE.md`を参照
4. **Backlog設定**: `docs/BACKLOG_SETUP_GUIDE.md`を参照

## 🔗 便利なURL

- DynamoDB Admin: http://localhost:8001
- LocalStack Dashboard: http://localhost:4566
- SAM Local API: http://localhost:3000

これで、5分以内にローカル環境で動作確認ができます！