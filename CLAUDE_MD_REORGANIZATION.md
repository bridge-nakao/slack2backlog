# CLAUDE.md 再編成計画

## 📋 現状の問題点
- CLAUDE.mdが1500行以上に肥大化
- プロジェクト固有の内容と汎用的な内容が混在
- 他プロジェクトへの転用が困難
- 情報の検索性が低下

## 🎯 再編成の目的
1. **再利用性の向上** - 汎用的な内容を他プロジェクトで使い回し
2. **保守性の改善** - ファイルを分割して管理しやすく
3. **検索性の向上** - 目的別にファイルを整理
4. **スケーラビリティ** - 今後の追加情報にも対応

## 📚 新しいファイル構成

### 🔄 汎用ファイル（他プロジェクトで使い回し可能）

#### 1. **CLAUDE.md** (汎用テンプレート)
Claude Code全般で使える内容のみを記載：
- Claude Code起動時の確認事項（テンプレート）
- 日付誤記防止ガイドライン
- Git Worktree開発環境ガイド
- Claude Codeインスタンスの区別方法
- テストプログラム作成ガイドライン
- eval使用の検討履歴（フォーマット）
- ファイル整理ルール
- セキュリティガイドライン（汎用部分）

#### 2. **DEVELOPMENT_TEMPLATE.md**
開発プロセスの標準テンプレート：
- 標準開発フロー（23ステップ）
- GitHub Projects連携方針
- コードレビューガイドライン
- リリースプロセステンプレート
- バージョン管理戦略

#### 3. **scripts/ディレクトリ**
全ての開発支援スクリプト：
- claude-workspace-setup.sh
- setup-github-project.sh
- github-project-helpers.sh
- pr-review-helpers.sh

### 📌 プロジェクト固有ファイル（ReadMarker専用）

#### 1. **PROJECT_HISTORY.md**
ReadMarkerの開発履歴：
- 解決済み問題の詳細
- 各フェーズでの学び
- 技術的な決定事項
- 2025年1月の各セッション記録

#### 2. **KNOWN_ISSUES.md**
ReadMarker固有の問題：
- 既知のテスト失敗ケース（6件）
- 対応方針と影響評価
- 将来の改善計画

#### 3. **README.md** (既存を拡張)
- 既存の仕様書内容
- テスト関連情報
- パフォーマンス基準
- トラブルシューティング（ReadMarker固有）

## 📦 新プロジェクトでの使用方法

```bash
# 1. 新プロジェクトのディレクトリで実行
NEW_PROJECT_DIR="/path/to/new-project"
TEMPLATE_DIR="/path/to/ReadMarker"

# 2. 汎用ファイルをコピー
cp $TEMPLATE_DIR/CLAUDE.md $NEW_PROJECT_DIR/
cp $TEMPLATE_DIR/DEVELOPMENT_TEMPLATE.md $NEW_PROJECT_DIR/DEVELOPMENT.md
cp -r $TEMPLATE_DIR/scripts $NEW_PROJECT_DIR/

# 3. プロジェクト固有セクションを追加
cat >> $NEW_PROJECT_DIR/CLAUDE.md << 'EOF'

## プロジェクト概要
[新プロジェクトの説明をここに記載]

## 重要なファイル
[プロジェクト固有のファイル一覧]
EOF

# 4. 初期設定
cd $NEW_PROJECT_DIR
./scripts/claude-workspace-setup.sh
```

## 🔀 移行手順

### Phase 1: ファイル作成（現在のCLAUDE.mdは保持）
1. PROJECT_HISTORY.mdを作成し、ReadMarker固有の履歴を移動
2. KNOWN_ISSUES.mdを作成し、既知の問題を移動
3. DEVELOPMENT_TEMPLATE.mdを作成し、開発フローを移動

### Phase 2: CLAUDE.md縮小
1. プロジェクト固有の内容を削除
2. 汎用的な内容のみ残す
3. テンプレート化のための調整

### Phase 3: 検証
1. 各ファイルの内容確認
2. リンクや参照の修正
3. scriptsの動作確認

### Phase 4: ドキュメント化
1. 移行完了後の使用方法を文書化
2. 各ファイルの役割を明確化

## 📊 期待される効果

### Before（現状）
```
CLAUDE.md (1500+ lines)
├── 汎用的な内容 (40%)
├── ReadMarker固有 (50%)
└── 一時的な記録 (10%)
```

### After（再編成後）
```
CLAUDE.md (300 lines) - 汎用テンプレート
DEVELOPMENT_TEMPLATE.md (400 lines) - 開発プロセス
PROJECT_HISTORY.md (500 lines) - ReadMarker履歴
KNOWN_ISSUES.md (200 lines) - 既知の問題
README.md (拡張) - 統合ドキュメント
```

## ✅ チェックリスト

- [ ] PROJECT_HISTORY.md作成
- [ ] KNOWN_ISSUES.md作成
- [ ] DEVELOPMENT_TEMPLATE.md作成
- [ ] CLAUDE.md縮小版作成
- [ ] 移行スクリプト作成
- [ ] ドキュメント更新
- [ ] 動作確認

## 🚀 実行タイミング

この再編成は、現在の開発が一段落した後（テスト修正完了後）に実施することを推奨。