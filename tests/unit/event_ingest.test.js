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
