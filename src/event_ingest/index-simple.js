/**
 * Simplified Event Ingest Lambda Function for local testing
 */

const crypto = require('crypto');

// Logging utility
const log = (level, message, data = {}) => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data,
    functionName: 'EventIngestFunction'
  }));
};

// Simple signature verification
function verifySlackSignature(signature, timestamp, body, signingSecret) {
  const sigBasestring = `v0:${timestamp}:${body}`;
  const mySignature = `v0=` + 
    crypto.createHmac('sha256', signingSecret)
      .update(sigBasestring, 'utf8')
      .digest('hex');
  
  return mySignature === signature;
}

exports.handler = async (event) => {
  log('info', 'Lambda function invoked - Simple version');

  try {
    const body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
    
    // URL verification
    if (body.type === 'url_verification') {
      log('info', 'URL verification challenge received');
      return {
        statusCode: 200,
        body: body.challenge
      };
    }
    
    // Get signature info from headers
    const signature = event.headers?.['x-slack-signature'] || event.headers?.['X-Slack-Signature'];
    const timestamp = event.headers?.['x-slack-request-timestamp'] || event.headers?.['X-Slack-Request-Timestamp'];
    const signingSecret = process.env.SLACK_SIGNING_SECRET || 'test-signing-secret';
    
    // Verify signature
    if (signature && timestamp) {
      const isValid = verifySlackSignature(signature, timestamp, event.body, signingSecret);
      log('info', 'Signature verification', { isValid });
      
      if (!isValid) {
        return {
          statusCode: 401,
          body: JSON.stringify({ error: 'Invalid signature' })
        };
      }
    }
    
    // Event callback
    if (body.type === 'event_callback' && body.event) {
      log('info', 'Event callback received', {
        eventType: body.event.type,
        text: body.event.text,
        user: body.event.user,
        channel: body.event.channel
      });
      
      // Check for Backlog trigger
      if (body.event.text && body.event.text.includes('Backlog登録希望')) {
        log('info', 'Backlog registration request detected');
        
        // Skip SQS for local testing
        log('info', 'SQS sending skipped for local testing');
        
        return {
          statusCode: 200,
          body: JSON.stringify({ 
            ok: true,
            message: 'Backlog registration request received'
          })
        };
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