#!/bin/bash

# Event Ingest Lambda implementation script

set -e

echo "=== Implementing event_ingest Lambda function ==="

# Create enhanced event_ingest implementation
echo "Creating event_ingest Lambda function..."
cat > src/event_ingest/index.js << 'EOF'
/**
 * Event Ingest Lambda Function
 * Receives Slack events and queues them for processing
 */

const AWS = require('aws-sdk');
const crypto = require('crypto');

// AWS SDK clients
const sqs = new AWS.SQS({
  region: process.env.AWS_REGION || 'ap-northeast-1',
  endpoint: process.env.LOCAL_SQS_ENDPOINT // For local testing
});

const secretsManager = new AWS.SecretsManager({
  region: process.env.AWS_REGION || 'ap-northeast-1',
  endpoint: process.env.LOCAL_SECRETS_ENDPOINT // For local testing
});

// Constants
const SLACK_SIGNATURE_VERSION = 'v0';
const SIGNATURE_TIMEOUT = 5 * 60; // 5 minutes

// Logging utility
const log = (level, message, data = {}) => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data,
    functionName: process.env.AWS_LAMBDA_FUNCTION_NAME,
    requestId: process.env.AWS_LAMBDA_REQUEST_ID
  }));
};

/**
 * Verify Slack request signature
 * @param {string} signature - X-Slack-Signature header
 * @param {string} timestamp - X-Slack-Request-Timestamp header
 * @param {string} body - Raw request body
 * @param {string} signingSecret - Slack signing secret
 * @returns {boolean} - True if signature is valid
 */
function verifySlackSignature(signature, timestamp, body, signingSecret) {
  // Check timestamp to prevent replay attacks
  const currentTime = Math.floor(Date.now() / 1000);
  if (Math.abs(currentTime - parseInt(timestamp)) > SIGNATURE_TIMEOUT) {
    log('warn', 'Request timestamp too old', { timestamp, currentTime });
    return false;
  }

  // Compute expected signature
  const sigBasestring = `${SLACK_SIGNATURE_VERSION}:${timestamp}:${body}`;
  const mySignature = `${SLACK_SIGNATURE_VERSION}=` + 
    crypto.createHmac('sha256', signingSecret)
      .update(sigBasestring, 'utf8')
      .digest('hex');

  // Compare signatures
  return crypto.timingSafeEqual(
    Buffer.from(mySignature, 'utf8'),
    Buffer.from(signature, 'utf8')
  );
}

/**
 * Get signing secret from Secrets Manager or environment
 * @returns {Promise<string>} - Signing secret
 */
async function getSigningSecret() {
  // For local development
  if (process.env.SLACK_SIGNING_SECRET) {
    return process.env.SLACK_SIGNING_SECRET;
  }

  // From Secrets Manager
  try {
    const secretId = process.env.SLACK_SIGNING_SECRET;
    const data = await secretsManager.getSecretValue({ SecretId: secretId }).promise();
    const secret = JSON.parse(data.SecretString);
    return secret.signing_secret;
  } catch (error) {
    log('error', 'Failed to retrieve signing secret', { error: error.message });
    throw error;
  }
}

/**
 * Send message to SQS queue
 * @param {object} message - Message to send
 * @returns {Promise<object>} - SQS response
 */
async function sendToQueue(message) {
  const params = {
    QueueUrl: process.env.SQS_QUEUE_URL,
    MessageBody: JSON.stringify(message),
    MessageAttributes: {
      eventType: {
        DataType: 'String',
        StringValue: message.eventType || 'unknown'
      },
      source: {
        DataType: 'String',
        StringValue: 'slack-event-ingest'
      },
      timestamp: {
        DataType: 'String',
        StringValue: new Date().toISOString()
      }
    }
  };

  return sqs.sendMessage(params).promise();
}

/**
 * Process Slack event
 * @param {object} event - Slack event data
 * @returns {Promise<object>} - Processing result
 */
async function processSlackEvent(event) {
  const eventType = event.type;
  
  switch (eventType) {
    case 'event_callback':
      // Process actual event
      const slackEvent = event.event;
      
      // Check if message contains trigger keyword
      if (slackEvent.type === 'message' && 
          slackEvent.text && 
          slackEvent.text.includes('Backlog登録希望')) {
        
        log('info', 'Backlog registration request detected', {
          channel: slackEvent.channel,
          user: slackEvent.user,
          text: slackEvent.text
        });

        // Create SQS message
        const message = {
          messageId: `${event.event_id}-${Date.now()}`,
          timestamp: new Date().toISOString(),
          source: 'slack-event-ingest',
          eventType: 'slack.message.backlog_request',
          data: {
            slackEvent: slackEvent,
            metadata: {
              teamId: event.team_id,
              eventId: event.event_id,
              eventTime: event.event_time
            }
          },
          retryCount: 0
        };

        // Send to SQS
        await sendToQueue(message);
        log('info', 'Message sent to queue', { 
          messageId: message.messageId,
          eventId: event.event_id 
        });
      }
      
      return { statusCode: 200, body: JSON.stringify({ ok: true }) };

    case 'url_verification':
      // Respond to Slack URL verification challenge
      log('info', 'URL verification challenge received');
      return { 
        statusCode: 200, 
        body: JSON.stringify({ challenge: event.challenge }) 
      };

    default:
      log('warn', 'Unknown event type', { eventType });
      return { statusCode: 200, body: JSON.stringify({ ok: true }) };
  }
}

/**
 * Lambda handler function
 */
exports.handler = async (event, context) => {
  const startTime = Date.now();
  
  try {
    log('info', 'Lambda function invoked', {
      requestId: context.requestId,
      functionArn: context.invokedFunctionArn,
      remainingTime: context.getRemainingTimeInMillis()
    });

    // Parse request body
    let body;
    try {
      body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
    } catch (error) {
      log('error', 'Invalid JSON in request body', { error: error.message });
      return {
        statusCode: 400,
        body: JSON.stringify({ error: 'Invalid request body' })
      };
    }

    // Handle URL verification immediately (no signature check needed)
    if (body.type === 'url_verification') {
      return await processSlackEvent(body);
    }

    // Get headers
    const headers = event.headers || {};
    const signature = headers['X-Slack-Signature'] || headers['x-slack-signature'];
    const timestamp = headers['X-Slack-Request-Timestamp'] || headers['x-slack-request-timestamp'];

    if (!signature || !timestamp) {
      log('warn', 'Missing required headers', { headers: Object.keys(headers) });
      return {
        statusCode: 400,
        body: JSON.stringify({ error: 'Missing required headers' })
      };
    }

    // Verify signature
    const signingSecret = await getSigningSecret();
    const isValid = verifySlackSignature(
      signature,
      timestamp,
      event.body,
      signingSecret
    );

    if (!isValid) {
      log('warn', 'Invalid request signature');
      return {
        statusCode: 401,
        body: JSON.stringify({ error: 'Invalid signature' })
      };
    }

    // Process the event
    const result = await processSlackEvent(body);
    
    const duration = Date.now() - startTime;
    log('info', 'Request processed successfully', { 
      duration,
      statusCode: result.statusCode 
    });

    return result;

  } catch (error) {
    log('error', 'Unhandled error in Lambda function', {
      error: error.message,
      stack: error.stack,
      duration: Date.now() - startTime
    });

    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Internal server error' })
    };
  }
};

// Export for testing
if (process.env.NODE_ENV === 'test') {
  exports.verifySlackSignature = verifySlackSignature;
  exports.processSlackEvent = processSlackEvent;
  exports.sendToQueue = sendToQueue;
}
EOF

# Create package.json for event_ingest function
echo "Updating event_ingest package.json..."
cat > src/event_ingest/package.json << 'EOF'
{
  "name": "slack2backlog-event-ingest",
  "version": "1.0.0",
  "description": "Event ingest Lambda function for slack2backlog",
  "main": "index.js",
  "scripts": {
    "test": "jest",
    "lint": "eslint index.js"
  },
  "dependencies": {
    "aws-sdk": "^2.1691.0"
  },
  "devDependencies": {
    "eslint": "^8.57.0",
    "jest": "^30.0.0"
  }
}
EOF

# Create comprehensive test file
echo "Creating test file for event_ingest..."
cat > tests/unit/event_ingest.test.js << 'EOF'
const { handler, verifySlackSignature, processSlackEvent, sendToQueue } = require('../../src/event_ingest');
const AWS = require('aws-sdk');
const crypto = require('crypto');

// Mock AWS SDK
jest.mock('aws-sdk', () => {
  const SQSMock = {
    sendMessage: jest.fn().mockReturnThis(),
    promise: jest.fn()
  };
  const SecretsManagerMock = {
    getSecretValue: jest.fn().mockReturnThis(),
    promise: jest.fn()
  };
  return {
    SQS: jest.fn(() => SQSMock),
    SecretsManager: jest.fn(() => SecretsManagerMock)
  };
});

describe('Event Ingest Lambda Function', () => {
  let mockSQS;
  let mockSecretsManager;
  const mockContext = {
    requestId: 'test-request-id',
    invokedFunctionArn: 'arn:aws:lambda:region:account:function:test',
    getRemainingTimeInMillis: () => 30000
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockSQS = new AWS.SQS();
    mockSecretsManager = new AWS.SecretsManager();
    
    // Set up environment variables
    process.env.SQS_QUEUE_URL = 'https://sqs.region.amazonaws.com/account/test-queue';
    process.env.SLACK_SIGNING_SECRET = 'test-signing-secret';
    process.env.NODE_ENV = 'test';
  });

  describe('handler', () => {
    test('should handle URL verification challenge', async () => {
      const event = {
        body: JSON.stringify({
          type: 'url_verification',
          challenge: 'test-challenge-123'
        }),
        headers: {}
      };

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(200);
      expect(JSON.parse(result.body)).toEqual({ challenge: 'test-challenge-123' });
    });

    test('should reject invalid JSON body', async () => {
      const event = {
        body: 'invalid-json',
        headers: {}
      };

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(400);
      expect(JSON.parse(result.body)).toEqual({ error: 'Invalid request body' });
    });

    test('should reject missing headers', async () => {
      const event = {
        body: JSON.stringify({ type: 'event_callback' }),
        headers: {}
      };

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(400);
      expect(JSON.parse(result.body)).toEqual({ error: 'Missing required headers' });
    });

    test('should process valid Slack event with Backlog keyword', async () => {
      const timestamp = Math.floor(Date.now() / 1000).toString();
      const body = JSON.stringify({
        type: 'event_callback',
        event: {
          type: 'message',
          text: 'Backlog登録希望 新しいタスク',
          channel: 'C123',
          user: 'U123'
        },
        event_id: 'Ev123',
        team_id: 'T123',
        event_time: timestamp
      });

      // Create valid signature
      const signingSecret = 'test-signing-secret';
      const sigBasestring = `v0:${timestamp}:${body}`;
      const signature = 'v0=' + crypto
        .createHmac('sha256', signingSecret)
        .update(sigBasestring, 'utf8')
        .digest('hex');

      const event = {
        body,
        headers: {
          'X-Slack-Signature': signature,
          'X-Slack-Request-Timestamp': timestamp
        }
      };

      mockSQS.promise.mockResolvedValue({ MessageId: 'test-message-id' });

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(200);
      expect(JSON.parse(result.body)).toEqual({ ok: true });
      expect(mockSQS.sendMessage).toHaveBeenCalledWith(
        expect.objectContaining({
          QueueUrl: process.env.SQS_QUEUE_URL,
          MessageBody: expect.stringContaining('Backlog登録希望')
        })
      );
    });

    test('should ignore messages without Backlog keyword', async () => {
      const timestamp = Math.floor(Date.now() / 1000).toString();
      const body = JSON.stringify({
        type: 'event_callback',
        event: {
          type: 'message',
          text: 'Regular message without keyword',
          channel: 'C123',
          user: 'U123'
        },
        event_id: 'Ev123',
        team_id: 'T123',
        event_time: timestamp
      });

      const signingSecret = 'test-signing-secret';
      const sigBasestring = `v0:${timestamp}:${body}`;
      const signature = 'v0=' + crypto
        .createHmac('sha256', signingSecret)
        .update(sigBasestring, 'utf8')
        .digest('hex');

      const event = {
        body,
        headers: {
          'X-Slack-Signature': signature,
          'X-Slack-Request-Timestamp': timestamp
        }
      };

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(200);
      expect(mockSQS.sendMessage).not.toHaveBeenCalled();
    });
  });

  describe('verifySlackSignature', () => {
    test('should verify valid signature', () => {
      const timestamp = Math.floor(Date.now() / 1000).toString();
      const body = 'test-body';
      const signingSecret = 'test-secret';
      const sigBasestring = `v0:${timestamp}:${body}`;
      const signature = 'v0=' + crypto
        .createHmac('sha256', signingSecret)
        .update(sigBasestring, 'utf8')
        .digest('hex');

      const result = verifySlackSignature(signature, timestamp, body, signingSecret);

      expect(result).toBe(true);
    });

    test('should reject old timestamp', () => {
      const oldTimestamp = (Math.floor(Date.now() / 1000) - 400).toString(); // 6+ minutes old
      const body = 'test-body';
      const signingSecret = 'test-secret';
      const signature = 'v0=invalid';

      const result = verifySlackSignature(signature, oldTimestamp, body, signingSecret);

      expect(result).toBe(false);
    });

    test('should reject invalid signature', () => {
      const timestamp = Math.floor(Date.now() / 1000).toString();
      const body = 'test-body';
      const signingSecret = 'test-secret';
      const signature = 'v0=invalid-signature';

      const result = verifySlackSignature(signature, timestamp, body, signingSecret);

      expect(result).toBe(false);
    });
  });

  describe('sendToQueue', () => {
    test('should send message to SQS', async () => {
      const message = {
        messageId: 'test-123',
        eventType: 'test.event',
        data: { test: true }
      };

      mockSQS.promise.mockResolvedValue({ MessageId: 'sqs-message-id' });

      await sendToQueue(message);

      expect(mockSQS.sendMessage).toHaveBeenCalledWith({
        QueueUrl: process.env.SQS_QUEUE_URL,
        MessageBody: JSON.stringify(message),
        MessageAttributes: expect.objectContaining({
          eventType: {
            DataType: 'String',
            StringValue: 'test.event'
          }
        })
      });
    });
  });
});
EOF

# Create deployment documentation
echo "Creating deployment documentation..."
cat > docs/LAMBDA_DEPLOYMENT_GUIDE.md << 'EOF'
# Lambda関数デプロイメントガイド

## event_ingest関数

### 概要
Slackからのイベントを受信し、SQSキューに送信するLambda関数です。

### 主な機能
- Slack署名検証
- URLチャレンジ応答
- "Backlog登録希望"キーワード検出
- SQSへのメッセージ送信
- 構造化ログ出力

### 環境変数

| 変数名 | 説明 | 例 |
|--------|------|-----|
| SQS_QUEUE_URL | SQSキューのURL | https://sqs.region.amazonaws.com/account/queue |
| SLACK_SIGNING_SECRET | Slackシークレットの参照 | arn:aws:secretsmanager:region:account:secret:name |
| AWS_REGION | AWSリージョン | ap-northeast-1 |
| LOG_LEVEL | ログレベル | info |

### ローカルテスト

```bash
# 単体テスト実行
npm test tests/unit/event_ingest.test.js

# カバレッジ付きテスト
npm run test:coverage -- tests/unit/event_ingest.test.js

# ローカル実行
sam local start-api
```

### デプロイ

```bash
# ビルド
sam build

# デプロイ（開発環境）
sam deploy --config-env dev

# デプロイ（本番環境）
sam deploy --config-env prod --parameter-overrides Stage=prod
```

### ログ確認

```bash
# CloudWatch Logsの確認
aws logs tail /aws/lambda/slack2backlog-event-ingest-dev --follow

# 特定のエラーを検索
aws logs filter-log-events \
  --log-group-name /aws/lambda/slack2backlog-event-ingest-dev \
  --filter-pattern '{ $.level = "error" }'
```

### パフォーマンスチューニング

1. **メモリ設定**: 512MB（デフォルト）
   - 署名検証とJSON処理には十分
   - 必要に応じて256MB-1024MBで調整

2. **タイムアウト**: 10秒
   - Slackの3秒制限に対応
   - SQS送信を含めても十分な余裕

3. **同時実行数**: 制限なし
   - スパイクに対応可能
   - 必要に応じてリザーブドコンカレンシー設定

### トラブルシューティング

#### 署名検証エラー
```javascript
// ログで以下を確認
{ 
  "level": "warn", 
  "message": "Invalid request signature"
}
```
- Signing Secretが正しいか確認
- タイムスタンプのずれを確認（NTPサーバー同期）

#### SQS送信エラー
```javascript
{
  "level": "error",
  "message": "Failed to send to queue",
  "error": "Access Denied"
}
```
- IAMロールの権限確認
- SQSキューURLの確認

#### タイムアウト
- Lambda関数のタイムアウト設定確認
- SQSエンドポイントの接続性確認
- VPC設定の確認（使用している場合）

## 監視設定

### CloudWatchメトリクス
- Invocations: 呼び出し回数
- Errors: エラー率
- Duration: 実行時間
- Throttles: スロットリング

### アラーム推奨設定
```yaml
ErrorRateAlarm:
  MetricName: Errors
  Threshold: 1
  EvaluationPeriods: 1
  Period: 60

HighLatencyAlarm:
  MetricName: Duration
  Threshold: 3000  # 3秒
  EvaluationPeriods: 2
  Period: 60
```
EOF

echo "=== event_ingest Lambda implementation complete! ==="
echo ""
echo "Created/Updated files:"
echo "  - src/event_ingest/index.js           : Lambda function implementation"
echo "  - src/event_ingest/package.json       : Function dependencies"
echo "  - tests/unit/event_ingest.test.js     : Comprehensive unit tests"
echo "  - docs/LAMBDA_DEPLOYMENT_GUIDE.md     : Deployment documentation"
echo ""
echo "Next steps:"
echo "1. Run tests: npm test tests/unit/event_ingest.test.js"
echo "2. Test locally: sam local start-api"
echo "3. Deploy: sam deploy"