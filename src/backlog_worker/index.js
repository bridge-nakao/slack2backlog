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
