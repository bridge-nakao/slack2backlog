# CI/CDセットアップガイド

## 概要

このドキュメントでは、slack2backlogプロジェクトのCI/CDパイプラインのセットアップ方法を説明します。

## アーキテクチャ

### ワークフロー構成

1. **CI Pipeline** (`ci.yml`)
   - プルリクエストとmain/developブランチへのプッシュで実行
   - テスト、ビルド、セキュリティスキャンを実行

2. **開発環境デプロイ** (`deploy-dev.yml`)
   - developブランチへのプッシュで自動実行
   - 開発環境へのデプロイ

3. **ステージング環境デプロイ** (`deploy-staging.yml`)
   - stagingブランチへのプッシュで自動実行
   - ステージング環境へのデプロイ

4. **本番環境デプロイ** (`deploy-prod.yml`)
   - リリース作成時または手動実行
   - 承認プロセス付き本番デプロイ

## セットアップ手順

### 1. AWS IAMロールの作成

#### GitHubActions用デプロイロール

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:bridge-nakao/slack2backlog:*"
        }
      }
    }
  ]
}
```

#### 必要な権限ポリシー

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "lambda:*",
        "apigateway:*",
        "sqs:*",
        "dynamodb:*",
        "secretsmanager:GetSecretValue",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:PassRole",
        "iam:TagRole",
        "iam:UntagRole",
        "logs:*",
        "s3:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### 2. S3バケットの作成

SAMアーティファクト用のS3バケットを作成：

```bash
aws s3api create-bucket \
  --bucket slack2backlog-sam-artifacts-YOUR_ACCOUNT_ID \
  --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1
```

### 3. GitHub Secretsの設定

以下のシークレットをGitHubリポジトリに設定：

#### 共通設定

- `AWS_DEPLOY_ROLE_ARN`: 開発/ステージング用IAMロール
- `AWS_PROD_DEPLOY_ROLE_ARN`: 本番用IAMロール
- `SAM_ARTIFACTS_BUCKET`: SAMアーティファクト用S3バケット名
- `SLACK_WEBHOOK`: Slack通知用Webhook URL

#### 開発/ステージング環境

- `SLACK_SIGNING_SECRET`: Slack署名シークレット
- `SLACK_BOT_TOKEN`: Slackボットトークン
- `BACKLOG_API_KEY`: Backlog APIキー
- `BACKLOG_SPACE`: Backlogスペース名
- `BACKLOG_PROJECT_ID`: BacklogプロジェクトID
- `BACKLOG_ISSUE_TYPE_ID`: Backlog課題タイプID

#### 本番環境

- `PROD_SLACK_SIGNING_SECRET`: 本番Slack署名シークレット
- `PROD_SLACK_BOT_TOKEN`: 本番Slackボットトークン
- `PROD_BACKLOG_API_KEY`: 本番Backlog APIキー
- `PROD_BACKLOG_SPACE`: 本番Backlogスペース名
- `PROD_BACKLOG_PROJECT_ID`: 本番BacklogプロジェクトID
- `PROD_BACKLOG_ISSUE_TYPE_ID`: 本番Backlog課題タイプID

### 4. Environments設定

GitHubリポジトリで以下の環境を作成：

1. **development**
   - 保護なし
   - 自動デプロイ

2. **staging**
   - 保護なし
   - 自動デプロイ

3. **production**
   - 保護あり
   - レビュー承認必須
   - 特定のユーザー/チームのみデプロイ可能

## 使用方法

### 開発フロー

1. **機能開発**
   ```bash
   git checkout -b feature/new-feature
   # 開発作業
   git push origin feature/new-feature
   ```

2. **プルリクエスト作成**
   - CIパイプラインが自動実行
   - テストとビルドが成功することを確認

3. **マージ**
   - developブランチにマージ
   - 開発環境へ自動デプロイ

### リリースフロー

1. **ステージングデプロイ**
   ```bash
   git checkout staging
   git merge develop
   git push origin staging
   ```

2. **本番リリース**
   ```bash
   # GitHubでリリースを作成
   # または手動でワークフローを実行
   ```

## モニタリング

### デプロイ状況の確認

- GitHub Actions タブで各ワークフローの実行状況を確認
- Slack通知でデプロイ結果を受信

### ログの確認

```bash
# CloudWatch Logsでログを確認
aws logs tail /aws/lambda/slack2backlog-prod-event-ingest --follow
```

## トラブルシューティング

### デプロイが失敗する場合

1. **AWS認証エラー**
   - IAMロールの信頼関係を確認
   - GitHub Secretsが正しく設定されているか確認

2. **SAMビルドエラー**
   - Node.jsバージョンを確認
   - 依存関係が正しくインストールされているか確認

3. **CloudFormationエラー**
   - スタックの状態を確認
   - 必要なリソースの権限を確認

### ロールバック手順

1. **自動ロールバック**
   - 本番デプロイが失敗した場合、自動的にロールバック

2. **手動ロールバック**
   ```bash
   # 前のバージョンにロールバック
   aws cloudformation update-stack \
     --stack-name slack2backlog-prod \
     --use-previous-template
   ```

## ベストプラクティス

1. **ブランチ戦略**
   - main: 安定版
   - develop: 開発版
   - staging: ステージング版
   - feature/*: 機能開発

2. **テストカバレッジ**
   - 本番デプロイ前に80%以上のカバレッジを維持

3. **セキュリティ**
   - シークレットは必ずGitHub Secretsを使用
   - 最小権限の原則に従ったIAMロール

4. **監視**
   - デプロイ通知をSlackで受信
   - CloudWatch Alarmsでエラーを監視