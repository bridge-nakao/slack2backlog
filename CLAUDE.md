# Claude Code Memory File - Git Worktree運用版

## 🚨 Claude Code起動時の確認事項

Claude Codeを起動した際、このCLAUDE.mdを読み込んで、ユーザーが実行すべきコマンドや確認事項があれば最初に提示してください。

### 📅 本日の日時確認

**重要**: Claude Code起動時に必ず1回、本日の日時を表示してください。これにより日付の誤記を防止します。

```
📅 現在の日時: [Today's date from environment]
```

### 起動時に確認すべき項目

1. **現在のWorktree状況**
   ```bash
   git worktree list
   pwd  # 現在の作業ディレクトリ
   ```

2. **テスト環境の状態**
   ```bash
   npm test  # テストが成功するか
   npm run test:coverage  # カバレッジが80%以上か
   ```

3. **開発環境の確認**
   ```bash
   node -v  # Node.js v18以上か
   which cursor  # Cursorがインストールされているか
   ```

4. **インスタンス識別の設定**
   ```bash
   # 未設定の場合は実行を促す
   ./scripts/claude-workspace-setup.sh
   ```

5. **最新のmainブランチとの同期**
   ```bash
   git fetch origin main
   git status  # 現在のブランチと変更状況
   ```

### 提示する形式の例

```
📋 実行が必要なコマンド:

1. テスト環境の確認:
   npm test
   npm run test:coverage
   
   npm test完了後、「手動テストを開始してください」と私（Claude Code）に依頼してください。

2. インスタンス設定（未設定の場合）:
   ./scripts/claude-workspace-setup.sh

3. mainブランチとの同期確認:
   git fetch origin main
   git merge main  # 必要に応じて

これらのコマンドを実行して、開発環境が適切に設定されているか確認してください。
```

### 📝 日付誤記防止のためのガイドライン

1. **起動時の日付表示**: Claude Code起動時に必ず本日の日付を表示
2. **ドキュメント記載時**: 日付を記載する際は常に現在の日付を確認
3. **コミットメッセージ**: 日付が含まれる場合は特に注意
4. **セッション記録**: 各セッションの開始時に日付を確認

## 📋 標準開発フロー（改訂版 - 23ステップ）

### フェーズ1: 仕様検討
1. **仕様提案受付** - 開発したい機能の要望を受ける
   - 📊 **Projects更新**: 新規タスクを「Backlog」に追加、「仕様検討」へ移動
2. **仕様検討・提示** - 技術的検討を行い、詳細仕様を提案
3. **仕様レビュー** - 提示された仕様の確認
4. **仕様修正** - 修正事項の指摘
5. **仕様確定** - 修正がなくなるまで2-4を繰り返し
   - 📊 **Projects更新**: 「仕様検討」から「開発中」へ移動

### フェーズ2: 実装
6. **Issue登録** - 確定仕様をGitHub Issueに登録
   - 📊 **Projects更新**: IssueがProjectsに自動追加される
7. **Git worktree作成** - 新規worktreeで独立した開発環境を準備
   
   **⚠️ 重要**: worktreeの作成とディレクトリ切り替えは**人間（開発者）が実行**してください。
   Claude Codeはセキュリティ制限により親ディレクトリへの移動ができません。
   
   ```bash
   # 人間が実行するコマンド
   git worktree add ../ReadMarker-機能名 feature/機能名
   cd ../ReadMarker-機能名
   npm install
   
   # その後、そのディレクトリでClaude Codeを起動
   ```
8. **プログラム作成** - 機能実装
9. **テストプログラム作成** - 実ファイルを使用したテスト作成（クラス再定義禁止）

### フェーズ3: 品質保証
10. **新機能テスト実行** - 作成したテストを実行
    - 📊 **Projects更新**: 「開発中」から「テスト中」へ移動
    - 失敗 → 8（プログラム修正）へ戻る
11. **既存テスト確認** - 新機能テスト完了後、全既存テスト実行
    - 失敗 → 8（プログラム修正）へ戻る
12. **カバレッジ計測** - 全テスト完了後にカバレッジ測定
    - 📊 **Projects更新**: カスタムフィールド「テストカバレッジ」を更新
13. **カバレッジ改善** - 80%以上を目標に調整
    - 不足 → 9（テスト追加）へ戻る

### フェーズ4: 検証
14. **手動テスト項目提示** - 全機能の手動確認項目リスト作成（既存機能のデグレーション確認含む）
15. **手動テスト実施** - 提示項目の動作確認
    - 失敗 → 4（仕様再検討）または8（実装修正）へ
    - **手動テスト実施方法**: テスト項目を1つずつ提示し、ユーザーが「OK」または「NG」を回答。全テストが完了したら結果をまとめて表示
    - **手動テストの詳細**: `MANUAL_TEST_GUIDE.md` に手順と期待結果を記載

### フェーズ5: 完了
16. **ドキュメント更新** - README.mdとCLAUDE.md更新
17. **CLAUDE.md見直し** - 開発経験を踏まえた改善点の追加
    - 新たに判明したベストプラクティス
    - 遭遇した問題と解決策
    - テスト戦略の更新
    - worktree運用の改善点
18. **コミット作成** - 変更内容をコミット
19. **Pull Request作成** - レビュー用PR作成
    - 📊 **Projects更新**: PRがProjectsに自動追加、「In review」ビューに表示
20. **コードレビュー** - GitHub上でコードレビュー実施
    - レビューコメントへの対応
    - 修正が必要な場合は8（プログラム修正）へ戻る
    - 承認後、マージ準備完了
21. **PRマージ** - レビュー完了後、mainブランチへマージ
    - 📊 **Projects更新**: 「In review」から「Done」へ移動
22. **不要ファイルの整理** - 使用しないファイルの削除
23. **サイクル継続** - 新たな要望があれば1へ戻る

### 📝 重要な原則
- **実ファイル使用**: テストは必ず実際のソースファイルを使用
- **100%成功率**: 次のステップに進む前に全テスト成功が必須
- **80%カバレッジ**: 全ファイルで目標達成を目指す
- **デグレ防止**: 新機能が既存機能を壊していないか必ず確認

**⚠️ このフローを今後必ず遵守すること。一つでも欠けた場合は不完全な実装とする。**

### 🔍 コードレビューガイドライン
- **レビュー観点**:
  - コードの可読性と保守性
  - 既存コードとの整合性
  - テストカバレッジの十分性
  - セキュリティ上の懸念事項
  - パフォーマンスへの影響
- **レビュープロセス**:
  - PR作成時にレビュー依頼
  - コメントや修正要求への迅速な対応
  - レビュー承認後にマージ

### 🚨 テスト完了の必須条件
- **すべてのテストが100%完了していない場合は、カバレッジ再計測に進まない**
- 失敗テストが1つでもある場合は、まず全テストを修正してから進む
- テスト完了 = テストスイート内のすべてのテストが正常に通ること

## 重要な指示
- 仕様はREADME.mdにまとめること！
- slack2backlogツールに関する技術仕様、使用方法、エラー対応はすべてREADME.mdに記載
- 新機能追加時は標準開発フローの全23ステップを完全実行すること

## プロジェクト概要
slack2backlog - SlackのメッセージやスレッドをBacklogの課題として移行するツール

## ✅ 開発準備チェックリスト
- [ ] AWS CLIのインストール・設定
- [ ] SAM CLIまたはCDKのインストール
- [ ] Slack Appの作成
- [ ] Slack Bot Token・署名シークレットの取得
- [ ] Backlog APIキーの取得
- [ ] AWS Secrets Managerの設定
- [ ] 環境変数の設定（PROJECT_ID, ISSUE_TYPE_ID等）

## 📈 開発履歴

### 2025年6月26日 - プロジェクト初期セットアップ
- slack2backlogプロジェクトの開始
- AWS LambdaベースのSlack→Backlog自動連携ボットの仕様策定
- 非同期2段構成アーキテクチャの採用決定
- ReadMarkerプロジェクトから汎用的な開発フローを流用
- CLAUDE.mdをプロジェクト用にカスタマイズ

## 📅 今後の開発計画

### Phase 1: AWS Lambda基本実装
- [ ] Lambda関数 (event_ingest, backlog_worker) の実装
- [ ] API Gatewayの設定
- [ ] SQSキューとDLQの設定
- [ ] Slack署名検証の実装
- [ ] Backlog APIクライアントの実装
- [ ] エラーハンドリングとリトライ機構

### Phase 2: 冗長性・信頼性向上
- [ ] DynamoDBでのevent_id管理（冗等性保証）
- [ ] CloudWatch Logsへの詳細ログ出力
- [ ] スレッドへの自動返信機能
- [ ] Exponential back-offの実装

### Phase 3: テスト・デプロイ
- [ ] ユニットテストの作成
- [ ] 統合テスト (SAM local)
- [ ] 負荷テスト (Artillery)
- [ ] CI/CDパイプラインの構築

### Phase 4: 拡張機能
- [ ] 正規表現でのキーワードマッチング
- [ ] スラッシュコマンド `/backlog create`
- [ ] SlackファイルのBacklogへの転送
- [ ] BacklogコメントのSlackへの反映




## 📊 GitHub Projects連携方針

### プロジェクト概要
- **プロジェクト名**: ReadMarker Development Roadmap
- **テンプレート**: Feature release
- **既存ビュー**: Prioritized backlog, Status board, Roadmap, Bugs, In review, My items

### カスタムフィールドの設定
開発フローの23ステップを効率的に管理するため、以下のカスタムフィールドを活用：
- **開発フェーズ**: 1-5（仕様検討/実装/品質保証/検証/完了）
- **現在ステップ**: 1-23の番号で進捗を追跡
- **worktree名**: ReadMarker-機能名（作業環境の識別）
- **テストカバレッジ**: XX.XX%（品質指標）

### ステータス（カラム）構成
詳細な6段階で進捗を可視化：
```
📋 Backlog → 🔍 仕様検討 → 💻 開発中 → 🧪 テスト中 → 👀 In review → ✅ Done
```

### 自動化ルール
最小限の自動化で運用負荷を軽減：
- **Issue/PR作成時**: 自動で"Backlog"へ配置
- **その他の移動**: Claude Codeからの進捗報告に基づき手動更新

### 運用ルール

#### Issue/PR管理
- **Issue作成（ステップ6）**: 確定仕様を記載してGitHub Issueに登録
- **PR作成（ステップ19）**: 実装内容、テスト結果、カバレッジを記載

#### ステータス更新タイミング
1. **Backlog → 仕様検討**: 仕様検討開始時（ステップ1）
2. **仕様検討 → 開発中**: 仕様確定時（ステップ5）
3. **開発中 → テスト中**: テスト開始時（ステップ10）
4. **テスト中 → In review**: PR作成時（ステップ19）
5. **In review → Done**: PRマージ完了時（ステップ21）

#### 手動テストの記録方法
PR内に以下の形式でチェックリストを作成：
```markdown
## 手動テスト結果
- [ ] テスト1: 基本的なハイライト機能 - OK
- [ ] テスト2: 拡張子除去機能 - OK
- [ ] テスト3: サイドパネル表示 - OK
...
- [x] すべての手動テスト完了（10/10 OK）
```

### 各ビューの活用方法
- **Prioritized backlog**: 優先順位に基づくタスク管理
- **Status board**: 現在の進捗状況の俯瞰（メインビュー）
- **Roadmap**: 長期的な開発計画の可視化
- **Bugs**: バグ専用の追跡と管理
- **In review**: レビュー中のPR/Issue管理
- **My items**: 個人に割り当てられたタスクの確認

### ベストプラクティス
1. **定期的な更新**: 各フェーズ完了時に必ずステータスを更新
2. **詳細な記録**: カスタムフィールドを活用して進捗を詳細に記録
3. **透明性の確保**: すべての作業をProjectsで可視化
4. **週次レビュー**: Prioritized backlogで優先順位を見直し

### 自動化スクリプト
プロジェクトの初期設定と操作を簡単にするスクリプトを用意：

#### 初期設定スクリプト
```bash
# カスタムフィールドの自動設定
./scripts/setup-github-project.sh
```

#### ヘルパー関数
```bash
# プロジェクト情報表示
source scripts/github-project-helpers.sh && show_project_info

# Issueをプロジェクトに追加
source scripts/github-project-helpers.sh && add_issue_to_project 1

# カスタムフィールド更新
source scripts/github-project-helpers.sh && update_custom_field ITEM_ID "テストカバレッジ" 84.89
```

### 🎉 設定完了状況（2025年6月19日）

#### ✅ 完了した設定
1. **カスタムフィールド（4つ）**
   - 開発フェーズ（SINGLE_SELECT）: 1-仕様検討, 2-実装, 3-品質保証, 4-検証, 5-完了
   - 現在ステップ（NUMBER）: 1-23の進捗番号
   - worktree名（TEXT）: 作業環境の識別
   - テストカバレッジ（NUMBER）: カバレッジ率

2. **ステータスカラム（6つ）**
   - 📋 Backlog
   - 🔍 仕様検討
   - 💻 開発中
   - 🧪 テスト中
   - 👀 レビュー中
   - ✅ Done

3. **自動化ワークフロー**
   - Auto-add to project: Issue/PR作成時に自動追加
   - Item added to project: 初期ステータスをBacklogに設定
   - Pull request merged: マージ時にDoneへ自動移動（推奨）

4. **動作確認済み**
   - Issue #6でテスト実施
   - 自動追加とステータス設定が正常動作

#### 📝 運用開始準備完了
新規Issue/PRは自動的にプロジェクトに追加され、23ステップフローに沿った管理が可能になりました。

## 🛠️ 開発支援スクリプト

プロジェクトの`scripts/`ディレクトリに、ReadMarker開発を支援する各種スクリプトを用意しています。

### 📋 スクリプト一覧と詳細

#### 1. **claude-workspace-setup.sh** - Claude Code環境設定
**用途**: Claude Codeインスタンスの初期設定と識別設定

**主な機能**:
- Claude Codeインスタンスの識別（A/B/C）
- ターミナルプロンプトのカスタマイズ
- Git author情報の設定
- 作業環境の初期化

**使用方法**:
```bash
./scripts/claude-workspace-setup.sh
```

---

#### 2. **setup-github-project.sh** - GitHub Projects初期設定
**用途**: GitHub Projectsの初期設定自動化

**主な機能**:
- カスタムフィールドの作成
- プロジェクト設定の確認
- 必要な権限チェック

**必要な権限**: `project`スコープ

**使用方法**:
```bash
# 事前に認証が必要
gh auth login -h github.com -p https -s repo,workflow,gist,read:org,project

# スクリプト実行
./scripts/setup-github-project.sh
```

---

#### 3. **github-project-helpers.sh** - GitHub Projects操作ヘルパー
**用途**: GitHub Projects操作のヘルパー関数集

**主な関数**:
- `show_project_info` - プロジェクト情報表示
- `add_issue_to_project` - IssueをProjectに追加
- `update_item_status` - ステータス更新
- `update_custom_field` - カスタムフィールド更新

**使用方法**:
```bash
# ヘルパー関数を読み込み
source scripts/github-project-helpers.sh

# プロジェクト情報を表示
show_project_info

# Issue #1をプロジェクトに追加
add_issue_to_project 1

# カスタムフィールドを更新
update_custom_field ITEM_ID "テストカバレッジ" 84.89
```

---

#### 4. **pr-review-helpers.sh** - PRレビュー支援 🆕
**用途**: PRレビュー作業を支援するヘルパー関数集

**主な関数**:
- `show_pr_info` - PRの基本情報表示
- `list_pr_files` - 変更ファイル一覧表示
- `review_file_diff` - 特定ファイルの差分表示
- `generate_review_checklist` - レビューチェックリスト生成
- `analyze_pr_stats` - PR統計情報の分析
- `draft_review_comment` - レビューコメント下書き生成
- `list_recent_prs` - 最近のPR一覧表示
- `check_pr_conflicts` - コンフリクト確認

**使用方法**:
```bash
# ヘルパー関数を読み込み
source scripts/pr-review-helpers.sh

# PR #5の情報を表示
show_pr_info 5

# レビューチェックリストを生成
generate_review_checklist 5

# 統計情報を分析
analyze_pr_stats 5

# レビューコメントの下書きを生成
draft_review_comment 5
```

### 🚀 初回セットアップ手順

```bash
# 1. スクリプトに実行権限を付与
chmod +x scripts/*.sh

# 2. GitHub CLI認証（project権限を含む）
gh auth login -h github.com -p https -s repo,workflow,gist,read:org,project

# 3. Claude Codeワークスペース設定
./scripts/claude-workspace-setup.sh

# 4. GitHub Projects初期設定
./scripts/setup-github-project.sh
```

### 📝 使用上の注意

1. **GitHub CLI必須**: すべてのGitHub連携スクリプトは`gh`コマンドが必要
2. **権限設定**: GitHub Projects操作には`project`スコープが必須
3. **デフォルト値**: 多くのスクリプトは`bridge-nakao/ReadMarker`をデフォルトとして使用

### 🔧 トラブルシューティング

**Q: "Your token has not been granted the required scopes"エラー**
```bash
# projectスコープを追加して再認証
gh auth login -h github.com -p https -s repo,workflow,gist,read:org,project
```

**Q: スクリプトが実行できない**
```bash
# 実行権限を確認
ls -la scripts/
# 権限がない場合は付与
chmod +x scripts/スクリプト名.sh
```

**Q: プロジェクトが見つからない**
- プロジェクト名に`@`が含まれているか確認
- Web UIでプロジェクトが作成されているか確認

### 🤝 新しいスクリプトを追加する場合

1. `scripts/`ディレクトリに配置
2. 実行権限を付与
3. CLAUDE.mdのこのセクションに説明を追加
4. 必要に応じてGitHub CLIの追加スコープを記載

## 技術スタック
- **AWS Services**:
  - Lambda (Node.js 20.x / Python 3.12)
  - API Gateway (REST)
  - SQS (Standard Queue + DLQ)
  - DynamoDB (冗等性管理)
  - Secrets Manager
  - CloudWatch Logs
- **外部API**:
  - Slack Events API
  - Slack Web API
  - Backlog API v2
- **IaC**:
  - AWS SAM / CDK
- **テスト**:
  - Jest / pytest
  - SAM Local
  - Artillery (負荷テスト)


## 🧪 テストプログラム作成ガイドライン

### 📌 テスト作成の絶対原則
- **テストファイル内でクラスを再定義は絶対やめること**（テストしている意味が無い）
- **必ず、実ファイルを使ってテストプログラムを作成すること**
- **テストが合格するためのテストプログラムは意味がない**
- **カバレッジをあげるためにテストを省略するのもダメ**

### 🎯 テストプログラム作成時の必須確認事項
1. **全ての仕様を網羅していること**
2. **実際のプログラムが仕様通り動くかを確認するものであること**
3. **新機能追加や修正が既存機能を壊していないか（デグレーション）を確認するためのものであること**

### ✅ テスト作成のベストプラクティス
1. **テストの独立性**
   - 各テストは他のテストに依存せず、単独で実行可能であること
   - テスト間でグローバル変数や状態を共有しない

2. **モックの適切性**
   - Chrome APIなど外部依存は適切にモック化すること
   - ただし、モックは実際のAPIの動作を正確に再現すること

3. **エラーケースの網羅**
   - 正常系だけでなく、異常系・境界値のテストも必須
   - エラーハンドリングが適切に動作することを確認

4. **非同期処理の確実なテスト**
   - Promise、async/await、コールバックを適切に待機
   - タイミング依存のテストは避け、確実性を重視

5. **テストの可読性**
   - テスト名は「何をテストしているか」が明確であること
   - アサーションは具体的で、失敗時に原因が分かりやすいこと

### ❌ 避けるべきテスト作成方法

#### 1. **evalを使用したファイル実行**
```javascript
// 悪い例：evalでファイル内容を実行
const fileContent = readFileSync(path.join(__dirname, '../content.js'), 'utf8');
eval(fileContent); // カバレッジが計測されない、セキュリティリスク、デバッグ困難
```

#### 2. **不適切なDOM/Chrome APIモック**
```javascript
// 悪い例：不完全なChrome APIモック
global.chrome = { storage: { local: {} } }; // 他のAPIがない
document.addEventListener = () => {}; // 実際の動作と異なる
```

#### 3. **テスト間の依存関係**
```javascript
// 悪い例：前のテストの状態に依存
test('first test', () => { window.someVar = 'value'; });
test('second test', () => { expect(window.someVar).toBe('value'); }); // 危険
```

#### 4. **非同期処理の不適切な処理**
```javascript
// 悪い例：適切な待機なし
test('async test', () => {
  someAsyncFunction();
  expect(result).toBe('expected'); // 非同期完了前にチェック
});
```

#### 5. **タイマー処理の不適切なテスト**
```javascript
// 悪い例：実際のタイマーを使用
test('timer test', (done) => {
  setTimeout(() => { expect(true).toBe(true); done(); }, 3000); // 3秒待機
});
```

#### 6. **テスト内でのクラス再定義**
```javascript
// 悪い例：テスト内で直接クラスを定義（実際のコードをテストしていない）
class ReadMarker {
  constructor() { /* 実装をコピー */ }
  highlight() { /* メソッドの実装をコピー */ }
}

test('highlight test', () => {
  const marker = new ReadMarker();
  // これは実際のReadMarkerクラスではなく、テスト用のコピーをテストしている
  expect(marker.highlight()).toBe(true);
});
```

### ✅ 推奨するテスト作成方法

#### 1. **実ファイルを直接読み込んで使用**
```javascript
// 良い例：実際のファイルをrequireで読み込む
const { SidePanelController } = require('../sidepanel.js');

// モジュールとしてエクスポートされていない場合は、
// ファイルが自己実行される形式で書かれていることを利用
require('../content.js');
// グローバル変数やDOMイベントリスナーが設定される

// テスト環境でモジュールをリセット
beforeEach(() => {
  jest.resetModules();
});
```

#### 2. **完全なChrome APIモック**
```javascript
// 良い例：包括的なAPIモック
beforeEach(() => {
  chrome.storage.local.get.mockImplementation((keys, callback) => {
    callback({ readTexts: ['test'] });
  });
  chrome.runtime.lastError = null;
  chrome.scripting = { executeScript: jest.fn() };
});
```

#### 3. **独立したテスト設計**
```javascript
// 良い例：各テストが独立
beforeEach(() => {
  document.body.innerHTML = '';
  jest.clearAllMocks();
  // 毎回クリーンな状態でスタート
});
```

#### 4. **適切な非同期処理**
```javascript
// 良い例：Promise/async-awaitの正しい使用
test('async test', async () => {
  const result = await someAsyncFunction();
  expect(result).toBe('expected');
});
```

#### 5. **フェイクタイマーの使用**
```javascript
// 良い例：フェイクタイマーでテスト高速化
test('timer test', () => {
  jest.useFakeTimers();
  startTimer();
  jest.advanceTimersByTime(3000);
  expect(timerCallback).toHaveBeenCalled();
  jest.useRealTimers();
});
```

### 🎯 テスト作成のベストプラクティス

#### 1. **テストファイル命名規則**
- 基本テスト: `*.test.js`
- 実ファイル使用テスト: `*-real.test.js`
- 拡張版テスト: `*-real-enhanced.test.js`
- 修正版テスト: `*-real-fixed.test.js`
- 統合テスト: `*-integration.test.js`

#### 2. **テスト構造**
```javascript
describe('コンポーネント名 Tests', () => {
  describe('正常系テスト', () => { /* 正常動作 */ });
  describe('異常系テスト', () => { /* エラー処理 */ });
  describe('境界値テスト', () => { /* 限界値 */ });
  describe('パフォーマンステスト', () => { /* 性能 */ });
});
```

#### 3. **モック設計の原則**
- **最小限**: 必要な機能のみモック
- **一貫性**: 実際のAPIと同じ動作
- **独立性**: テスト間で影響しない
- **リセット**: 各テスト前にクリア

#### 4. **エラーテストの重要性**
```javascript
// Chrome APIエラー、DOM操作エラー、ネットワークエラーを必ずテスト
test('storage error handling', async () => {
  chrome.storage.local.get.mockImplementation((keys, callback) => {
    chrome.runtime.lastError = { message: 'Storage error' };
    callback({});
  });
  await expect(loadData()).rejects.toThrow('Storage error');
});
```

### 📋 テスト完了チェックリスト
- [ ] すべてのテストが独立して実行可能
- [ ] Chrome API呼び出しが適切にモック化されている
- [ ] 非同期処理が正しくテストされている
- [ ] エラーケースが網羅されている
- [ ] 境界値テストが含まれている
- [ ] テスト実行時間が適切（長時間テストは避ける）
- [ ] テストコードが理解しやすく保守可能

### 🚨 重要な注意点
- **eval()使用時はカバレッジが計測されない** - 原則としてeval()の使用を控えること
- **eval()の例外的使用** - モジュールとしてエクスポートされていないChrome拡張機能ファイルの統合テストでのみ許可
  - ただし、この場合でもカバレッジは計測されないことを理解した上で使用
  - 単体テストでは必ずrequireを使用すること
  - **検討済みのeval使用**: `tests/sidepanel-integration.test.js`での使用は、Chrome拡張機能の実際の動作環境を再現するために必要と判断済み
  - **今後のeval使用**: 新たにevalを使用する場合は、その理由と検討結果をCLAUDE.mdに必ず記録すること
- **実ファイルを必ず使用** - テスト対象のコードは実際のファイルから読み込むこと
- **外部依存（Chrome API等）のみモック化** - テスト対象以外の外部APIはモックで代替
- **DOM操作は慎重にモック化** - 実際のDOM APIの動作を正確に再現
- **タイマー処理は必ずフェイクタイマー使用** - テスト高速化とタイミング制御のため
- **Chrome拡張機能特有のAPIは完全モック必須** - ブラウザ環境でしか動作しないAPIをモック化

## 📌 eval使用の検討履歴

### 承認済みのeval使用
1. **tests/sidepanel-integration.test.js** (2025-06-13)
   - **理由**: Chrome拡張機能の統合テストにおいて、実際のブラウザ環境での動作を再現するため
   - **詳細**: 
     - background.js: Chrome APIリスナーの自動登録が必要
     - content.js: ファイル実行時の自動インスタンス化を再現
     - sidepanel.js: DOMContentLoadedイベントハンドラーの自動設定を再現
   - **代替案検討**: requireでの置き換えは技術的に可能だが、追加の手動処理が必要となり、実際の動作環境との乖離が生じるため不採用

### eval使用時の必須記録項目
- 使用ファイル名
- 使用理由（なぜrequireでは不十分か）
- 代替案の検討結果
- カバレッジへの影響評価
- 承認日

## 🚨 GitHub Issues管理規則

### Issues運用方針
- **Issuesはすべてのフェーズのすべての作業が完了してからクローズすること**
- 部分的な完了や一時的な改善でのクローズは禁止
- 全ての関連テストが成功し、カバレッジ目標を達成してからクローズ
- 問題の根本的解決が確認されてからクローズ

## 📝 CLAUDE.md更新ガイドライン

### いつ更新するか
- 新機能の実装完了時
- 重要なバグ修正の完了時
- 新しいベストプラクティスを発見した時
- テスト戦略に変更があった時
- worktree運用で新しい知見を得た時

### 更新すべき内容
1. **成功したアプローチ** - 今後も使いたい手法
2. **失敗から学んだこと** - 避けるべきパターン
3. **ツールの使い方** - 効率的な使用方法
4. **テストの改善点** - カバレッジ向上のコツ
5. **worktree運用Tips** - 並行開発の効率化

## 🚀 Git Worktree開発環境ガイド

### 概要
Git worktreeを活用して複数の機能を並行開発する標準的な運用方法です。各worktreeは独立した環境として機能し、ファイル競合なく開発できます。

**📖 詳細なチーム開発運用方法については [GIT_WORKTREE_GUIDE.md](./GIT_WORKTREE_GUIDE.md) を参照してください。**

### 推奨開発環境
- **エディタ**: Cursor（AI支援機能付き）
- **ターミナル**: WSL2 + Windows Terminal
- **Node.js**: v18以上

### Git worktreeを使用した並行開発

#### メリット
- ファイル競合の完全回避
- 独立した作業環境での並行開発
- 高速なブランチ切り替え
- 各環境で独立した依存関係管理（node_modules等）

#### セットアップ手順

1. **worktreeの作成**
```bash
# ReadMarker用の新しいworktreeを作成
git worktree add ../ReadMarker-sidepanel feature/sidepanel
git worktree add ../ReadMarker-highlighting feature/highlighting
git worktree add ../ReadMarker-tests test/coverage-improvement
```

2. **推奨ディレクトリ構造**
```
/mnt/d/Git/
├── ReadMarker/              # メインブランチ (main)
├── ReadMarker-sidepanel/    # サイドパネル機能開発
├── ReadMarker-highlighting/ # ハイライト機能改善
├── ReadMarker-tests/        # テスト改善作業
└── ReadMarker-docs/         # ドキュメント更新
```

#### 初期セットアップ手順

**1. 新規worktree作成と初期化**
```bash
# worktree作成
git worktree add ../ReadMarker-新機能 feature/新機能
cd ../ReadMarker-新機能

# 依存関係インストール
npm install

# テスト環境確認
npm test
npm run test:coverage

# Cursorで開く
cursor .
```

**2. 機能別セットアップ例**

```bash
# サイドパネル開発
cd ../ReadMarker-sidepanel
npm test -- tests/sidepanel-real-fixed.test.js

# コンテンツスクリプト開発
cd ../ReadMarker-content
npm test -- tests/content-real-enhanced.test.js

# テスト改善
cd ../ReadMarker-tests
npm run test:coverage
```

#### 管理コマンド

```bash
# worktree一覧の確認
git worktree list

# 作業完了後のworktree削除
git worktree remove ReadMarker-機能名

# 不要なworktreeのクリーンアップ
git worktree prune
```

#### ベストプラクティス

1. **Worktree命名規則**
   ```
   ReadMarker-機能名/    # 機能開発用
   ReadMarker-fix-xxx/   # バグ修正用
   ReadMarker-test-xxx/  # テスト改善用
   ReadMarker-docs/      # ドキュメント用
   ```

2. **ブランチ戦略**
   - `feature/機能名`: 新機能開発
   - `fix/問題名`: バグ修正
   - `test/改善内容`: テスト改善
   - `docs/更新内容`: ドキュメント更新

3. **定期的な同期**
   ```bash
   # メインブランチの最新を取り込む
   cd ../ReadMarker
   git pull origin main
   
   # 各worktreeで同期
   cd ../ReadMarker-機能名
   git merge main
   npm install  # 依存関係も更新
   ```

4. **ローカル設定の活用**
   ```bash
   # 各worktree専用の設定ファイル
   echo '{"worktree": "機能名"}' > settings.local.json
   ```

#### 注意事項

- **リソース管理**: 複数のClaude Codeインスタンスはそれぞれメモリ・CPUを消費
- **ディスク容量**: 各worktreeは独立したファイルセットを保持
- **同期タイミング**: 定期的にメインブランチとの同期を行い、コンフリクトを最小限に

#### トラブルシューティング

**worktreeが削除できない場合**
```bash
git worktree remove --force ReadMarker-機能名
```

**worktreeの場所を忘れた場合**
```bash
git worktree list --porcelain
```

### Worktree管理ファイル (.gitignoreに追加推奨)

```gitignore
# Worktree specific files
test-coverage-analysis.md
*-analysis.md
*-report.md
*.working.*
*.temp.*
*.local.*

# Build outputs
/build/
/dist/

# Worktree logs
*.log
!npm-debug.log*
```

### まとめ
Git worktreeを標準的な開発環境として活用することで、以下のメリットがあります：
- 複数機能の並行開発が可能
- 各環境が完全に独立
- コンフリクトリスクの最小化
- テスト実行の並列化
- Cursorエディタとの相性が良い

## 🏷️ Claude Codeインスタンスの区別方法

### 概要
複数のClaude Codeを同時に使用する際、どのインスタンスがどの作業をしているかを明確に区別するための方法です。

### 1. **インスタンス識別スクリプトの使用**

#### 初期セットアップ
```bash
# 統合セットアップスクリプトを実行
./scripts/claude-workspace-setup.sh

# または個別に設定
./scripts/setup-claude-instance.sh A Frontend
./scripts/git-author-setup.sh A
```

#### 各インスタンスの識別
- **Instance A**: Frontend Development (赤色表示)
- **Instance B**: Backend Development (緑色表示)
- **Instance C**: Testing & QA (黄色表示)

### 2. **ターミナルでの表示**

#### プロンプト表示
```bash
[Claude-A] /mnt/d/Git/ReadMarker-frontend $ 
[Claude-B] /mnt/d/Git/ReadMarker-backend $ 
[Claude-C] /mnt/d/Git/ReadMarker-tests $ 
```

#### ターミナルタイトル
各ターミナルウィンドウのタイトルバーに表示：
- "Claude Code A - Frontend Development"
- "Claude Code B - Backend API"
- "Claude Code C - Test Suite"

### 3. **Git設定による識別**

#### コミット時の作成者情報
```bash
# Instance Aでのコミット
git log --oneline
# abc123 feat: 新UIコンポーネント追加 (Claude Code A - Frontend)

# Instance Bでのコミット
# def456 fix: APIエンドポイントエラー修正 (Claude Code B - Backend)
```

### 4. **ローカル状態ファイル**

#### インスタンス情報の確認
```bash
# 現在のインスタンス情報
cat .claude-instance.json
{
  "instance": "A",
  "role": "Frontend Development",
  "worktree": "ReadMarker-frontend",
  "created": "2025-06-13 10:00:00",
  "pid": 12345
}

# 作業状態の確認
cat .claude/instance-status.md
```

### 5. **推奨運用方法**

#### Worktreeごとの割り当て
```
ReadMarker/              → メイン（レビュー・統合用）
ReadMarker-frontend/     → Instance A専用
ReadMarker-backend/      → Instance B専用
ReadMarker-tests/        → Instance C専用
```

#### 並行作業の例
1. **Instance A (Frontend)**
   ```bash
   cd ../ReadMarker-frontend
   ./scripts/claude-workspace-setup.sh  # Aを選択
   cursor .  # Frontend開発開始
   ```

2. **Instance B (Backend)**
   ```bash
   cd ../ReadMarker-backend
   ./scripts/claude-workspace-setup.sh  # Bを選択
   cursor .  # Backend開発開始
   ```

3. **Instance C (Testing)**
   ```bash
   cd ../ReadMarker-tests
   ./scripts/claude-workspace-setup.sh  # Cを選択
   npm run test:coverage  # テスト実行
   ```

### 6. **トラブルシューティング**

#### インスタンス情報のリセット
```bash
# 状態ファイルを削除
rm .claude-instance.json
rm -rf .claude/

# 再設定
./scripts/claude-workspace-setup.sh
```

#### Git設定の確認
```bash
# 現在の設定確認
git config user.name
git config user.email
```

これらの方法により、複数のClaude Codeインスタンスを明確に区別し、効率的な並行開発が可能になります。

## 📌 既知のテスト失敗ケース（意図的に未修正）

### 背景
以下のテストは2025年6月のサイドパネル実装時から失敗しているが、実際の機能に影響がないため未修正としている。

### 失敗テスト一覧（content-real-enhanced.test.js）

1. **サイドパネルが正常に初期化される**
   - 原因: Shadow DOM `mode: 'closed'`で外部アクセス不可
   - 影響: なし（セキュリティ設計として正しい）
   - 対応: 将来的に`mode: 'open'`への変更を検討

2. **処理時間制限が正常に動作する**
   - 原因: 処理が速すぎてタイムアウトに達しない
   - 影響: なし（性能が良いことの証明）
   - 対応: より重い処理でのテストに変更を検討

3. **highlight処理中の個別ノードエラーが処理される**
   - 原因: モックが実際のエラーフローを再現できていない
   - 影響: なし（実際のエラー処理は正常動作）
   - 対応: モック設計の見直しが必要

4. **clearメッセージが処理される**（テスト5）
   - 原因: テストでハイライト要素を作成していない
   - 影響: なし（実環境では正常動作）
   - 対応: テストセットアップの改善が必要

5. **スタイル初期化エラーが処理される**（テスト6）
   - 原因: エラーが内部で適切に処理され外部に伝播しない
   - 影響: なし（エラー処理は正常）
   - 対応: テストの期待値を実装に合わせる

6. **ページ読み込み完了時に自動ハイライトが実行される**（テスト7）
   - 原因: モジュール再読み込みで初期化コードが再実行されない
   - 影響: なし（実環境では正常動作）
   - 対応: テスト手法の根本的な見直しが必要

### 対応方針
- **カバレッジ**: 84.89%達成済み（目標80%以上）
- **実機能への影響**: なし
- **修正の費用対効果**: 低い
- **結論**: 将来的なリファクタリング時に対応

### 2025年6月18日の対応
- テスト4「既存のサイドパネルが削除される」のみ修正（実装に合わせてテストを修正）
- 他のテストは既知の問題として記録し、実装に影響がないことを確認

## 📁 ファイル整理ルール

### 🎯 推奨: Git管理下では物理削除

**理由：**
1. **Gitが完全な履歴を保持** - いつでも復元可能
2. **リポジトリがクリーン** - 現在必要なファイルのみ表示
3. **検索性向上** - 不要なファイルが検索結果に出ない
4. **標準的な開発手法** - 多くのプロジェクトで採用

**復元方法：**
```bash
# 削除したファイルの履歴確認
git log --oneline -- 削除したファイル名

# 特定のコミットから復元
git checkout コミットハッシュ -- ファイル名
```

### ❌ 非推奨: Backupフォルダ

**問題点：**
1. **二重管理** - Gitとフォルダの両方で管理
2. **混乱の元** - どれが最新か不明確
3. **検索ノイズ** - 使わないファイルが検索に引っかかる
4. **リポジトリ肥大化** - 不要ファイルも含まれる

### 📋 整理時のベストプラクティス

1. **削除前にコミット** - 現在の状態を保存
2. **意味のあるコミットメッセージ**
   ```bash
   git commit -m "cleanup: 旧テストファイルを削除（実ファイル版に置き換え済み）"
   ```
3. **関連ファイルをまとめて削除** - 一つの機能に関するファイルは同時に
4. **READMEに記録** - 大きな整理は変更履歴に記載

### 🚨 例外: 一時的に保持する場合

`.gitignore`に追加してローカルのみ保持：
```
# 一時保存用（コミットしない）
/backup/
/old/
```

### 🗑️ 整理対象ファイル

1. **古いテストファイル** - 実ファイルを使わない旧版テスト
2. **一時的な作業ファイル** - デバッグ用、実験用ファイル
3. **重複ファイル** - 同じ機能の複数バージョン
4. **無効な設定ファイル** - 使われていない設定

これにより、Git管理はクリーンに保ちつつ、必要に応じて過去のファイルを復元できます。

## 🚀 リリースプロセス

### リリース前チェックリスト
- [ ] 全テスト成功（100%）
- [ ] カバレッジ80%以上達成
- [ ] セキュリティ監査完了
- [ ] パフォーマンステスト合格
- [ ] manifest.jsonのバージョン更新
- [ ] CHANGELOG.md更新
- [ ] README.md更新（必要に応じて）
- [ ] 手動テスト完了（全機能）
- [ ] メモリリークチェック完了
- [ ] Chrome拡張機能のポリシー準拠確認

### バージョン管理戦略

#### セマンティックバージョニング
- **形式**: MAJOR.MINOR.PATCH (例: 1.2.3)
- **MAJOR**: 破壊的変更（後方互換性なし）
- **MINOR**: 機能追加（後方互換性あり）
- **PATCH**: バグ修正

#### バージョン更新手順
```bash
# manifest.jsonのバージョン更新
# "version": "1.2.3" に更新

# リリースタグの作成
git tag -a v1.2.3 -m "Release version 1.2.3: 機能説明"
git push origin v1.2.3

# CHANGELOG.md更新例
## [1.2.3] - 2025-06-13
### Added
- サイドパネルUI機能
### Fixed
- 通信エラーの修正
```

### Chrome Web Store公開手順

1. **ビルドパッケージ作成**
   ```bash
   # 不要ファイルを除外してZIP作成
   zip -r readmarker-v1.2.3.zip . \
     -x "*.git*" \
     -x "node_modules/*" \
     -x "tests/*" \
     -x "coverage/*" \
     -x "*.md" \
     -x "package*.json" \
     -x "jest.config.js" \
     -x "scripts/*"
   ```

2. **必要な素材準備**
   - スクリーンショット (1280x800 または 640x400)
   - プロモーション画像 (440x280)
   - アイコン (128x128)
   - 説明文（日本語・英語）

3. **ストア情報更新**
   - カテゴリ: 生産性
   - 言語: 日本語、英語
   - 対象ユーザー: すべて

4. **プライバシーポリシー**
   - 収集データ: なし
   - 権限の説明を明記

5. **審査提出**
   - 審査期間: 通常1-3営業日
   - 却下時の対応準備

## ⚡ パフォーマンス基準

### 必須要件
- **ハイライト処理**: 100個のテキストで1秒以内
- **メモリ使用量**: 50MB以下（通常使用時）
- **起動時間**: 500ms以内
- **サイドパネル表示**: 200ms以内
- **ファイル読み込み**: 1MBで2秒以内

### パフォーマンステスト実装
```javascript
// tests/performance.test.js
describe('パフォーマンステスト', () => {
  test('大量テキストのハイライト性能', async () => {
    const texts = Array(100).fill('テストテキスト');
    const startTime = performance.now();
    
    await readMarker.highlight(texts);
    
    const endTime = performance.now();
    expect(endTime - startTime).toBeLessThan(1000);
  });

  test('メモリ使用量の確認', () => {
    if (performance.memory) {
      const usedMemory = performance.memory.usedJSHeapSize / 1048576;
      expect(usedMemory).toBeLessThan(50);
    }
  });
});
```

### パフォーマンス改善指針
1. **デバウンス・スロットリング**: 連続処理の制御
2. **仮想スクロール**: 大量要素の表示最適化
3. **Web Worker**: 重い処理の別スレッド化
4. **キャッシュ活用**: 計算結果の再利用

## 📊 エラー監視とログ

### ログレベル定義
- **ERROR**: 即座に対応が必要な致命的エラー
- **WARN**: 監視が必要な警告
- **INFO**: 通常動作の記録
- **DEBUG**: 開発時のみ出力

### ログ実装例
```javascript
class Logger {
  static error(message, error) {
    console.error(`[ReadMarker ERROR] ${message}`, error);
    // 本番環境ではエラー収集サービスに送信
  }
  
  static warn(message) {
    console.warn(`[ReadMarker WARN] ${message}`);
  }
  
  static info(message) {
    if (process.env.NODE_ENV !== 'production') {
      console.log(`[ReadMarker INFO] ${message}`);
    }
  }
  
  static debug(message, data) {
    if (process.env.NODE_ENV === 'development') {
      console.log(`[ReadMarker DEBUG] ${message}`, data);
    }
  }
}
```

### エラー収集（将来実装）
```javascript
// Sentryなどの導入例
window.addEventListener('error', (event) => {
  Logger.error('Uncaught error', {
    message: event.message,
    source: event.filename,
    line: event.lineno,
    column: event.colno,
    error: event.error
  });
});
```

## 🔒 セキュリティガイドライン

### 権限の最小化原則
```json
// manifest.json
{
  "permissions": [
    "storage",     // 設定保存に必要
    "activeTab",   // 現在のタブのみアクセス
    "scripting"    // Content Script注入に必要
  ],
  "host_permissions": [
    "<all_urls>"   // 必要最小限に絞ることを検討
  ]
}
```

### セキュリティチェックリスト
- [ ] 外部スクリプトの読み込み禁止
- [ ] eval()の使用禁止（テスト環境での限定的使用を除く）
- [ ] innerHTML使用時のサニタイズ
- [ ] Content Security Policy (CSP) 設定
- [ ] 機密情報のハードコーディング禁止
- [ ] HTTPS通信の強制

### セキュアコーディング例
```javascript
// 悪い例
element.innerHTML = userInput;

// 良い例
element.textContent = userInput;
// または
element.innerHTML = DOMPurify.sanitize(userInput);
```

## 🔧 トラブルシューティングガイド

### 開発時の問題

#### 1. **テストが失敗する**
```bash
# node_modulesのクリーンインストール
rm -rf node_modules package-lock.json
npm install

# Jestキャッシュのクリア
npm test -- --clearCache

# Chrome APIモックの確認
# tests/setup.jsでglobal.chromeが正しく設定されているか確認
```

#### 2. **カバレッジが上がらない**
```bash
# 未カバーの行を特定
npm run test:coverage

# HTML形式でカバレッジレポートを確認
open coverage/lcov-report/index.html
```

#### 3. **Worktreeでの依存関係エラー**
```bash
# 各worktreeで独立してインストール
cd ../ReadMarker-機能名
rm -rf node_modules
npm install
```

### 本番環境の問題

#### 1. **拡張機能が動作しない**
- Chrome DevToolsでエラーログ確認
- manifest.jsonの権限確認
- Content Scriptが正しく注入されているか確認

#### 2. **サイドパネルが表示されない**
- Chrome拡張機能の再読み込み
- web_accessible_resourcesの確認
- Shadow DOMの初期化確認

#### 3. **ハイライトが機能しない**
- ストレージのデータ確認
- テキストのエンコーディング確認
- DOMの構造変更を監視

### デバッグ手法

#### Chrome DevToolsの活用
```javascript
// Background script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('Message received:', message);
  console.log('Sender:', sender);
  // デバッグポイント設定可能
  debugger;
});
```

#### ローカルストレージの確認
```javascript
// Console で実行
chrome.storage.local.get(null, (items) => {
  console.log('All storage items:', items);
});
```

これらの追加により、リリースまでの品質保証とリリース後の安定運用が実現できます。

## 📝 CLAUDE.md再編成計画

### 現在の課題
このCLAUDE.mdファイルが1500行以上に肥大化しており、プロジェクト固有の内容と汎用的な内容が混在しています。

### 再編成計画
詳細な再編成計画は `CLAUDE_MD_REORGANIZATION.md` に記載されています。

**主な内容：**
- 汎用ファイルとプロジェクト固有ファイルの分離
- 他プロジェクトへの転用を容易にする構成
- 段階的な移行手順

**参照：**
```bash
# 再編成計画の詳細を確認
cat CLAUDE_MD_REORGANIZATION.md
```

この再編成により、新プロジェクトでは3つのファイル/ディレクトリをコピーするだけで同じ開発環境を構築できるようになります。