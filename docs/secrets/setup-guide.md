# Secrets Manager セットアップガイド

## 概要

このガイドでは、slack2backlogプロジェクトのSecrets Manager設定手順を説明します。

## 必要なシークレット

### 1. Slack Secrets
- **シークレット名**: `slack2backlog-slack-secrets-{stage}`
- **内容**:
  ```json
  {
    "bot_token": "xoxb-your-bot-token",
    "signing_secret": "your-signing-secret"
  }
  ```

### 2. Backlog Secrets
- **シークレット名**: `slack2backlog-backlog-secrets-{stage}`
- **内容**:
  ```json
  {
    "api_key": "your-backlog-api-key",
    "space_id": "your-space-id"
  }
  ```

## セットアップ手順

### 1. Slackアプリの作成

1. [Slack API](https://api.slack.com/apps)にアクセス
2. "Create New App" → "From scratch"を選択
3. App Name: `slack2backlog`
4. Workspace: 対象のワークスペースを選択

### 2. Bot Token Scopesの設定

OAuth & Permissions → Scopesで以下を追加：
- `chat:write`
- `channels:history`
- `groups:history`
- `im:history`

### 3. Event Subscriptionsの設定

1. Event Subscriptions → Enable Events: ON
2. Request URL: `https://your-api-gateway-url/slack/events`
3. Subscribe to bot events:
   - `message.channels`
   - `message.groups`
   - `message.im`

### 4. Signing Secretの取得

Basic Information → App Credentials → Signing Secret

### 5. Bot Tokenの取得

OAuth & Permissions → OAuth Tokens → Bot User OAuth Token

### 6. Backlog APIキーの取得

1. Backlogにログイン
2. 個人設定 → API → 新しいAPIキーを発行
3. メモ: `slack2backlog integration`

### 7. AWS Secrets Managerへの登録

#### CLIを使用する場合
```bash
# Slack secrets
aws secretsmanager create-secret \
    --name slack2backlog-slack-secrets-dev \
    --secret-string '{
        "bot_token": "xoxb-your-actual-token",
        "signing_secret": "your-actual-secret"
    }'

# Backlog secrets
aws secretsmanager create-secret \
    --name slack2backlog-backlog-secrets-dev \
    --secret-string '{
        "api_key": "your-actual-api-key",
        "space_id": "your-space-id"
    }'
```

#### パラメータとして渡す場合（推奨）
```bash
sam deploy --parameter-overrides \
    SlackBotToken=xoxb-your-token \
    SlackSigningSecret=your-secret \
    BacklogApiKey=your-api-key \
    BacklogSpaceId=your-space-id
```

## ローカル開発環境

### 1. .envファイルの作成
```bash
cp .env.example .env
```

### 2. .envファイルの編集
```env
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_SIGNING_SECRET=your-signing-secret
BACKLOG_API_KEY=your-api-key
BACKLOG_SPACE_ID=your-space-id
```

### 3. 環境変数の読み込み
```javascript
// Node.js
require('dotenv').config();

// または
const secrets = require('./shared/secrets-manager');
const localSecrets = secrets.getSecretsFromEnv();
```

## セキュリティベストプラクティス

### 1. アクセス制限
- 最小権限の原則に従い、必要なLambda関数のみアクセス許可
- リソースポリシーで明示的に許可

### 2. ローテーション
- 90日ごとの自動ローテーション推奨
- ローテーション時はSlack/Backlogでの再設定必要

### 3. 監査
- CloudTrailでアクセスログを監視
- 異常なアクセスパターンにアラート設定

### 4. 暗号化
- AWS管理のKMSキー（aws/secretsmanager）使用
- 必要に応じてカスタマーマネージドキーに変更

## トラブルシューティング

### シークレットが取得できない
1. IAMロールの権限確認
   ```bash
   aws iam simulate-principal-policy \
       --policy-source-arn arn:aws:iam::account:role/role-name \
       --action-names secretsmanager:GetSecretValue \
       --resource-arns arn:aws:secretsmanager:region:account:secret:name
   ```

2. シークレットの存在確認
   ```bash
   aws secretsmanager describe-secret --secret-id secret-name
   ```

3. リソースポリシーの確認
   ```bash
   aws secretsmanager get-resource-policy --secret-id secret-name
   ```

### ローカル開発でエラー
1. .envファイルの存在確認
2. 環境変数の読み込み確認
3. dotenvパッケージのインストール確認

## 関連ドキュメント
- [AWS Secrets Manager ドキュメント](https://docs.aws.amazon.com/secretsmanager/)
- [Slack API ドキュメント](https://api.slack.com/)
- [Backlog API ドキュメント](https://developer.nulab.com/ja/docs/backlog/)
