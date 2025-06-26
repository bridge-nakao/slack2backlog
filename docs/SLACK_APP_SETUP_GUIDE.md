# Slack App設定ガイド

## 概要

このガイドでは、slack2backlogと連携するSlack Appの作成と設定方法を詳しく説明します。

## 前提条件

- Slackワークスペースの管理者権限
- AWS環境へのデプロイが完了していること（API Gateway URLが必要）

## 1. Slack Appの作成

### 1.1 新規App作成

1. [Slack API Apps](https://api.slack.com/apps)にアクセス
2. 「Create New App」をクリック
3. 「From an app manifest」を選択（推奨）

### 1.2 App Manifest設定

以下のマニフェストをコピーして使用：

```yaml
display_information:
  name: Backlog Bot
  description: Slackメッセージから自動的にBacklog課題を作成します
  background_color: "#2c3e50"
  long_description: |
    このBotは、Slackで「Backlog登録希望」というキーワードを含むメッセージを検知し、
    自動的にBacklogプロジェクトに課題を作成します。
    
    使い方:
    1. Botを任意のチャンネルに招待
    2. 「Backlog登録希望 タスクの説明」と投稿
    3. Backlogに課題が自動作成され、リンクが返信されます

features:
  bot_user:
    display_name: Backlog Bot
    always_online: true

oauth_config:
  scopes:
    bot:
      - chat:write
      - chat:write.public
      - channels:history
      - groups:history
      - im:history
      - mpim:history
      - channels:read
      - groups:read
      - im:read
      - mpim:read

settings:
  event_subscriptions:
    request_url: https://YOUR-API-GATEWAY-URL/slack/events
    bot_events:
      - message.channels
      - message.groups
      - message.im
      - message.mpim

  interactivity:
    is_enabled: false

  org_deploy_enabled: false
  socket_mode_enabled: false
  token_rotation_enabled: false
```

**注意**: `YOUR-API-GATEWAY-URL`を実際のAPI Gateway URLに置き換えてください。

### 1.3 基本設定

App作成後、以下の情報を確認・保存：

1. **Basic Information**ページ
   - App ID
   - Client ID
   - Client Secret
   - Signing Secret（重要: AWS Secrets Managerに保存）

2. **App-Level Tokens**
   - 今回の実装では不要（Event APIを使用）

## 2. OAuth & Permissionsの設定

### 2.1 OAuth Scopeの確認

以下のBot Token Scopesが設定されていることを確認：

| Scope | 説明 | 用途 |
|-------|------|------|
| `chat:write` | メッセージ送信 | Backlog課題作成後の返信 |
| `chat:write.public` | パブリックチャンネルへの投稿 | 未参加チャンネルへの返信 |
| `channels:history` | パブリックチャンネルの履歴読み取り | メッセージ検知 |
| `groups:history` | プライベートチャンネルの履歴読み取り | メッセージ検知 |
| `im:history` | DM履歴読み取り | DM対応 |
| `mpim:history` | グループDM履歴読み取り | グループDM対応 |
| `channels:read` | チャンネル情報読み取り | チャンネル情報取得 |
| `groups:read` | プライベートチャンネル情報読み取り | チャンネル情報取得 |

### 2.2 Redirect URLs

OAuth認証を使用する場合のみ設定（今回は不要）

## 3. Event Subscriptionsの設定

### 3.1 Request URL設定

1. 「Event Subscriptions」ページを開く
2. 「Enable Events」をONにする
3. Request URLに以下を入力：
   ```
   https://YOUR-API-GATEWAY-URL/slack/events
   ```

### 3.2 URL検証

URLを設定すると、Slackが自動的に検証リクエストを送信します。

検証リクエストの形式：
```json
{
  "token": "Jhj5dZrVaK7ZwHHjRyZWjbDl",
  "challenge": "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P",
  "type": "url_verification"
}
```

Lambda関数は自動的に`challenge`を返すように実装されています。

### 3.3 Subscribe to Bot Events

以下のイベントを追加：

- `message.channels` - パブリックチャンネルのメッセージ
- `message.groups` - プライベートチャンネルのメッセージ
- `message.im` - ダイレクトメッセージ
- `message.mpim` - グループダイレクトメッセージ

## 4. ワークスペースへのインストール

### 4.1 インストール手順

1. 「Install App」ページを開く
2. 「Install to Workspace」をクリック
3. 権限を確認して「許可する」をクリック

### 4.2 Bot User OAuth Token取得

インストール後、以下のトークンが発行されます：

- **Bot User OAuth Token**: `xoxb-`で始まるトークン
- AWS Secrets Managerに保存

## 5. AWS側の設定

### 5.1 Secrets Managerへの保存

```bash
# Slack認証情報を保存
aws secretsmanager create-secret \
    --name slack2backlog-slack-secrets \
    --secret-string '{
      "bot_token": "xoxb-YOUR-BOT-TOKEN",
      "signing_secret": "YOUR-SIGNING-SECRET"
    }'
```

### 5.2 環境変数の確認

Lambda関数で以下の環境変数が設定されていることを確認：

```yaml
Environment:
  Variables:
    SLACK_SIGNING_SECRET: slack2backlog-slack-secrets
    SLACK_BOT_TOKEN: slack2backlog-slack-secrets
```

## 6. 動作確認

### 6.1 Botをチャンネルに招待

```
/invite @Backlog Bot
```

### 6.2 テストメッセージ送信

```
Backlog登録希望 テスト課題の作成
```

### 6.3 期待される動作

1. Botがメッセージを検知
2. BacklogにAPIリクエストを送信
3. 課題作成成功後、スレッドに返信：
   ```
   ✅ Backlog課題を作成しました！
   
   **タイトル**: テスト課題の作成
   **URL**: https://yourspace.backlog.com/view/PROJ-123
   **担当者**: 未割り当て
   **期限**: 未設定
   ```

## 7. トラブルシューティング

### 7.1 URL検証が失敗する

**原因と対処法**：

1. **API Gateway URLが間違っている**
   - URLが正しいか確認
   - HTTPSであることを確認

2. **Lambda関数がchallenge応答していない**
   - CloudWatch Logsでエラーを確認
   - event_ingest関数のurl_verification処理を確認

3. **3秒以内に応答していない**
   - Lambda関数のコールドスタート対策
   - プロビジョンド同時実行の検討

### 7.2 イベントが受信されない

**確認項目**：

1. **Event Subscriptionsが有効か**
   ```bash
   # CloudWatch Logsで確認
   aws logs tail /aws/lambda/slack2backlog-event-ingest --follow
   ```

2. **Botがチャンネルに参加しているか**
   - `/invite @Backlog Bot`を実行

3. **必要なscopeが付与されているか**
   - OAuth & Permissionsページで確認

### 7.3 署名検証エラー

**エラーメッセージ**:
```
Invalid Slack signature
```

**対処法**：

1. **Signing Secretの確認**
   ```bash
   # Secrets Managerの値を確認
   aws secretsmanager get-secret-value \
       --secret-id slack2backlog-slack-secrets
   ```

2. **タイムスタンプの確認**
   - サーバー時刻がずれていないか確認
   - NTPサーバーとの同期

### 7.4 Botが返信しない

**確認項目**：

1. **chat:write権限**
   - OAuth & Permissionsで確認

2. **Bot Tokenが正しい**
   ```bash
   # Lambda環境変数を確認
   aws lambda get-function-configuration \
       --function-name slack2backlog-backlog-worker
   ```

3. **スレッドIDの取得**
   - thread_tsが正しく取得されているか

## 8. セキュリティベストプラクティス

### 8.1 トークン管理

1. **環境変数に直接記載しない**
   - 必ずSecrets Manager経由で取得

2. **定期的なローテーション**
   - 3ヶ月ごとにトークンを再生成

3. **最小権限の原則**
   - 必要なscopeのみ付与

### 8.2 署名検証

1. **すべてのリクエストで検証**
   - 署名なしのリクエストは拒否

2. **タイムスタンプ検証**
   - 5分以上古いリクエストは拒否

3. **定数時間比較**
   - タイミング攻撃対策

### 8.3 監査とログ

1. **アクセスログ**
   - すべてのSlackイベントをログ記録

2. **エラー監視**
   - 認証エラーをアラート

3. **使用状況分析**
   - 異常なアクセスパターンの検知

## 9. 高度な設定

### 9.1 カスタムコマンド（オプション）

Slash Commandsを追加する場合：

```yaml
slash_commands:
  - command: /backlog
    url: https://YOUR-API-GATEWAY-URL/slack/commands
    description: Backlog課題を作成
    usage_hint: "[課題のタイトル]"
    should_escape: false
```

### 9.2 インタラクティブ機能（オプション）

ボタンやメニューを追加する場合：

```yaml
interactivity:
  is_enabled: true
  request_url: https://YOUR-API-GATEWAY-URL/slack/interactive
```

### 9.3 ホームタブ（オプション）

Appホームページを追加する場合：

```yaml
features:
  app_home:
    home_tab_enabled: true
    messages_tab_enabled: true
    messages_tab_read_only_enabled: false
```

## 10. メンテナンス

### 10.1 定期確認項目

- [ ] Bot Tokenの有効期限
- [ ] API利用制限の確認
- [ ] エラーログの確認
- [ ] パフォーマンスメトリクス

### 10.2 アップデート手順

1. **マニフェストの更新**
   - App設定ページでマニフェストを編集

2. **権限の追加**
   - 新しいscopeを追加した場合は再インストール

3. **URL変更**
   - API Gateway URLが変わった場合は更新

## まとめ

このガイドに従ってSlack Appを設定することで、slack2backlogとの連携が可能になります。設定後は必ず動作確認を行い、本番環境での運用前に十分なテストを実施してください。