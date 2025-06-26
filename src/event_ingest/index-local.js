/**
 * Local version of Event Ingest Lambda Function for testing
 * This version skips signature verification for local development
 */

const AWS = require('aws-sdk');

// AWS SDK clients
const sqs = new AWS.SQS({
  region: process.env.AWS_REGION || 'ap-northeast-1',
  endpoint: process.env.LOCAL_SQS_ENDPOINT || 'http://localhost:4566'
});

// Logging utility
const log = (level, message, data = {}) => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data,
    functionName: process.env.AWS_LAMBDA_FUNCTION_NAME || 'EventIngestFunction'
  }));
};

/**
 * Send message to SQS queue
 * @param {object} message - Message to send
 * @returns {Promise<object>} - SQS response
 */
async function sendToQueue(message) {
  const params = {
    QueueUrl: process.env.QUEUE_URL,
    MessageBody: JSON.stringify(message),
    MessageAttributes: {
      eventType: {
        DataType: 'String',
        StringValue: message.event?.type || 'unknown'
      },
      eventId: {
        DataType: 'String',
        StringValue: message.event_id || 'unknown'
      }
    }
  };

  return sqs.sendMessage(params).promise();
}

/**
 * Lambda handler
 */
exports.handler = async (event) => {
  log('info', 'Lambda function invoked - LOCAL VERSION (signature verification skipped)', {
    functionArn: event.functionArn,
    remainingTime: event.getRemainingTimeInMillis?.() || 'N/A'
  });

  try {
    // Parse the body
    const body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
    
    log('info', 'Event received', { 
      eventType: body.type,
      eventId: body.event_id,
      hasEvent: !!body.event
    });

    // Handle URL verification challenge
    if (body.type === 'url_verification') {
      log('info', 'URL verification challenge received');
      return {
        statusCode: 200,
        body: body.challenge
      };
    }

    // Handle event callback
    if (body.type === 'event_callback' && body.event) {
      // Check if message contains the trigger keyword
      if (body.event.type === 'message' && 
          body.event.text && 
          body.event.text.includes('Backlog登録希望')) {
        
        log('info', 'Backlog registration request detected', {
          user: body.event.user,
          channel: body.event.channel,
          text: body.event.text
        });

        // Send to SQS for processing
        const sqsResponse = await sendToQueue(body);
        log('info', 'Message sent to SQS', { 
          messageId: sqsResponse.MessageId,
          queueUrl: process.env.QUEUE_URL
        });
      }
    }

    return {
      statusCode: 200,
      body: JSON.stringify({ ok: true })
    };

  } catch (error) {
    log('error', 'Error processing event', {
      error: error.message,
      stack: error.stack
    });

    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Internal server error' })
    };
  }
};