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

  // Compare signatures (handle different lengths)
  try {
    return crypto.timingSafeEqual(
      Buffer.from(mySignature, 'utf8'),
      Buffer.from(signature, 'utf8')
    );
  } catch (error) {
    // Signatures have different lengths, definitely not equal
    return false;
  }
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
