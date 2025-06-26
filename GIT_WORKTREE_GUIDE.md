# Git Worktree チーム開発運用ガイド

## 📋 概要

Git worktreeを使用したチーム開発の運用方法を説明します。複数の開発者が同じリポジトリで並行作業する際の手順とベストプラクティスをまとめています。

## 🎯 Git Worktreeのメリット

### 開発者にとってのメリット
- **完全に独立した作業環境** - 他の開発者の作業に影響されない
- **高速なコンテキスト切り替え** - `git checkout`不要で即座に切り替え
- **並行ビルド・テスト** - 複数の環境で同時にテスト実行可能
- **ファイル競合の回避** - 物理的に別フォルダで作業

### プロジェクトにとってのメリット
- **開発効率の向上** - 複数機能の並行開発
- **CI/CD時間の短縮** - ローカルで並行テスト
- **レビュー効率化** - レビュー用環境を即座に準備

## 🚀 基本的な使い方

### 1. 新規開発者の参加手順

```bash
# リポジトリをクローン
git clone https://github.com/[organization]/[repository].git
cd [repository]

# 作業用worktreeを作成
git worktree add ../[repository]-[feature-name] feature/[feature-name]
cd ../[repository]-[feature-name]

# 環境セットアップ
npm install  # または yarn install, pip install等

# Claude Codeインスタンス設定（オプション）
./scripts/claude-workspace-setup.sh
```

### 2. 既存開発者が新機能を開発する場合

```bash
# mainリポジトリで最新を取得
cd /path/to/main-repository
git fetch origin

# 新しいworktreeを作成
git worktree add ../[repository]-[new-feature] feature/[new-feature]
cd ../[repository]-[new-feature]

# 環境セットアップ
npm install
```

## 📁 推奨ディレクトリ構造

```
/mnt/d/Git/  # または任意の開発ディレクトリ
├── ProjectName/              # メインリポジトリ（main/master）
├── ProjectName-frontend/     # フロントエンド開発用
├── ProjectName-backend/      # バックエンド開発用
├── ProjectName-feature-x/    # 機能X開発用
├── ProjectName-bugfix-y/     # バグ修正Y用
└── ProjectName-review/       # コードレビュー用
```

## 👥 チーム開発シナリオ

### シナリオ1: 3人での並行開発

**開発者A（フロントエンド担当）**
```bash
git worktree add ../ProjectName-frontend feature/new-ui
cd ../ProjectName-frontend
./scripts/claude-workspace-setup.sh  # A選択
# UIコンポーネント開発
```

**開発者B（バックエンド担当）**
```bash
git worktree add ../ProjectName-backend feature/api-v2
cd ../ProjectName-backend
./scripts/claude-workspace-setup.sh  # B選択
# API開発
```

**開発者C（テスト担当）**
```bash
git worktree add ../ProjectName-tests test/integration
cd ../ProjectName-tests
./scripts/claude-workspace-setup.sh  # C選択
# テスト作成
```

### シナリオ2: レビューワークフロー

```bash
# レビュアーがPRをローカルで確認
git worktree add ../ProjectName-review-pr-123 origin/feature/some-feature
cd ../ProjectName-review-pr-123
npm install
npm test
# コードレビュー実施
```

## 🔄 日常的な運用

### 定期的な同期

```bash
# 各worktreeで定期的に実行
git fetch origin
git merge origin/main  # または git rebase origin/main

# コンフリクトがある場合
git status
# コンフリクト解決
git add .
git merge --continue
```

### worktreeの管理

```bash
# worktree一覧表示
git worktree list

# 不要になったworktreeの削除
git worktree remove ../ProjectName-old-feature

# 削除されたブランチのworktreeをクリーンアップ
git worktree prune
```

## ⚠️ 注意事項

### 1. **同じブランチを複数のworktreeで使用しない**
```bash
# ❌ 悪い例
git worktree add ../project-1 feature/same-branch
git worktree add ../project-2 feature/same-branch  # エラー
```

### 2. **worktree内でブランチを切り替えない**
```bash
# ❌ 悪い例（worktree内で）
git checkout main  # 混乱の元

# ✅ 良い例
cd ../ProjectName  # メインリポジトリに戻る
git checkout main
```

### 3. **定期的なクリーンアップ**
```bash
# 月1回程度実行
git worktree prune
git branch -d feature/merged-branch
```

## 📋 トラブルシューティング

### Q: worktreeが作成できない
```bash
# ブランチが既に存在する場合
git worktree add ../project-feature -b feature/new-feature

# 強制的に作成
git worktree add -f ../project-feature feature/existing
```

### Q: worktreeを削除してもフォルダが残る
```bash
# 強制削除
git worktree remove --force ../project-feature
# または手動削除後
rm -rf ../project-feature
git worktree prune
```

### Q: どのworktreeがどのブランチか分からない
```bash
# 詳細表示
git worktree list --porcelain
```

## 🎯 ベストプラクティス

1. **命名規則を統一**
   - `ProjectName-機能名` または `ProjectName-issue番号`
   
2. **作業完了後は速やかに削除**
   - マージ後のworktreeは削除してディスクスペースを節約

3. **README.mdに現在のworktreeを記載**
   ```markdown
   ## Active Development Worktrees
   - frontend-redesign: @developer-a (feature/ui-redesign)
   - backend-api-v2: @developer-b (feature/api-v2)
   ```

4. **CI/CDとの連携**
   - worktreeごとに`.env.local`を設定
   - ビルド成果物は`.gitignore`に追加

## 📝 チーム間の情報共有

### Slackやチャットでの共有例
```
@team 新しいworktreeを作成しました
- 場所: ../ProjectName-payment
- ブランチ: feature/payment-integration
- 担当: @developer-name
- 目的: 決済機能の統合
```

### プロジェクト管理ツールとの連携
- GitHub Projects/Jiraのチケットにworktree名を記載
- PRにworktree情報を含める

## 🔧 高度な使い方

### 1. 自動セットアップスクリプト
```bash
#!/bin/bash
# create-worktree.sh
FEATURE_NAME=$1
git worktree add ../${PWD##*/}-$FEATURE_NAME feature/$FEATURE_NAME
cd ../${PWD##*/}-$FEATURE_NAME
npm install
./scripts/claude-workspace-setup.sh
```

### 2. worktree状態の可視化
```bash
# すべてのworktreeの状態を表示
for worktree in $(git worktree list --porcelain | grep "worktree" | cut -d' ' -f2); do
    echo "=== $worktree ==="
    cd $worktree
    git status --short
    cd - > /dev/null
done
```

---

Git worktreeを活用することで、チーム全体の開発効率が大幅に向上します。各開発者が独立した環境で作業できるため、相互の干渉を最小限に抑えながら、高速な開発サイクルを実現できます。