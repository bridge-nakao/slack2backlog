# 開発ガイド

## 概要

このドキュメントでは、slack2backlogのローカル開発環境のセットアップから、デバッグ、テスト、デプロイまでの開発フロー全体を説明します。

## 前提条件

以下のツールがインストールされていることを確認してください：

- **Node.js** (v18以上)
- **Docker & Docker Compose**
- **AWS CLI**
- **SAM CLI**
- **Git**
- **VS Code** または **Cursor**（推奨エディタ）

## クイックスタート

```bash
# リポジトリのクローン
git clone https://github.com/bridge-nakao/slack2backlog.git
cd slack2backlog

# ローカル環境のセットアップ
./scripts/setup-local.sh

# SAM Local APIの起動
sam local start-api --env-vars env.json

# 別ターミナルでテストを実行
./scripts/test-local.sh
```

## 詳細なセットアップ手順

### 1. 依存関係のインストール

```bash
npm install
```

### 2. Docker環境の起動

```bash
docker-compose up -d
```

これにより以下のサービスが起動します：
- **DynamoDB Local** (ポート 8000)
- **LocalStack** (ポート 4566)
- **DynamoDB Admin** (ポート 8001)

### 3. AWSリソースの初期化

```bash
# DynamoDBテーブルの作成
aws dynamodb create-table \
  --table-name slack2backlog-idempotency \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:8000 \
  --region ap-northeast-1

# SQSキューの作成
aws sqs create-queue \
  --queue-name slack2backlog-queue \
  --endpoint-url http://localhost:4566 \
  --region ap-northeast-1
```

### 4. SAMアプリケーションのビルド

```bash
sam build
```

### 5. ローカルAPIの起動

```bash
sam local start-api --env-vars env.json --debug-port 9999
```

## 開発フロー

### 1. 機能開発

1. **新しいブランチを作成**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **コードを実装**
   - `src/`ディレクトリ内でLambda関数を開発
   - `template.yaml`でリソースを定義

3. **テストを作成**
   - `tests/unit/`にユニットテストを追加
   - `tests/integration/`に統合テストを追加

### 2. デバッグ

#### VS Code/Cursorでのデバッグ

1. `.vscode/launch.json`の設定を使用
2. ブレークポイントを設定
3. デバッグ構成を選択して実行

#### SAM Localでのデバッグ

```bash
# デバッグモードでSAM Localを起動
sam local start-api --env-vars env.json --debug-port 9999

# VS Codeで"Attach to SAM Local"構成を使用してアタッチ
```

#### ログの確認

```bash
# Docker logsの確認
docker logs slack2backlog-localstack
docker logs slack2backlog-dynamodb

# SAM Localのログはターミナルに直接出力されます
```

### 3. テスト

#### ユニットテスト

```bash
# 全てのユニットテストを実行
npm test

# 特定のファイルのみテスト
npm test -- tests/unit/event_ingest.test.js

# ウォッチモードでテスト
npm test -- --watch
```

#### 統合テスト

```bash
# ローカル環境が起動していることを確認してから実行
npm test -- tests/integration/integration.test.js
```

#### カバレッジ確認

```bash
npm run test:coverage
```

### 4. 手動テスト

#### Slack イベントのシミュレーション

```bash
# URL検証チャレンジ
curl -X POST http://localhost:3000/slack/events \
  -H "Content-Type: application/json" \
  -d '{"type":"url_verification","challenge":"test-challenge"}'

# メッセージイベント（要署名）
node scripts/send-test-event.js
```

#### DynamoDB データの確認

1. ブラウザで http://localhost:8001 を開く
2. テーブル `slack2backlog-idempotency` を選択
3. データを確認

## トラブルシューティング

### よくある問題と解決方法

#### 1. Docker サービスが起動しない

```bash
# Docker が実行中か確認
docker ps

# ポートの競合を確認
lsof -i :8000
lsof -i :4566

# Docker をリスタート
docker-compose down
docker-compose up -d
```

#### 2. SAM Local がエラーを出す

```bash
# SAM アプリケーションを再ビルド
sam build --use-container

# Python のバージョンを確認（3.8以上が必要）
python3 --version
```

#### 3. テストが失敗する

```bash
# node_modules をクリーンインストール
rm -rf node_modules package-lock.json
npm install

# Jest キャッシュをクリア
npm test -- --clearCache
```

#### 4. LocalStack の初期化に失敗

```bash
# LocalStack のログを確認
docker logs slack2backlog-localstack

# 手動でリソースを作成
./scripts/localstack-init.sh
```

## デバッグテクニック

### 1. console.log の活用

開発時は構造化ログを使用：

```javascript
const log = (level, message, data = {}) => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data
  }));
};

log('debug', 'Processing event', { eventId, userId });
```

### 2. AWS SDK のデバッグ

```javascript
// AWS SDK のデバッグログを有効化
AWS.config.update({ logger: console });
```

### 3. イベントの記録

```javascript
// Lambda イベントを保存してデバッグ
const fs = require('fs');
fs.writeFileSync('debug-event.json', JSON.stringify(event, null, 2));
```

## ベストプラクティス

### 1. コーディング規約

- **ESLint** の設定に従う
- **Prettier** でコードをフォーマット
- 意味のある変数名を使用
- 関数は単一責任の原則に従う

### 2. テスト駆動開発

1. テストを先に書く
2. テストが失敗することを確認
3. 最小限のコードで通す
4. リファクタリング

### 3. コミットメッセージ

```bash
# 良い例
git commit -m "feat: Add retry logic to Backlog API client"
git commit -m "fix: Handle empty message text in event processor"
git commit -m "test: Add unit tests for signature verification"

# 形式
# type: subject
# 
# type は以下のいずれか:
# - feat: 新機能
# - fix: バグ修正
# - docs: ドキュメント
# - test: テスト
# - refactor: リファクタリング
# - chore: その他の変更
```

### 4. プルリクエスト

- 機能ごとに小さなPRを作成
- テストが全て通ることを確認
- レビュアーが理解しやすい説明を記載
- 関連するIssue番号を含める

## リソース

- [AWS SAM ドキュメント](https://docs.aws.amazon.com/serverless-application-model/)
- [LocalStack ドキュメント](https://docs.localstack.cloud/)
- [Jest ドキュメント](https://jestjs.io/docs/getting-started)
- [Slack API ドキュメント](https://api.slack.com/)
- [Backlog API ドキュメント](https://developer.nulab.com/docs/backlog/)

## サポート

問題が解決しない場合は、GitHubのIssuesに報告してください。