## 仕様書 — Slack → Backlog 課題登録 Bot（AWS Lambda 版）

> **目的**
>  Slack ワークスペース内の複数チャンネルを監視し、メッセージ本文に **「Backlog登録希望」** を含む投稿のみ Backlog に課題として登録し、結果をスレッドに返信する。
>  ※本書は **Codex / ClaudeCode** 等でプログラム自動生成を行う前提で、要素を網羅的に示す。

------

### 1. 全体アーキテクチャ

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

- **非同期 2 段構成**
   `event_ingest` が 200 OK を即時返却→SQS に投入し、`backlog_worker` が実処理。Slack の *3 秒* 制限を確実にクリアしつつ、Backlog 側の遅延やリトライも分離。([api.slack.com](https://api.slack.com/apis/events-api?utm_source=chatgpt.com))
- **署名検証**：`X-Slack-Signature` / `X-Slack-Request-Timestamp` を HMAC-SHA256 で照合。
- **コスト最適化**：両 Lambda のメモリ 512 MB・タイムアウト 10 s、`backlog_worker` は予備同時実行 1 でコールドスタート低減（必要なら *Provisioned Concurrency* に切替）。

------

### 2. 機能要件

| #     | 要件                                                         |
| ----- | ------------------------------------------------------------ |
| FR-1  | 監視対象は **workspace 全体**。イベントタイプ `message.channels` / `message.groups` / `message.im` を購読。 |
| FR-2  | メッセージ本文に **完全一致または前方一致**で `"Backlog登録希望"` が含まれる場合のみ処理対象。 |
| FR-3  | Backlog 課題登録に必要な `projectId`, `summary`, `issueTypeId`, `priorityId` を組み立てて **POST `/api/v2/issues`** を呼び出す。([developer.nulab.com](https://developer.nulab.com/ja/docs/backlog/api/2/add-issue/?utm_source=chatgpt.com)) |
| FR-4  | 登録成功時は元メッセージの **スレッド**に「課題 ABC-123 を登録しました」(issueKey) を投稿。 |
| FR-5  | 失敗時はスレッドにエラー要約を送信し、CloudWatch Logs に詳細スタックトレースを出力。 |
| NFR-1 | 署名検証失敗、チャネル権限不足、Backlog 4xx/5xx は **リトライ 3 回** → SQS DLQ へ隔離。 |
| NFR-2 | 受信から Slack への ACK まで **1 秒未満 p95**。              |
| NFR-3 | 月 10 万件のメッセージで **月額コスト < ¥500** を目標。      |

------

### 3. AWS リソース定義（IaC 例示）

| リソース                   | 主要設定                                                     |
| -------------------------- | ------------------------------------------------------------ |
| **API Gateway** (REST)     | POST `/slack/events` → Lambda プロキシ統合カスタムドメイン `api.example.com` (ACM) |
| **Lambda: event_ingest**   | Runtime Node.js 20 / Python 3.12環境変数: `SLACK_SIGNING_SECRET`, `SQS_URL` |
| **Lambda: backlog_worker** | Runtime 同上環境変数: `BACKLOG_API_KEY`, `BACKLOG_SPACE`, `PROJECT_ID`, ほか |
| **SQS**                    | 標準キュー (VisibilityTimeout 60 s)DLQ 14 日保持             |
| **Secrets Manager**        | Bot Token / Signing Secret / Backlog API Key                 |
| **IAM**                    | *Execution Role* は `AWSLambdaBasicExecutionRole` + SQS / Secrets **最小権限** |

*(CloudFormation/SAM/CDK の具体的なテンプレート断片は生成対象とするため省略)*

------

### 4. 環境変数・シークレット一覧

| 名称                        | 用途                    | 設定例                     |
| --------------------------- | ----------------------- | -------------------------- |
| SLACK_BOT_TOKEN             | Web API 用 Bot トークン | `xoxb-***`                 |
| SLACK_SIGNING_SECRET        | 署名検証                | `abcd1234`                 |
| BACKLOG_API_KEY             | 課題登録 API キー       | `************************` |
| BACKLOG_SPACE               | スペース名              | `example.backlog.com`      |
| PROJECT_ID                  | デフォルト projectId    | `12345`                    |
| ISSUE_TYPE_ID / PRIORITY_ID | ID マッピング           | `67890`                    |

------

### 5. デプロイ手順（CLI ベース）

1. **リポジトリ準備**

   ```bash
   git clone git@github.com:yourorg/backlog-slack-bot.git
   cd backlog-slack-bot
   ```

2. **IaC スタック作成**

   ```bash
   sam build && sam deploy --guided
   # or
   cdk deploy
   ```

3. **Slack App 設定**

   - Event Subscriptions ON → Request URL: `https://api.example.com/slack/events`
   - Subscribe: `message.channels`, `message.groups`, `message.im`
   - Bot Token Scopes: `chat:write`, `channels:history`, `groups:history`, `im:history` など
   - 再インストールしてトークン取得 → Secrets Manager に登録

4. **環境変数更新**

   ```bash
   aws lambda update-function-configuration \
     --function-name backlog_worker \
     --environment "Variables={BACKLOG_API_KEY=****,PROJECT_ID=12345,...}"
   ```

5. **動作確認**

   - 任意チャンネルで `Backlog登録希望 テスト課題` と投稿
   - スレッド返信と Backlog 課題生成を確認

------

### 6. 参考イベントペイロード（要約）

```json
{
  "token": "verification_token",
  "team_id": "T123",
  "event": {
    "type": "message",
    "text": "Backlog登録希望 API バグ修正",
    "user": "U456",
    "channel": "C789",
    "ts": "1627048492.000200"
  }
}
```

------

### 7. エラーハンドリングと冪等性

| ケース                        | 対応                                                        |
| ----------------------------- | ----------------------------------------------------------- |
| **重複呼び出し** (Slack 再送) | `event.event_id` を DynamoDB で 24 h 保持し、二重登録を防止 |
| **Backlog 429/5xx**           | Exponential back-off (1, 3, 9 s) 最大 3 回 → DLQ            |
| **JSON 解析失敗**             | 400 ログ出力のみ、Slack 返信なし                            |

------

### 8. テスト戦略

- **ユニット**：キーワード判定 / 署名検証 / Backlog リクエスト生成
- **統合**：API Gateway → Lambda 連携 (SAM local)、SQS 経由ワークフロー
- **負荷**：Artillery で 100 req/s, 1 min、p95 < 2 s を確認（コールドスタートを含む）(Uncertain)

------

### 9. 今後の拡張候補

1. **キーワード拡張**：正規表現や `/backlog create` スラッシュコマンド対応
2. **ファイル添付**：Slack ファイルを Backlog 添付ファイル API へ転送
3. **ステータス通知**：Backlog コメント更新を Slack スレッドへ webhook 返信

------

#### 付録 A. 処理シーケンス図 (テキスト)

```plain
Slack → API GW → Lambda(event_ingest) → 200 OK
                            │
                            └──▶ SQS ▶ Lambda(backlog_worker)
                                          ├─ POST issue
                                          └─ chat.postMessage
```

------

**備考**

- Lambda コールドスタートは Node.js/Python で *200–800 ms* 程度が一般値 (Uncertain)。
- Slack の 3 秒 ACK 制限は公式ドキュメントで明示されている。([api.slack.com](https://api.slack.com/apis/events-api?utm_source=chatgpt.com))
- Backlog 課題追加エンドポイントは `/api/v2/issues`。([developer.nulab.com](https://developer.nulab.com/ja/docs/backlog/api/2/add-issue/?utm_source=chatgpt.com))

以上を Codex / ClaudeCode に渡せば、リソース作成・ハンドラ実装・CI/CD スクリプト自動生成まで可能です。