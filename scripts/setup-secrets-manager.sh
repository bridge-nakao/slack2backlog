#!/bin/bash

# Secrets Manager setup script for slack2backlog

set -e  # Exit on error

echo "=== Setting up Secrets Manager for slack2backlog ==="

# Create enhanced Secrets Manager configuration
echo "Creating enhanced Secrets Manager configuration..."
cat > template-secrets-enhanced.yaml << 'EOF'
# Enhanced Secrets Manager configurations to be integrated with main template
Resources:
  # Slack credentials secret
  SlackSecrets:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub ${AWS::StackName}-slack-secrets-${Stage}
      Description: Slack Bot Token and Signing Secret for slack2backlog
      SecretString: !Sub |
        {
          "bot_token": "${SlackBotToken}",
          "signing_secret": "${SlackSigningSecret}"
        }
      KmsKeyId: alias/aws/secretsmanager
      Tags:
        - Key: Environment
          Value: !Ref Stage
        - Key: Application
          Value: slack2backlog
        - Key: Type
          Value: credentials

  # Backlog credentials secret
  BacklogSecrets:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub ${AWS::StackName}-backlog-secrets-${Stage}
      Description: Backlog API credentials for slack2backlog
      SecretString: !Sub |
        {
          "api_key": "${BacklogApiKey}",
          "space_id": "${BacklogSpaceId}"
        }
      KmsKeyId: alias/aws/secretsmanager
      Tags:
        - Key: Environment
          Value: !Ref Stage
        - Key: Application
          Value: slack2backlog
        - Key: Type
          Value: credentials

  # Secret rotation Lambda (optional, for future implementation)
  SecretRotationLambda:
    Type: AWS::SecretsManager::RotationSchedule
    Condition: EnableRotation
    Properties:
      SecretId: !Ref SlackSecrets
      RotationRules:
        AutomaticallyAfterDays: 90
      RotationLambdaARN: !GetAtt SecretRotationFunction.Arn

  # Resource policies for secrets
  SlackSecretsResourcePolicy:
    Type: AWS::SecretsManager::ResourcePolicy
    Properties:
      SecretId: !Ref SlackSecrets
      ResourcePolicy:
        Version: '2012-10-17'
        Statement:
          - Sid: AllowLambdaAccess
            Effect: Allow
            Principal:
              AWS:
                - !GetAtt EventIngestFunctionRole.Arn
                - !GetAtt BacklogWorkerFunctionRole.Arn
            Action:
              - secretsmanager:GetSecretValue
              - secretsmanager:DescribeSecret
            Resource: '*'

  BacklogSecretsResourcePolicy:
    Type: AWS::SecretsManager::ResourcePolicy
    Properties:
      SecretId: !Ref BacklogSecrets
      ResourcePolicy:
        Version: '2012-10-17'
        Statement:
          - Sid: AllowLambdaAccess
            Effect: Allow
            Principal:
              AWS: !GetAtt BacklogWorkerFunctionRole.Arn
            Action:
              - secretsmanager:GetSecretValue
              - secretsmanager:DescribeSecret
            Resource: '*'

# Parameters for initial secret values
Parameters:
  SlackBotToken:
    Type: String
    NoEcho: true
    Default: "xoxb-your-token-here"
    Description: Slack Bot User OAuth Token

  SlackSigningSecret:
    Type: String
    NoEcho: true
    Default: "your-signing-secret-here"
    Description: Slack Signing Secret

  BacklogApiKey:
    Type: String
    NoEcho: true
    Default: "your-backlog-api-key-here"
    Description: Backlog API Key

  BacklogSpaceId:
    Type: String
    Default: "your-space-id"
    Description: Backlog Space ID

  EnableRotation:
    Type: String
    Default: "false"
    AllowedValues:
      - "true"
      - "false"
    Description: Enable automatic secret rotation

Conditions:
  EnableRotation: !Equals [!Ref EnableRotation, "true"]

Outputs:
  SlackSecretsArn:
    Description: ARN of the Slack secrets
    Value: !Ref SlackSecrets
    Export:
      Name: !Sub ${AWS::StackName}-SlackSecretsArn

  BacklogSecretsArn:
    Description: ARN of the Backlog secrets
    Value: !Ref BacklogSecrets
    Export:
      Name: !Sub ${AWS::StackName}-BacklogSecretsArn
EOF

# Create local environment file template
echo "Creating .env.example file..."
cat > .env.example << 'EOF'
# Slack Configuration
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_SIGNING_SECRET=your-signing-secret

# Backlog Configuration
BACKLOG_API_KEY=your-api-key
BACKLOG_SPACE_ID=your-space-id
BACKLOG_SPACE=example.backlog.com
PROJECT_ID=12345
ISSUE_TYPE_ID=67890
PRIORITY_ID=3

# AWS Configuration (for local development)
AWS_REGION=ap-northeast-1
AWS_PROFILE=default

# Application Configuration
STAGE=dev
LOG_LEVEL=debug
NODE_ENV=development

# Local Development URLs (when using LocalStack)
LOCAL_SQS_ENDPOINT=http://localhost:4566
LOCAL_DYNAMODB_ENDPOINT=http://localhost:8000
LOCAL_SECRETS_ENDPOINT=http://localhost:4566

# Testing Configuration
TEST_MODE=true
MOCK_EXTERNAL_APIS=true
EOF

# Add .env to .gitignore if not already present
if ! grep -q "^\.env$" .gitignore 2>/dev/null; then
    echo "Adding .env to .gitignore..."
    echo "" >> .gitignore
    echo "# Environment variables" >> .gitignore
    echo ".env" >> .gitignore
    echo ".env.local" >> .gitignore
    echo ".env.*.local" >> .gitignore
fi

# Create secrets helper functions
echo "Creating secrets helper functions..."
mkdir -p src/shared
cat > src/shared/secrets-manager.js << 'EOF'
/**
 * Secrets Manager helper functions
 */

const AWS = require('aws-sdk');

// Configure AWS SDK
const secretsManager = new AWS.SecretsManager({
  region: process.env.AWS_REGION || 'ap-northeast-1',
  endpoint: process.env.LOCAL_SECRETS_ENDPOINT // For local testing with LocalStack
});

// Cache for secrets to avoid repeated API calls
const secretsCache = new Map();
const CACHE_TTL = 300000; // 5 minutes

/**
 * Get secret value from Secrets Manager
 * @param {string} secretId - The secret ID or ARN
 * @returns {Promise<object>} - The secret value as an object
 */
async function getSecret(secretId) {
  // Check cache first
  const cached = secretsCache.get(secretId);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    console.log(`Returning cached secret for ${secretId}`);
    return cached.value;
  }

  try {
    console.log(`Fetching secret: ${secretId}`);
    const data = await secretsManager.getSecretValue({ SecretId: secretId }).promise();
    
    let secretValue;
    if ('SecretString' in data) {
      secretValue = JSON.parse(data.SecretString);
    } else {
      // Binary secret
      const buff = Buffer.from(data.SecretBinary, 'base64');
      secretValue = JSON.parse(buff.toString('ascii'));
    }

    // Cache the secret
    secretsCache.set(secretId, {
      value: secretValue,
      timestamp: Date.now()
    });

    return secretValue;
  } catch (error) {
    console.error(`Error retrieving secret ${secretId}:`, error);
    throw error;
  }
}

/**
 * Get specific secret value
 * @param {string} secretId - The secret ID or ARN
 * @param {string} key - The key within the secret
 * @returns {Promise<string>} - The specific secret value
 */
async function getSecretValue(secretId, key) {
  const secret = await getSecret(secretId);
  if (!secret[key]) {
    throw new Error(`Key ${key} not found in secret ${secretId}`);
  }
  return secret[key];
}

/**
 * Clear secrets cache
 */
function clearCache() {
  secretsCache.clear();
}

/**
 * Initialize secrets from environment variables (for local development)
 * @returns {object} - Secrets object
 */
function getSecretsFromEnv() {
  return {
    slack: {
      bot_token: process.env.SLACK_BOT_TOKEN,
      signing_secret: process.env.SLACK_SIGNING_SECRET
    },
    backlog: {
      api_key: process.env.BACKLOG_API_KEY,
      space_id: process.env.BACKLOG_SPACE_ID
    }
  };
}

module.exports = {
  getSecret,
  getSecretValue,
  clearCache,
  getSecretsFromEnv
};
EOF

# Create secrets testing script
echo "Creating secrets testing script..."
cat > scripts/test-secrets-manager.sh << 'EOF'
#!/bin/bash

# Secrets Manager testing script

set -e

echo "=== Testing Secrets Manager ==="

STACK_NAME="${1:-slack2backlog}"
STAGE="${2:-dev}"
REGION="${3:-ap-northeast-1}"

# Get secret ARNs from CloudFormation outputs
echo "Getting secret ARNs..."
SLACK_SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='SlackSecretsArn'].OutputValue" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

BACKLOG_SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='BacklogSecretsArn'].OutputValue" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

if [ -z "$SLACK_SECRET_ARN" ]; then
    echo "Warning: Could not find secret ARNs. Using default names."
    SLACK_SECRET_ARN="$STACK_NAME-slack-secrets-$STAGE"
    BACKLOG_SECRET_ARN="$STACK_NAME-backlog-secrets-$STAGE"
fi

echo "Slack Secret: $SLACK_SECRET_ARN"
echo "Backlog Secret: $BACKLOG_SECRET_ARN"
echo ""

# Test 1: Describe secrets
echo "Test 1: Describing secrets"
echo "Slack secret metadata:"
aws secretsmanager describe-secret \
    --secret-id "$SLACK_SECRET_ARN" \
    --region $REGION \
    --query '{Name: Name, Description: Description, LastChangedDate: LastChangedDate}' \
    2>/dev/null || echo "Secret not found"

echo ""
echo "Backlog secret metadata:"
aws secretsmanager describe-secret \
    --secret-id "$BACKLOG_SECRET_ARN" \
    --region $REGION \
    --query '{Name: Name, Description: Description, LastChangedDate: LastChangedDate}' \
    2>/dev/null || echo "Secret not found"

# Test 2: Get secret values (only in test mode)
if [ "$4" = "--show-values" ]; then
    echo ""
    echo "Test 2: Getting secret values (TEST MODE)"
    echo "WARNING: This will display sensitive information!"
    echo ""
    
    echo "Slack secrets:"
    aws secretsmanager get-secret-value \
        --secret-id "$SLACK_SECRET_ARN" \
        --region $REGION \
        --query 'SecretString' \
        --output text 2>/dev/null | jq '.' || echo "Failed to retrieve"
    
    echo ""
    echo "Backlog secrets:"
    aws secretsmanager get-secret-value \
        --secret-id "$BACKLOG_SECRET_ARN" \
        --region $REGION \
        --query 'SecretString' \
        --output text 2>/dev/null | jq '.' || echo "Failed to retrieve"
fi

# Test 3: Check secret policies
echo ""
echo "Test 3: Checking resource policies"
aws secretsmanager get-resource-policy \
    --secret-id "$SLACK_SECRET_ARN" \
    --region $REGION \
    --query 'ResourcePolicy' \
    --output text 2>/dev/null | jq '.' || echo "No resource policy"

echo ""
echo "=== Secrets Manager tests complete ==="
EOF

chmod +x scripts/test-secrets-manager.sh

# Create secrets setup documentation
echo "Creating secrets setup documentation..."
mkdir -p docs/secrets
cat > docs/secrets/setup-guide.md << 'EOF'
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
EOF

echo "=== Secrets Manager configuration complete! ==="
echo ""
echo "Created files:"
echo "  - template-secrets-enhanced.yaml      : Enhanced Secrets Manager config"
echo "  - .env.example                       : Environment variables template"
echo "  - src/shared/secrets-manager.js      : Secrets helper functions"
echo "  - scripts/test-secrets-manager.sh    : Testing script"
echo "  - docs/secrets/setup-guide.md        : Setup documentation"
echo ""
echo "Next steps:"
echo "1. Copy .env.example to .env and fill in your values"
echo "2. Deploy with 'sam deploy --parameter-overrides ...'"
echo "3. Test with './scripts/test-secrets-manager.sh'"
echo "4. Never commit .env file to version control!"