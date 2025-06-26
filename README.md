# slack2backlog

Slackメッセージを自動的にBacklog課題として登録するAWS Lambdaベースのボット

## 概要

slack2backlogは、Slackワークスペース内の複数チャンネルを監視し、「Backlog登録希望」を含むメッセージを自動的にBacklogの課題として登録するサーバーレスアプリケーションです。AWS Lambda、API Gateway、SQSを使用した非同期2段構成により、高速かつ信頼性の高い処理を実現します。

## プロジェクト構造

```
slack2backlog/
├── src/                      # ソースコード
│   ├── event_ingest/        # Slackイベント受信Lambda関数
│   │   ├── index.js         # メインハンドラー
│   │   └── package.json     # 関数固有の依存関係
│   ├── backlog_worker/      # Backlog処理Lambda関数
│   │   ├── index.js         # メインハンドラー
│   │   └── package.json     # 関数固有の依存関係
│   └── shared/              # 共有ユーティリティ
│       ├── slack-client.js  # Slack APIクライアント
│       ├── backlog-client.js # Backlog APIクライアント
│       └── utils.js         # 共通ユーティリティ
├── tests/                    # テストファイル
│   ├── unit/                # 単体テスト
│   ├── integration/         # 統合テスト
│   └── load/                # 負荷テスト
├── docs/                     # ドキュメント
├── scripts/                  # ユーティリティスクリプト
├── events/                   # SAMテストイベント
├── .github/workflows/        # GitHub Actions
├── template.yaml            # SAMテンプレート
├── samconfig.toml          # SAM設定
├── docker-compose.yml      # ローカル開発環境
├── buildspec.yml           # AWS CodeBuild設定
├── package.json            # プロジェクト設定
├── jest.config.js          # Jest設定
├── .eslintrc.json          # ESLint設定
├── .prettierrc             # Prettier設定
└── .gitignore              # Git除外設定
```

## アーキテクチャ

```
Slack (Events API)
     │  HTTPS POST
┌────▼──────────────┐
│ API Gateway REST │  ← 署名検証は Lambda 層で実施
└────┬──────────────┘
     │ (proxy integration)
┌────▼──────────────┐
│ Lambda: event_ingest│  (Stage: prod)
└────┬──────────────┘
     │ SQS enqueue (JSON)
┌────▼──────────────┐
│ Lambda: backlog_worker│  (reserved concurrency 1)
└────┬──────────────┘
     │ HTTPS
┌────▼──────────────┐
│ Backlog API (POST /api/v2/issues) │
└──────────────────┘
```

### 主な特徴

- **非同期処理**: Slackの3秒制限に対応するため、即座に200 OKを返却
- **署名検証**: X-Slack-Signature/X-Slack-Request-TimestampをHMAC-SHA256で検証
- **リトライ機能**: Backlogエラー時は最大3回のExponential back-off
- **冪等性保証**: event_idをDynamoDBで管理し、重複登録を防止
- **エラーハンドリング**: 失敗時はDLQへ隔離、詳細ログをCloudWatchに記録

## 主な機能

- 📨 **自動メッセージ監視**: ワークスペース全体のメッセージを監視
- 🔍 **キーワード検出**: 「Backlog登録希望」を含むメッセージを自動検出
- 🎯 **課題自動作成**: Backlog APIを使用して課題を自動登録
- 💬 **スレッド返信**: 登録結果を元メッセージのスレッドに返信
- 🔄 **エラー処理**: 失敗時の自動リトライとエラー通知

## 必要な権限・スコープ

### Slack Bot Token Scopes
- `chat:write` - メッセージ投稿
- `channels:history` - パブリックチャンネルの履歴読み取り
- `groups:history` - プライベートチャンネルの履歴読み取り
- `im:history` - DMの履歴読み取り

### Event Subscriptions
- `message.channels` - パブリックチャンネルのメッセージ
- `message.groups` - プライベートチャンネルのメッセージ
- `message.im` - DMのメッセージ

## セットアップ

### 前提条件

- AWS CLIがインストール・設定済み
- Node.js 20.x または Python 3.12
- SAM CLI または AWS CDK
- Slack Appの作成権限
- Backlog APIキー

### 1. リポジトリのクローン

```bash
git clone git@github.com:yourorg/slack2backlog.git
cd slack2backlog
```

### 2. 依存関係のインストール

```bash
npm install
# または
pip install -r requirements.txt
```

### 3. AWSリソースのデプロイ

#### SAMを使用する場合
```bash
sam build
sam deploy --guided
```

#### CDKを使用する場合
```bash
npm install -g aws-cdk
cdk bootstrap
cdk deploy
```

### 4. Slack Appの設定

1. [Slack API](https://api.slack.com/apps)で新しいAppを作成
2. Event Subscriptionsを有効化
   - Request URL: `https://api.example.com/slack/events`
3. Subscribe to bot eventsで以下を追加:
   - `message.channels`
   - `message.groups`  
   - `message.im`
4. OAuth & Permissionsで必要なスコープを追加
5. ワークスペースにインストール

### 5. 環境変数の設定

#### Secrets Managerを使用（推奨）
```bash
aws secretsmanager create-secret --name slack2backlog-secrets \
  --secret-string '{
    "SLACK_BOT_TOKEN":"xoxb-...",
    "SLACK_SIGNING_SECRET":"abcd1234...",
    "BACKLOG_API_KEY":"..."
  }'
```

#### Lambda環境変数を直接更新
```bash
aws lambda update-function-configuration \
  --function-name backlog_worker \
  --environment "Variables={
    BACKLOG_SPACE=example.backlog.com,
    PROJECT_ID=12345,
    ISSUE_TYPE_ID=67890,
    PRIORITY_ID=3
  }"
```

## 環境変数

| 変数名 | 説明 | 例 |
|--------|------|-----|
| `SLACK_BOT_TOKEN` | Slack Bot User OAuth Token | `xoxb-...` |
| `SLACK_SIGNING_SECRET` | Slack Signing Secret | `abcd1234...` |
| `BACKLOG_API_KEY` | Backlog APIキー | `...` |
| `BACKLOG_SPACE` | Backlogスペース名 | `example.backlog.com` |
| `PROJECT_ID` | デフォルトプロジェクトID | `12345` |
| `ISSUE_TYPE_ID` | デフォルト課題タイプID | `67890` |
| `PRIORITY_ID` | デフォルト優先度ID | `3` |

## 使用方法

### 基本的な使用方法

Slackの任意のチャンネルで以下のようなメッセージを投稿：

```
Backlog登録希望 APIのバグを修正する
```

ボットが自動的に検出し、Backlogに課題を登録後、スレッドに返信します：

```
課題 ABC-123 を登録しました
```

### メッセージフォーマット

- 必須キーワード: `Backlog登録希望`
- 位置: メッセージの先頭または任意の位置
- 残りのテキスト: 課題のタイトルとして使用

## トラブルシューティング

### よくある問題

1. **署名検証エラー**
   - Signing Secretが正しく設定されているか確認
   - タイムスタンプの時刻ずれ（5分以内）を確認

2. **権限エラー**
   - Slack Appの権限スコープを確認
   - ボットがチャンネルに追加されているか確認

3. **Backlog API エラー**
   - APIキーの有効性を確認
   - プロジェクトID、課題タイプIDが正しいか確認

### ログの確認

```bash
# event_ingestのログ
aws logs tail /aws/lambda/event_ingest --follow

# backlog_workerのログ
aws logs tail /aws/lambda/backlog_worker --follow

# DLQメッセージの確認
aws sqs receive-message --queue-url https://sqs.region.amazonaws.com/.../dlq
```

## パフォーマンス目標

- **レスポンス時間**: 受信からACKまで1秒未満（p95）
- **処理能力**: 月10万件のメッセージ処理
- **コスト**: 月額500円未満
- **可用性**: 99.9%

## 開発

### ローカルテスト

```bash
# ローカルサービスの起動（DynamoDB、SQS）
./scripts/local/start-local.sh

# SAM Localを使用
sam local start-api

# テストイベントの送信
curl -X POST http://localhost:3000/slack/events \
  -H "Content-Type: application/json" \
  -d @events/slack-event.json

# ローカルサービスの停止
./scripts/local/stop-local.sh
```

### ユニットテスト

```bash
npm test
# または
pytest
```

### デプロイパイプライン

```bash
# 本番環境へのデプロイ
npm run deploy:prod

# ステージング環境へのデプロイ
npm run deploy:staging
```

## 今後の拡張予定

1. **キーワード拡張**: 正規表現対応、複数キーワード設定
2. **スラッシュコマンド**: `/backlog create`コマンドの追加
3. **ファイル添付**: Slackファイルの自動転送
4. **双方向同期**: Backlogコメントの自動反映
5. **カスタマイズ**: チャンネル別の設定機能

## ライセンス

MIT License

## 貢献

プルリクエストを歓迎します。大きな変更の場合は、まずissueを作成して議論してください。

## サポート

問題や質問がある場合は、[GitHubのIssue](https://github.com/yourorg/slack2backlog/issues)を作成してください。