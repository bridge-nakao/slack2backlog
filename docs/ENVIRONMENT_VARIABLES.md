# 環境変数設定ガイド

## 概要

このドキュメントでは、slack2backlogアプリケーションで使用する環境変数の設定方法を説明します。

## 必須環境変数

### Slack関連

| 変数名 | 説明 | 取得方法 | 例 |
|--------|------|----------|-----|
| `SLACK_SIGNING_SECRET` | Slack署名検証用シークレット | Slack App > Basic Information > App Credentials | `abc123def456...` |
| `SLACK_BOT_TOKEN` | SlackボットOAuthトークン | Slack App > OAuth & Permissions > Bot User OAuth Token | `xoxb-123456789...` |

### Backlog関連

| 変数名 | 説明 | 取得方法 | 例 |
|--------|------|----------|-----|
| `BACKLOG_API_KEY` | Backlog APIキー | Backlog > 個人設定 > API | `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqr` |
| `BACKLOG_SPACE` | Backlogスペース名 | BacklogのURL | `yourspace.backlog.com` |
| `PROJECT_ID` | BacklogプロジェクトID | プロジェクト設定 > 基本設定 | `12345` |
| `ISSUE_TYPE_ID` | Backlog課題タイプID | プロジェクト設定 > 課題タイプ | `67890` |
| `PRIORITY_ID` | Backlog優先度ID（オプション） | API経由で取得 | `3` |

### AWS関連

| 変数名 | 説明 | デフォルト値 |
|--------|------|-------------|
| `AWS_REGION` | AWSリージョン | `ap-northeast-1` |
| `QUEUE_URL` | SQSキューURL | CloudFormationで自動設定 |
| `IDEMPOTENCY_TABLE` | DynamoDBテーブル名 | CloudFormationで自動設定 |
| `ENVIRONMENT` | 実行環境 | `production` |

## 設定方法

### 1. AWS Secrets Managerを使用（推奨）

#### Slack認証情報の保存

```bash
aws secretsmanager create-secret \
  --name slack2backlog-slack-secrets \
  --secret-string '{
    "bot_token": "xoxb-your-bot-token",
    "signing_secret": "your-signing-secret"
  }'
```

#### Backlog認証情報の保存

```bash
aws secretsmanager create-secret \
  --name slack2backlog-backlog-secrets \
  --secret-string '{
    "api_key": "your-api-key",
    "space_id": "yourspace"
  }'
```

### 2. SAMテンプレートでの参照

```yaml
Parameters:
  SlackSigningSecret:
    Type: String
    Default: slack2backlog-slack-secrets
    Description: Secrets Manager secret name for Slack credentials

Environment:
  Variables:
    SLACK_SIGNING_SECRET: !Ref SlackSigningSecret
```

### 3. ローカル開発環境

#### env.jsonファイル

```json
{
  "EventIngestFunction": {
    "SLACK_SIGNING_SECRET": "slack2backlog-slack-secrets",
    "QUEUE_URL": "http://localhost:4566/000000000000/slack2backlog-queue",
    "AWS_REGION": "ap-northeast-1",
    "NODE_ENV": "development"
  },
  "BacklogWorkerFunction": {
    "SLACK_BOT_TOKEN": "slack2backlog-slack-secrets",
    "BACKLOG_API_KEY": "slack2backlog-backlog-secrets",
    "BACKLOG_SPACE": "test.backlog.com",
    "PROJECT_ID": "12345",
    "ISSUE_TYPE_ID": "67890",
    "PRIORITY_ID": "3",
    "IDEMPOTENCY_TABLE": "slack2backlog-idempotency",
    "AWS_REGION": "ap-northeast-1",
    "NODE_ENV": "development"
  }
}
```

#### .envファイル（gitignore推奨）

```bash
# Slack
SLACK_SIGNING_SECRET=your-signing-secret
SLACK_BOT_TOKEN=xoxb-your-bot-token

# Backlog
BACKLOG_API_KEY=your-api-key
BACKLOG_SPACE=yourspace.backlog.com
PROJECT_ID=12345
ISSUE_TYPE_ID=67890
PRIORITY_ID=3

# AWS
AWS_REGION=ap-northeast-1
```

## 環境別設定

### 開発環境

```bash
sam deploy --parameter-overrides \
  Environment=dev \
  SlackSigningSecret=slack2backlog-dev-slack-secrets \
  BacklogApiKey=slack2backlog-dev-backlog-secrets
```

### ステージング環境

```bash
sam deploy --parameter-overrides \
  Environment=staging \
  SlackSigningSecret=slack2backlog-staging-slack-secrets \
  BacklogApiKey=slack2backlog-staging-backlog-secrets
```

### 本番環境

```bash
sam deploy --parameter-overrides \
  Environment=production \
  SlackSigningSecret=slack2backlog-prod-slack-secrets \
  BacklogApiKey=slack2backlog-prod-backlog-secrets
```

## APIキー・トークンの取得方法

### Slack

1. **Slack App作成**
   - https://api.slack.com/apps にアクセス
   - 「Create New App」をクリック
   - 「From an app manifest」を選択

2. **App Manifest**
   ```yaml
   display_information:
     name: Backlog Bot
     description: Slackメッセージから自動的にBacklog課題を作成
   features:
     bot_user:
       display_name: Backlog Bot
       always_online: true
   oauth_config:
     scopes:
       bot:
         - chat:write
         - channels:history
         - groups:history
         - im:history
         - mpim:history
   settings:
     event_subscriptions:
       request_url: https://your-api-gateway-url/slack/events
       bot_events:
         - message.channels
         - message.groups
         - message.im
         - message.mpim
   ```

3. **認証情報取得**
   - Basic Information > App Credentials > Signing Secret
   - OAuth & Permissions > Bot User OAuth Token

### Backlog

1. **APIキー作成**
   - Backlogにログイン
   - 個人設定 > API
   - 「新しいAPIキーを発行」

2. **プロジェクト情報取得**
   ```bash
   # プロジェクト一覧取得
   curl -X GET \
     "https://yourspace.backlog.com/api/v2/projects?apiKey=YOUR_API_KEY"
   
   # 課題タイプ一覧取得
   curl -X GET \
     "https://yourspace.backlog.com/api/v2/projects/PROJECT_ID/issueTypes?apiKey=YOUR_API_KEY"
   ```

## セキュリティベストプラクティス

1. **環境変数の直接埋め込み禁止**
   - ソースコードに認証情報を直接記載しない
   - .envファイルは必ず.gitignoreに追加

2. **Secrets Manager推奨**
   - 本番環境では必ずSecrets Managerを使用
   - 定期的なローテーション設定

3. **最小権限の原則**
   - 必要最小限の権限のみ付与
   - 環境ごとに異なる認証情報を使用

4. **監査ログ**
   - シークレットへのアクセスログを監視
   - 異常なアクセスパターンの検知

## トラブルシューティング

### よくあるエラー

#### 1. Secrets Manager アクセスエラー

```
Error: User is not authorized to perform: secretsmanager:GetSecretValue
```

**解決方法**: Lambda実行ロールにSecrets Manager読み取り権限を追加

#### 2. 環境変数未設定エラー

```
Error: Missing required environment variable: BACKLOG_API_KEY
```

**解決方法**: SAMテンプレートまたはenv.jsonで環境変数を設定

#### 3. APIキー無効エラー

```
Error: Invalid API key
```

**解決方法**: APIキーの有効期限と権限を確認

## 環境変数一覧（完全版）

| カテゴリ | 変数名 | 必須 | 説明 |
|----------|--------|------|------|
| **Slack** | | | |
| | SLACK_SIGNING_SECRET | ✓ | 署名検証用シークレット |
| | SLACK_BOT_TOKEN | ✓ | Bot OAuthトークン |
| **Backlog** | | | |
| | BACKLOG_API_KEY | ✓ | APIキー |
| | BACKLOG_SPACE | ✓ | スペース名 |
| | PROJECT_ID | ✓ | プロジェクトID |
| | ISSUE_TYPE_ID | ✓ | 課題タイプID |
| | PRIORITY_ID | | 優先度ID（デフォルト: 3） |
| **AWS** | | | |
| | AWS_REGION | | リージョン（デフォルト: ap-northeast-1） |
| | QUEUE_URL | ✓ | SQSキューURL |
| | IDEMPOTENCY_TABLE | ✓ | DynamoDBテーブル名 |
| | ENVIRONMENT | | 実行環境 |
| **デバッグ** | | | |
| | NODE_ENV | | Node環境（development/production） |
| | LOG_LEVEL | | ログレベル（debug/info/warn/error） |
| | DEBUG | | デバッグモード（true/false） |