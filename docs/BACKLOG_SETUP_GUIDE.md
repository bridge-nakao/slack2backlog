# Backlog設定ガイド

## 概要

このガイドでは、slack2backlogと連携するためのBacklog側の設定方法を詳しく説明します。

## 前提条件

- Backlogアカウント（管理者権限推奨）
- 課題を作成するプロジェクトへのアクセス権限
- APIを使用できるプラン

## 1. Backlog APIキーの作成

### 1.1 APIキー作成手順

1. Backlogにログイン
2. 右上のプロフィールアイコンをクリック
3. 「個人設定」を選択
4. 左メニューから「API」を選択
5. 「新しいAPIキーを発行」をクリック
6. メモ欄に「slack2backlog」など識別しやすい名前を入力
7. 「登録」をクリック

### 1.2 APIキーの保管

発行されたAPIキーは以下の点に注意して保管：

- **一度しか表示されない**: 必ずコピーして安全な場所に保存
- **AWS Secrets Managerに保存**: 本番環境では必須
- **共有しない**: APIキーは個人に紐づく

```bash
# AWS Secrets Managerへの保存
aws secretsmanager create-secret \
    --name slack2backlog-backlog-secrets \
    --secret-string '{
      "api_key": "YOUR_API_KEY_HERE",
      "space_id": "yourspace"
    }'
```

## 2. プロジェクト設定の確認

### 2.1 プロジェクトIDの取得

#### 方法1: Web UIから確認

1. 対象プロジェクトを開く
2. 「プロジェクト設定」を開く
3. URLまたは基本設定画面でプロジェクトIDを確認

#### 方法2: APIで取得

```bash
# プロジェクト一覧を取得
curl -X GET \
  "https://yourspace.backlog.com/api/v2/projects?apiKey=YOUR_API_KEY" \
  | jq '.[] | {id, projectKey, name}'
```

出力例：
```json
{
  "id": 12345,
  "projectKey": "PROJ",
  "name": "サンプルプロジェクト"
}
```

### 2.2 課題タイプIDの取得

```bash
# 課題タイプ一覧を取得
curl -X GET \
  "https://yourspace.backlog.com/api/v2/projects/12345/issueTypes?apiKey=YOUR_API_KEY" \
  | jq '.[] | {id, name}'
```

出力例：
```json
{
  "id": 67890,
  "name": "タスク"
}
{
  "id": 67891,
  "name": "バグ"
}
```

### 2.3 優先度IDの確認（オプション）

```bash
# 優先度一覧を取得
curl -X GET \
  "https://yourspace.backlog.com/api/v2/priorities?apiKey=YOUR_API_KEY" \
  | jq '.[] | {id, name}'
```

出力例：
```json
{
  "id": 2,
  "name": "高"
}
{
  "id": 3,
  "name": "中"
}
{
  "id": 4,
  "name": "低"
}
```

## 3. 必要な権限の確認

### 3.1 プロジェクト権限

以下の権限が必要：

| 権限 | 必須/推奨 | 説明 |
|------|-----------|------|
| 課題の追加 | 必須 | 新規課題作成 |
| 課題の閲覧 | 必須 | 作成した課題の確認 |
| 課題の編集 | 推奨 | 課題の更新 |
| コメントの追加 | 推奨 | 課題へのコメント |

### 3.2 権限確認方法

プロジェクト設定 > ユーザー > 自分のユーザーを確認

## 4. Webhook設定（オプション）

Backlogからの通知をSlackに送る場合：

### 4.1 Webhook作成

1. プロジェクト設定 > インテグレーション > Webhook
2. 「Webhookを追加」をクリック
3. 以下を設定：
   - 名前: `Slack通知`
   - URL: Lambda関数のURL（別途作成が必要）
   - イベント: 課題の追加、更新など

### 4.2 Webhookペイロード例

```json
{
  "id": 1,
  "project": {
    "id": 12345,
    "projectKey": "PROJ",
    "name": "サンプルプロジェクト"
  },
  "type": 1,
  "content": {
    "id": 123,
    "key_id": 1,
    "summary": "Slackから作成された課題",
    "description": "詳細な説明"
  },
  "createdUser": {
    "id": 1,
    "name": "admin"
  },
  "created": "2024-01-01T00:00:00Z"
}
```

## 5. カスタムフィールド設定（オプション）

Slack連携用のカスタムフィールドを作成：

### 5.1 カスタムフィールド作成

1. プロジェクト設定 > カスタムフィールド
2. 「カスタムフィールドを追加」
3. 以下を設定：
   - 名前: `Slack URL`
   - タイプ: 文字列
   - 説明: 元のSlackメッセージへのリンク

### 5.2 APIでの使用

```javascript
// カスタムフィールドID取得
const customFields = await getCustomFields(projectId);
const slackUrlFieldId = customFields.find(f => f.name === 'Slack URL').id;

// 課題作成時に設定
const params = {
  projectId: PROJECT_ID,
  summary: '課題タイトル',
  issueTypeId: ISSUE_TYPE_ID,
  priorityId: 3,
  customField_12345: slackMessageUrl  // カスタムフィールドID
};
```

## 6. API利用制限

### 6.1 レート制限

| プラン | API制限 |
|--------|---------|
| フリー | 60リクエスト/分 |
| スターター | 300リクエスト/分 |
| スタンダード | 600リクエスト/分 |
| プレミアム | 1200リクエスト/分 |

### 6.2 制限への対策

```javascript
// レート制限対策の実装例
const rateLimiter = {
  queue: [],
  processing: false,
  
  async add(apiCall) {
    this.queue.push(apiCall);
    if (!this.processing) {
      this.process();
    }
  },
  
  async process() {
    this.processing = true;
    while (this.queue.length > 0) {
      const apiCall = this.queue.shift();
      await apiCall();
      await new Promise(resolve => setTimeout(resolve, 1000)); // 1秒待機
    }
    this.processing = false;
  }
};
```

## 7. 環境変数設定

### 7.1 必須環境変数

```bash
# .env ファイル
BACKLOG_API_KEY=your-api-key
BACKLOG_SPACE=yourspace.backlog.com
PROJECT_ID=12345
ISSUE_TYPE_ID=67890
PRIORITY_ID=3  # オプション（デフォルト: 中）
```

### 7.2 Lambda環境変数

```yaml
Environment:
  Variables:
    BACKLOG_API_KEY: slack2backlog-backlog-secrets
    BACKLOG_SPACE: yourspace.backlog.com
    PROJECT_ID: "12345"
    ISSUE_TYPE_ID: "67890"
    PRIORITY_ID: "3"
```

## 8. テスト方法

### 8.1 API接続テスト

```bash
# スペース情報取得
curl -X GET \
  "https://yourspace.backlog.com/api/v2/space?apiKey=YOUR_API_KEY"
```

成功時のレスポンス：
```json
{
  "spaceKey": "yourspace",
  "name": "Your Space Name",
  "ownerId": 1,
  "lang": "ja",
  "timezone": "Asia/Tokyo"
}
```

### 8.2 課題作成テスト

```bash
# テスト課題作成
curl -X POST \
  "https://yourspace.backlog.com/api/v2/issues?apiKey=YOUR_API_KEY" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "projectId=12345" \
  -d "summary=APIテスト課題" \
  -d "issueTypeId=67890" \
  -d "priorityId=3" \
  -d "description=APIからの課題作成テスト"
```

### 8.3 課題作成確認スクリプト

```bash
#!/bin/bash
# scripts/test-backlog-api.sh

API_KEY="${BACKLOG_API_KEY}"
SPACE="${BACKLOG_SPACE}"
PROJECT_ID="${PROJECT_ID}"
ISSUE_TYPE_ID="${ISSUE_TYPE_ID}"

echo "Testing Backlog API connection..."

# Test API connection
response=$(curl -s -w "\n%{http_code}" \
  "https://${SPACE}/api/v2/space?apiKey=${API_KEY}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
  echo "✓ API connection successful"
  echo "Space: $(echo $body | jq -r .name)"
else
  echo "✗ API connection failed"
  echo "HTTP Code: $http_code"
  echo "Response: $body"
  exit 1
fi

# Test issue creation
echo ""
echo "Creating test issue..."

response=$(curl -s -w "\n%{http_code}" -X POST \
  "https://${SPACE}/api/v2/issues?apiKey=${API_KEY}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "projectId=${PROJECT_ID}" \
  -d "summary=slack2backlog テスト課題 $(date +%Y%m%d%H%M%S)" \
  -d "issueTypeId=${ISSUE_TYPE_ID}" \
  -d "priorityId=3" \
  -d "description=このテスト課題は自動作成されました。")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "201" ]; then
  issue_key=$(echo $body | jq -r .issueKey)
  echo "✓ Test issue created successfully"
  echo "Issue: $issue_key"
  echo "URL: https://${SPACE}/view/${issue_key}"
else
  echo "✗ Issue creation failed"
  echo "HTTP Code: $http_code"
  echo "Response: $body"
  exit 1
fi
```

## 9. トラブルシューティング

### 9.1 よくあるエラー

#### APIキーが無効

**エラー**:
```json
{
  "errors": [
    {
      "message": "Authenticate error",
      "code": 6,
      "moreInfo": ""
    }
  ]
}
```

**対処法**:
- APIキーが正しいか確認
- APIキーが有効期限内か確認
- スペース名が正しいか確認

#### プロジェクトが見つからない

**エラー**:
```json
{
  "errors": [
    {
      "message": "No project.",
      "code": 7,
      "moreInfo": ""
    }
  ]
}
```

**対処法**:
- プロジェクトIDが正しいか確認
- APIキーのユーザーがプロジェクトにアクセス権限があるか確認

#### レート制限エラー

**エラー**:
```json
{
  "errors": [
    {
      "message": "Rate limit exceeded",
      "code": 45,
      "moreInfo": ""
    }
  ]
}
```

**対処法**:
- API呼び出し頻度を下げる
- より上位のプランへのアップグレードを検討

### 9.2 デバッグ方法

1. **CloudWatch Logsで確認**
   ```bash
   aws logs tail /aws/lambda/slack2backlog-backlog-worker --follow
   ```

2. **curlでAPI直接テスト**
   ```bash
   # 詳細なデバッグ情報付き
   curl -v -X GET \
     "https://yourspace.backlog.com/api/v2/projects?apiKey=YOUR_API_KEY"
   ```

3. **Postmanでテスト**
   - BacklogのAPIドキュメントからPostmanコレクションをインポート
   - 環境変数を設定してテスト

## 10. セキュリティベストプラクティス

### 10.1 APIキー管理

1. **環境変数として管理**
   - ソースコードに直接記載しない
   - .envファイルは.gitignoreに追加

2. **定期的なローテーション**
   - 3ヶ月ごとにAPIキーを再発行
   - 古いキーは速やかに削除

3. **最小権限の原則**
   - 必要最小限のプロジェクトのみアクセス許可
   - 読み取り専用の操作には別のAPIキーを使用

### 10.2 監査ログ

Backlogの操作履歴で以下を定期的に確認：
- APIキーによる操作
- 異常なアクセスパターン
- 大量の課題作成

## 11. パフォーマンス最適化

### 11.1 バッチ処理

複数の課題を作成する場合：

```javascript
// 効率的なバッチ処理
async function createIssuesBatch(issues) {
  const results = [];
  
  for (const issue of issues) {
    try {
      const result = await createIssue(issue);
      results.push({ success: true, data: result });
    } catch (error) {
      results.push({ success: false, error: error.message });
    }
    
    // レート制限対策
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  
  return results;
}
```

### 11.2 キャッシュ活用

```javascript
// プロジェクト情報のキャッシュ
const projectCache = new Map();

async function getProjectInfo(projectId) {
  if (projectCache.has(projectId)) {
    return projectCache.get(projectId);
  }
  
  const info = await fetchProjectInfo(projectId);
  projectCache.set(projectId, info);
  
  // 1時間後にキャッシュクリア
  setTimeout(() => projectCache.delete(projectId), 3600000);
  
  return info;
}
```

## まとめ

このガイドに従ってBacklogを設定することで、slack2backlogとの連携が可能になります。APIキーは安全に管理し、定期的な動作確認を行うことで、安定した運用が可能です。