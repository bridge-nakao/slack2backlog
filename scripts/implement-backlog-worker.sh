#!/bin/bash

# Backlog Worker Lambda implementation script

set -e

echo "=== Implementing backlog_worker Lambda function ==="

# Create backlog_worker implementation
echo "Creating backlog_worker Lambda function..."
cat > src/backlog_worker/index.js << 'EOF'
/**
 * Backlog Worker Lambda Function
 * Processes queued events and creates Backlog issues
 */

const AWS = require('aws-sdk');
const axios = require('axios');

// AWS SDK clients
const dynamodb = new AWS.DynamoDB.DocumentClient({
  region: process.env.AWS_REGION || 'ap-northeast-1',
  endpoint: process.env.LOCAL_DYNAMODB_ENDPOINT // For local testing
});

const secretsManager = new AWS.SecretsManager({
  region: process.env.AWS_REGION || 'ap-northeast-1',
  endpoint: process.env.LOCAL_SECRETS_ENDPOINT // For local testing
});

// Initialize Slack Web API client
const { WebClient } = require('@slack/web-api');
let slackClient = null;

// Constants
const MAX_RETRIES = 3;
const BACKOFF_BASE = 1000; // 1 second

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
 * Get secrets from Secrets Manager
 * @returns {Promise<object>} - Secrets object
 */
async function getSecrets() {
  try {
    // Get Slack secrets
    const slackSecretId = process.env.SLACK_BOT_TOKEN || 'slack2backlog-slack-secrets';
    const slackData = await secretsManager.getSecretValue({ SecretId: slackSecretId }).promise();
    const slackSecret = JSON.parse(slackData.SecretString);

    // Get Backlog secrets
    const backlogSecretId = process.env.BACKLOG_API_KEY || 'slack2backlog-backlog-secrets';
    const backlogData = await secretsManager.getSecretValue({ SecretId: backlogSecretId }).promise();
    const backlogSecret = JSON.parse(backlogData.SecretString);

    return {
      slack: {
        botToken: slackSecret.bot_token || process.env.SLACK_BOT_TOKEN
      },
      backlog: {
        apiKey: backlogSecret.api_key || process.env.BACKLOG_API_KEY,
        spaceId: backlogSecret.space_id || process.env.BACKLOG_SPACE_ID
      }
    };
  } catch (error) {
    log('error', 'Failed to retrieve secrets', { error: error.message });
    throw error;
  }
}

/**
 * Initialize Slack client
 * @param {string} token - Slack bot token
 */
function initializeSlackClient(token) {
  if (!slackClient) {
    slackClient = new WebClient(token);
  }
  return slackClient;
}

/**
 * Check if message has already been processed (idempotency)
 * @param {string} eventId - Slack event ID
 * @returns {Promise<boolean>} - True if already processed
 */
async function isAlreadyProcessed(eventId) {
  try {
    const params = {
      TableName: process.env.IDEMPOTENCY_TABLE,
      Key: { event_id: eventId }
    };
    
    const result = await dynamodb.get(params).promise();
    return !!result.Item;
  } catch (error) {
    log('warn', 'Failed to check idempotency', { error: error.message, eventId });
    return false;
  }
}

/**
 * Mark message as processed
 * @param {string} eventId - Slack event ID
 * @param {object} metadata - Processing metadata
 */
async function markAsProcessed(eventId, metadata) {
  try {
    const ttl = Math.floor(Date.now() / 1000) + (24 * 60 * 60); // 24 hours
    
    const params = {
      TableName: process.env.IDEMPOTENCY_TABLE,
      Item: {
        event_id: eventId,
        processed_at: new Date().toISOString(),
        ttl: ttl,
        ...metadata
      }
    };
    
    await dynamodb.put(params).promise();
  } catch (error) {
    log('error', 'Failed to mark as processed', { error: error.message, eventId });
    // Don't throw - this shouldn't stop processing
  }
}

/**
 * Create Backlog issue
 * @param {object} slackEvent - Slack event data
 * @param {object} credentials - Backlog credentials
 * @returns {Promise<object>} - Created issue data
 */
async function createBacklogIssue(slackEvent, credentials) {
  const backlogUrl = `https://${process.env.BACKLOG_SPACE}/api/v2/issues`;
  
  // Extract task description from Slack message
  const text = slackEvent.text || '';
  const taskDescription = text.replace('Backlog登録希望', '').trim();
  
  const params = {
    projectId: process.env.PROJECT_ID,
    summary: taskDescription || 'Slackから登録されたタスク',
    issueTypeId: process.env.ISSUE_TYPE_ID,
    priorityId: process.env.PRIORITY_ID || 3,
    description: `Slackから自動登録されました。\n\n元のメッセージ:\n${text}\n\n投稿者: <@${slackEvent.user}>\nチャンネル: <#${slackEvent.channel}>\n時刻: ${new Date(parseFloat(slackEvent.ts) * 1000).toLocaleString('ja-JP')}`
  };

  try {
    const response = await axios.post(backlogUrl, params, {
      params: { apiKey: credentials.backlog.apiKey },
      timeout: 10000 // 10 seconds
    });

    log('info', 'Backlog issue created', {
      issueKey: response.data.issueKey,
      issueId: response.data.id,
      summary: response.data.summary
    });

    return response.data;
  } catch (error) {
    log('error', 'Failed to create Backlog issue', {
      error: error.message,
      status: error.response?.status,
      data: error.response?.data
    });
    throw error;
  }
}

/**
 * Post result to Slack thread
 * @param {object} slackEvent - Original Slack event
 * @param {object} issue - Created Backlog issue
 * @param {object} slackClient - Initialized Slack client
 */
async function postToSlackThread(slackEvent, issue, slackClient) {
  try {
    const backlogUrl = `https://${process.env.BACKLOG_SPACE}/view/${issue.issueKey}`;
    
    const result = await slackClient.chat.postMessage({
      channel: slackEvent.channel,
      thread_ts: slackEvent.ts,
      text: `課題を登録しました: <${backlogUrl}|${issue.issueKey}>`,
      unfurl_links: false
    });

    log('info', 'Posted to Slack thread', {
      channel: slackEvent.channel,
      thread_ts: slackEvent.ts,
      message_ts: result.ts
    });

    return result;
  } catch (error) {
    log('error', 'Failed to post to Slack', {
      error: error.message,
      channel: slackEvent.channel
    });
    throw error;
  }
}

/**
 * Process SQS message with retry logic
 * @param {object} message - SQS message
 * @param {object} credentials - API credentials
 * @returns {Promise<object>} - Processing result
 */
async function processMessage(message, credentials) {
  const body = JSON.parse(message.Body);
  const slackEvent = body.data.slackEvent;
  const eventId = body.data.metadata.eventId;

  // Check idempotency
  const alreadyProcessed = await isAlreadyProcessed(eventId);
  if (alreadyProcessed) {
    log('info', 'Event already processed, skipping', { eventId });
    return { status: 'skipped', reason: 'already_processed' };
  }

  // Initialize Slack client
  const slack = initializeSlackClient(credentials.slack.botToken);

  let lastError = null;
  let retryCount = body.retryCount || 0;

  // Retry loop with exponential backoff
  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      // Create Backlog issue
      const issue = await createBacklogIssue(slackEvent, credentials);

      // Post to Slack thread
      await postToSlackThread(slackEvent, issue, slack);

      // Mark as processed
      await markAsProcessed(eventId, {
        issue_key: issue.issueKey,
        issue_id: issue.id,
        retry_count: retryCount,
        attempt: attempt
      });

      return {
        status: 'success',
        issueKey: issue.issueKey,
        issueId: issue.id
      };

    } catch (error) {
      lastError = error;
      log('warn', `Attempt ${attempt + 1} failed`, {
        error: error.message,
        attempt,
        eventId
      });

      if (attempt < MAX_RETRIES - 1) {
        // Exponential backoff
        const delay = BACKOFF_BASE * Math.pow(2, attempt);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  // All retries failed
  throw lastError;
}

/**
 * Lambda handler function
 */
exports.handler = async (event, context) => {
  const startTime = Date.now();
  
  log('info', 'Lambda function invoked', {
    requestId: context.requestId,
    functionArn: context.invokedFunctionArn,
    messageCount: event.Records?.length || 0
  });

  // Get credentials once for all messages
  let credentials;
  try {
    credentials = await getSecrets();
  } catch (error) {
    log('error', 'Failed to get credentials', { error: error.message });
    // Return all messages as failures if we can't get credentials
    return {
      batchItemFailures: event.Records.map(record => ({
        itemIdentifier: record.messageId
      }))
    };
  }

  const results = [];
  const failures = [];

  // Process each SQS message
  for (const record of event.Records) {
    try {
      const result = await processMessage(record, credentials);
      results.push({
        messageId: record.messageId,
        result
      });
    } catch (error) {
      log('error', 'Failed to process message', {
        messageId: record.messageId,
        error: error.message,
        stack: error.stack
      });

      failures.push({
        itemIdentifier: record.messageId
      });
    }
  }

  const duration = Date.now() - startTime;
  log('info', 'Processing complete', {
    duration,
    processed: results.length,
    failed: failures.length
  });

  // Return failed message IDs for SQS retry
  return {
    batchItemFailures: failures
  };
};

// Export for testing
if (process.env.NODE_ENV === 'test') {
  exports.isAlreadyProcessed = isAlreadyProcessed;
  exports.markAsProcessed = markAsProcessed;
  exports.createBacklogIssue = createBacklogIssue;
  exports.postToSlackThread = postToSlackThread;
  exports.processMessage = processMessage;
}
EOF

# Update package.json for backlog_worker function
echo "Updating backlog_worker package.json..."
cat > src/backlog_worker/package.json << 'EOF'
{
  "name": "slack2backlog-backlog-worker",
  "version": "1.0.0",
  "description": "Backlog worker Lambda function for slack2backlog",
  "main": "index.js",
  "scripts": {
    "test": "jest",
    "lint": "eslint index.js"
  },
  "dependencies": {
    "aws-sdk": "^2.1691.0",
    "@slack/web-api": "^7.7.0",
    "axios": "^1.7.7"
  },
  "devDependencies": {
    "eslint": "^8.57.0",
    "jest": "^30.0.0",
    "nock": "^13.5.0"
  }
}
EOF

# Create comprehensive test file
echo "Creating test file for backlog_worker..."
cat > tests/unit/backlog_worker.test.js << 'EOF'
const {
  handler,
  isAlreadyProcessed,
  markAsProcessed,
  createBacklogIssue,
  postToSlackThread,
  processMessage
} = require('../../src/backlog_worker');

const AWS = require('aws-sdk');
const axios = require('axios');
const { WebClient } = require('@slack/web-api');

// Mock AWS SDK
jest.mock('aws-sdk', () => {
  const DynamoDBDocumentClientMock = {
    get: jest.fn().mockReturnThis(),
    put: jest.fn().mockReturnThis(),
    promise: jest.fn()
  };
  const SecretsManagerMock = {
    getSecretValue: jest.fn().mockReturnThis(),
    promise: jest.fn()
  };
  return {
    DynamoDB: {
      DocumentClient: jest.fn(() => DynamoDBDocumentClientMock)
    },
    SecretsManager: jest.fn(() => SecretsManagerMock)
  };
});

// Mock axios
jest.mock('axios');

// Mock Slack Web API
jest.mock('@slack/web-api', () => ({
  WebClient: jest.fn(() => ({
    chat: {
      postMessage: jest.fn()
    }
  }))
}));

describe('Backlog Worker Lambda Function', () => {
  let mockDynamoDB;
  let mockSecretsManager;
  let mockSlackClient;
  const mockContext = {
    requestId: 'test-request-id',
    invokedFunctionArn: 'arn:aws:lambda:region:account:function:test',
    getRemainingTimeInMillis: () => 30000
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockDynamoDB = new AWS.DynamoDB.DocumentClient();
    mockSecretsManager = new AWS.SecretsManager();
    mockSlackClient = new WebClient();
    
    // Set up environment variables
    process.env.IDEMPOTENCY_TABLE = 'test-idempotency-table';
    process.env.BACKLOG_SPACE = 'test.backlog.com';
    process.env.PROJECT_ID = '12345';
    process.env.ISSUE_TYPE_ID = '67890';
    process.env.PRIORITY_ID = '3';
    process.env.NODE_ENV = 'test';
  });

  describe('handler', () => {
    test('should process SQS messages successfully', async () => {
      const event = {
        Records: [{
          messageId: 'msg-123',
          body: JSON.stringify({
            data: {
              slackEvent: {
                type: 'message',
                text: 'Backlog登録希望 新しいタスク',
                channel: 'C123',
                user: 'U123',
                ts: '1234567890.123456'
              },
              metadata: {
                eventId: 'Ev123'
              }
            }
          })
        }]
      };

      // Mock secrets
      mockSecretsManager.promise
        .mockResolvedValueOnce({
          SecretString: JSON.stringify({
            bot_token: 'xoxb-test-token'
          })
        })
        .mockResolvedValueOnce({
          SecretString: JSON.stringify({
            api_key: 'test-api-key',
            space_id: 'test-space'
          })
        });

      // Mock DynamoDB (not already processed)
      mockDynamoDB.promise.mockResolvedValueOnce({ Item: null });
      mockDynamoDB.promise.mockResolvedValueOnce({}); // put success

      // Mock Backlog API
      axios.post.mockResolvedValueOnce({
        data: {
          id: 123,
          issueKey: 'TEST-123',
          summary: '新しいタスク'
        }
      });

      // Mock Slack API
      mockSlackClient.chat.postMessage.mockResolvedValueOnce({
        ok: true,
        ts: '1234567890.123457'
      });

      const result = await handler(event, mockContext);

      expect(result.batchItemFailures).toEqual([]);
      expect(axios.post).toHaveBeenCalledWith(
        expect.stringContaining('backlog.com/api/v2/issues'),
        expect.objectContaining({
          projectId: '12345',
          summary: '新しいタスク'
        }),
        expect.any(Object)
      );
    });

    test('should handle failed messages', async () => {
      const event = {
        Records: [{
          messageId: 'msg-123',
          body: JSON.stringify({
            data: {
              slackEvent: {
                text: 'Backlog登録希望 失敗するタスク',
                channel: 'C123',
                user: 'U123',
                ts: '1234567890.123456'
              },
              metadata: {
                eventId: 'Ev123'
              }
            }
          })
        }]
      };

      // Mock secrets
      mockSecretsManager.promise
        .mockResolvedValueOnce({
          SecretString: JSON.stringify({ bot_token: 'xoxb-test' })
        })
        .mockResolvedValueOnce({
          SecretString: JSON.stringify({ api_key: 'test-key' })
        });

      // Mock DynamoDB
      mockDynamoDB.promise.mockResolvedValueOnce({ Item: null });

      // Mock Backlog API failure
      axios.post.mockRejectedValue(new Error('API Error'));

      const result = await handler(event, mockContext);

      expect(result.batchItemFailures).toEqual([
        { itemIdentifier: 'msg-123' }
      ]);
    });
  });

  describe('isAlreadyProcessed', () => {
    test('should return true if already processed', async () => {
      mockDynamoDB.promise.mockResolvedValueOnce({
        Item: { event_id: 'Ev123', processed_at: '2025-06-26T00:00:00Z' }
      });

      const result = await isAlreadyProcessed('Ev123');

      expect(result).toBe(true);
      expect(mockDynamoDB.get).toHaveBeenCalledWith({
        TableName: 'test-idempotency-table',
        Key: { event_id: 'Ev123' }
      });
    });

    test('should return false if not processed', async () => {
      mockDynamoDB.promise.mockResolvedValueOnce({ Item: null });

      const result = await isAlreadyProcessed('Ev123');

      expect(result).toBe(false);
    });
  });

  describe('createBacklogIssue', () => {
    test('should create issue successfully', async () => {
      const slackEvent = {
        text: 'Backlog登録希望 テストタスク',
        user: 'U123',
        channel: 'C123',
        ts: '1234567890.123456'
      };

      const credentials = {
        backlog: { apiKey: 'test-api-key' }
      };

      axios.post.mockResolvedValueOnce({
        data: {
          id: 123,
          issueKey: 'TEST-123',
          summary: 'テストタスク'
        }
      });

      const result = await createBacklogIssue(slackEvent, credentials);

      expect(result.issueKey).toBe('TEST-123');
      expect(axios.post).toHaveBeenCalledWith(
        'https://test.backlog.com/api/v2/issues',
        expect.objectContaining({
          summary: 'テストタスク',
          projectId: '12345'
        }),
        expect.objectContaining({
          params: { apiKey: 'test-api-key' }
        })
      );
    });

    test('should handle empty task description', async () => {
      const slackEvent = {
        text: 'Backlog登録希望',
        user: 'U123',
        channel: 'C123',
        ts: '1234567890.123456'
      };

      const credentials = {
        backlog: { apiKey: 'test-api-key' }
      };

      axios.post.mockResolvedValueOnce({
        data: {
          id: 123,
          issueKey: 'TEST-124',
          summary: 'Slackから登録されたタスク'
        }
      });

      const result = await createBacklogIssue(slackEvent, credentials);

      expect(axios.post).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          summary: 'Slackから登録されたタスク'
        }),
        expect.any(Object)
      );
    });
  });

  describe('postToSlackThread', () => {
    test('should post to thread successfully', async () => {
      const slackEvent = {
        channel: 'C123',
        ts: '1234567890.123456'
      };

      const issue = {
        issueKey: 'TEST-123'
      };

      mockSlackClient.chat.postMessage.mockResolvedValueOnce({
        ok: true,
        ts: '1234567890.123457'
      });

      await postToSlackThread(slackEvent, issue, mockSlackClient);

      expect(mockSlackClient.chat.postMessage).toHaveBeenCalledWith({
        channel: 'C123',
        thread_ts: '1234567890.123456',
        text: expect.stringContaining('TEST-123'),
        unfurl_links: false
      });
    });
  });
});
EOF

# Create backlog API client module
echo "Creating Backlog API client..."
cat > src/shared/backlog-client.js << 'EOF'
/**
 * Backlog API Client
 */

const axios = require('axios');

class BacklogClient {
  constructor(space, apiKey) {
    this.space = space;
    this.apiKey = apiKey;
    this.baseUrl = `https://${space}/api/v2`;
  }

  /**
   * Create a new issue
   * @param {object} params - Issue parameters
   * @returns {Promise<object>} - Created issue
   */
  async createIssue(params) {
    const url = `${this.baseUrl}/issues`;
    
    const response = await axios.post(url, params, {
      params: { apiKey: this.apiKey },
      timeout: 10000,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      }
    });

    return response.data;
  }

  /**
   * Get issue types for a project
   * @param {string} projectId - Project ID
   * @returns {Promise<array>} - Issue types
   */
  async getIssueTypes(projectId) {
    const url = `${this.baseUrl}/projects/${projectId}/issueTypes`;
    
    const response = await axios.get(url, {
      params: { apiKey: this.apiKey }
    });

    return response.data;
  }

  /**
   * Get project details
   * @param {string} projectIdOrKey - Project ID or key
   * @returns {Promise<object>} - Project details
   */
  async getProject(projectIdOrKey) {
    const url = `${this.baseUrl}/projects/${projectIdOrKey}`;
    
    const response = await axios.get(url, {
      params: { apiKey: this.apiKey }
    });

    return response.data;
  }
}

module.exports = BacklogClient;
EOF

# Create Slack client module
echo "Creating Slack client module..."
cat > src/shared/slack-client.js << 'EOF'
/**
 * Slack Client wrapper
 */

const { WebClient } = require('@slack/web-api');

class SlackClient {
  constructor(token) {
    this.client = new WebClient(token);
  }

  /**
   * Post a message to a channel
   * @param {object} params - Message parameters
   * @returns {Promise<object>} - Posted message
   */
  async postMessage(params) {
    return this.client.chat.postMessage(params);
  }

  /**
   * Post a message to a thread
   * @param {string} channel - Channel ID
   * @param {string} threadTs - Thread timestamp
   * @param {string} text - Message text
   * @param {object} options - Additional options
   * @returns {Promise<object>} - Posted message
   */
  async postToThread(channel, threadTs, text, options = {}) {
    return this.postMessage({
      channel,
      thread_ts: threadTs,
      text,
      unfurl_links: false,
      ...options
    });
  }

  /**
   * Get user information
   * @param {string} userId - User ID
   * @returns {Promise<object>} - User information
   */
  async getUserInfo(userId) {
    return this.client.users.info({ user: userId });
  }

  /**
   * Get channel information
   * @param {string} channelId - Channel ID
   * @returns {Promise<object>} - Channel information
   */
  async getChannelInfo(channelId) {
    return this.client.conversations.info({ channel: channelId });
  }
}

module.exports = SlackClient;
EOF

echo "=== backlog_worker Lambda implementation complete! ==="
echo ""
echo "Created/Updated files:"
echo "  - src/backlog_worker/index.js         : Lambda function implementation"
echo "  - src/backlog_worker/package.json     : Function dependencies"
echo "  - tests/unit/backlog_worker.test.js   : Comprehensive unit tests"
echo "  - src/shared/backlog-client.js        : Backlog API client"
echo "  - src/shared/slack-client.js          : Slack client wrapper"
echo ""
echo "Next steps:"
echo "1. Run tests: npm test tests/unit/backlog_worker.test.js"
echo "2. Test locally: sam local invoke BacklogWorkerFunction"
echo "3. Deploy: sam deploy"