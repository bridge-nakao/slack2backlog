# Secrets Manager セキュリティガイド

## 概要

このドキュメントでは、slack2backlogプロジェクトにおけるシークレット管理のセキュリティベストプラクティスを説明します。

## シークレット管理の原則

### 1. 最小公開の原則
- シークレットは必要最小限のサービス・人員のみアクセス可能に
- 環境ごとに異なるシークレット使用
- 本番環境のシークレットは限定的なアクセス

### 2. 定期的なローテーション
```yaml
SecretRotationSchedule:
  Type: AWS::SecretsManager::RotationSchedule
  Properties:
    SecretId: !Ref ProductionSecret
    RotationRules:
      AutomaticallyAfterDays: 90
```

### 3. 監査証跡
- すべてのシークレットアクセスをCloudTrailで記録
- 異常なアクセスパターンの検知
- 定期的なアクセスレビュー

## AWS Secrets Manager設定

### KMS暗号化
```yaml
Secret:
  Type: AWS::SecretsManager::Secret
  Properties:
    KmsKeyId: !Ref CustomKMSKey  # カスタマーマネージドキー推奨
    SecretString: !Sub |
      {
        "api_key": "${ApiKey}"
      }
```

### リソースポリシー
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "RestrictAccess",
    "Effect": "Allow",
    "Principal": {
      "AWS": [
        "arn:aws:iam::123456789012:role/LambdaRole"
      ]
    },
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "*",
    "Condition": {
      "StringEquals": {
        "secretsmanager:VersionStage": "AWSCURRENT"
      }
    }
  }]
}
```

### タグによる管理
```yaml
Tags:
  - Key: Classification
    Value: Confidential
  - Key: Owner
    Value: DevOps
  - Key: Environment
    Value: Production
```

## ローカル開発のセキュリティ

### .env ファイルの保護
```bash
# 権限設定（Unixシステム）
chmod 600 .env

# Windowsの場合はファイルのプロパティから
# 「セキュリティ」タブで適切な権限設定
```

### Git設定
```gitignore
# 必ず.gitignoreに含める
.env
.env.*
!.env.example
secrets/
*.pem
*.key
```

### 環境変数の分離
```javascript
// 環境ごとの設定
const config = {
  development: {
    secretsEndpoint: 'http://localhost:4566'
  },
  production: {
    secretsEndpoint: null  // デフォルトのAWSエンドポイント
  }
};
```

## シークレットアクセスパターン

### 1. キャッシュの実装
```javascript
const secretsCache = new Map();
const CACHE_TTL = 5 * 60 * 1000; // 5分

async function getCachedSecret(secretId) {
  const cached = secretsCache.get(secretId);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    return cached.value;
  }
  
  const secret = await getSecretFromAWS(secretId);
  secretsCache.set(secretId, {
    value: secret,
    timestamp: Date.now()
  });
  
  return secret;
}
```

### 2. エラーハンドリング
```javascript
async function getSecretSafely(secretId, defaultValue = null) {
  try {
    return await getSecret(secretId);
  } catch (error) {
    console.error(`Failed to retrieve secret: ${secretId}`);
    
    // 本番環境では絶対にデフォルト値を使わない
    if (process.env.NODE_ENV === 'production') {
      throw error;
    }
    
    return defaultValue;
  }
}
```

### 3. 最小権限でのアクセス
```javascript
// 必要な値のみ取得
async function getSlackToken() {
  const secrets = await getSecret('slack-secrets');
  return secrets.bot_token;  // 必要な値のみ返す
}
```

## 監視とアラート

### CloudWatchアラーム
```yaml
UnauthorizedAccessAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: secrets-unauthorized-access
    MetricName: UserErrorCount
    Namespace: AWS/SecretsManager
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 1
    Threshold: 1
    ComparisonOperator: GreaterThanOrEqualToThreshold
    AlarmActions:
      - !Ref SNSTopic
```

### CloudTrailイベント
```json
{
  "eventVersion": "1.05",
  "userIdentity": {
    "type": "AssumedRole",
    "principalId": "AIDACKCEVSQ6C2EXAMPLE",
    "arn": "arn:aws:sts::123456789012:assumed-role/LambdaRole/function"
  },
  "eventTime": "2025-06-26T10:00:00Z",
  "eventSource": "secretsmanager.amazonaws.com",
  "eventName": "GetSecretValue",
  "sourceIPAddress": "10.0.0.1",
  "resources": [{
    "ARN": "arn:aws:secretsmanager:region:123456789012:secret:name"
  }]
}
```

## インシデント対応

### 1. シークレット漏洩時の対応

#### 即座の対応（30分以内）
1. **該当シークレットの無効化**
   ```bash
   # Slackトークンの無効化
   curl -X POST https://slack.com/api/auth.revoke \
     -H "Authorization: Bearer xoxb-compromised-token"
   ```

2. **新しいシークレットの生成と更新**
   ```bash
   aws secretsmanager update-secret \
     --secret-id production-secret \
     --secret-string '{"api_key": "new-secure-key"}'
   ```

3. **影響範囲の調査**
   ```bash
   # CloudTrailでの使用履歴確認
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=ResourceName,AttributeValue=secret-name \
     --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)
   ```

#### フォローアップ（24時間以内）
- インシデントレポート作成
- 再発防止策の検討
- セキュリティ監査の実施

### 2. 不正アクセスの検知

```bash
# 異常なアクセスパターンの検索
aws logs filter-log-events \
  --log-group-name /aws/lambda/function-name \
  --filter-pattern '{ $.errorCode = "*AccessDenied*" }' \
  --start-time $(date -d '1 hour ago' +%s)000
```

## 開発者ガイドライン

### DO ✅
- 環境変数からシークレットを読み込む
- エラー時は適切にハンドリング
- キャッシュを活用してAPI呼び出しを削減
- 定期的にシークレットをローテーション

### DON'T ❌
- ハードコーディング
- ログへのシークレット出力
- 例外メッセージにシークレットを含める
- 本番シークレットをローカルで使用

### コードレビューチェックリスト
- [ ] シークレットがハードコードされていない
- [ ] console.logでシークレットが出力されていない
- [ ] エラーメッセージにシークレットが含まれていない
- [ ] 適切なエラーハンドリングがされている
- [ ] 環境変数名が適切（SLACK_BOT_TOKENなど）

## 自動化ツール

### シークレットスキャナー
```bash
# git-secretsのインストールと設定
git secrets --install
git secrets --register-aws

# カスタムパターンの追加
git secrets --add 'xoxb-[0-9A-Za-z-]+'  # Slack bot token
git secrets --add 'sk_[0-9A-Za-z]+'      # Stripe secret key
```

### pre-commitフック
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
```

## まとめ

シークレット管理は継続的な注意が必要です。定期的な監査、ローテーション、アクセス制御により、セキュアな環境を維持しましょう。

### 関連ドキュメント
- [セットアップガイド](./secrets/setup-guide.md)
- [AWS Secrets Manager ベストプラクティス](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [OWASP シークレット管理チートシート](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)