const axios = require('axios');
const AWS = require('aws-sdk');
const crypto = require('crypto');

// Configure AWS SDK for LocalStack
AWS.config.update({
  region: 'ap-northeast-1',
  endpoint: 'http://localhost:4566',
  accessKeyId: 'test',
  secretAccessKey: 'test'
});

const sqs = new AWS.SQS();
const secretsManager = new AWS.SecretsManager();
const dynamodb = new AWS.DynamoDB.DocumentClient({
  endpoint: 'http://localhost:8000'
});

// Test configuration
const API_GATEWAY_URL = 'http://localhost:3000';
const SLACK_SIGNING_SECRET = 'test-signing-secret';

describe('Integration Tests', () => {
  describe('API Gateway → Lambda Integration', () => {
    test('should handle URL verification challenge', async () => {
      const challenge = 'test-challenge-token';
      const response = await axios.post(`${API_GATEWAY_URL}/slack/events`, {
        type: 'url_verification',
        challenge: challenge
      });

      expect(response.status).toBe(200);
      expect(response.data.challenge).toBe(challenge);
    });

    test('should reject invalid signatures', async () => {
      const timestamp = Math.floor(Date.now() / 1000);
      const body = JSON.stringify({
        event: {
          type: 'message',
          text: 'Test message'
        }
      });

      try {
        await axios.post(`${API_GATEWAY_URL}/slack/events`, body, {
          headers: {
            'x-slack-request-timestamp': timestamp,
            'x-slack-signature': 'v0=invalid-signature',
            'Content-Type': 'application/json'
          }
        });
        fail('Should have thrown an error');
      } catch (error) {
        expect(error.response.status).toBe(401);
      }
    });

    test('should accept valid Slack events', async () => {
      const timestamp = Math.floor(Date.now() / 1000);
      const eventBody = {
        event: {
          type: 'message',
          text: 'Backlog登録希望 テストタスク',
          user: 'U123',
          channel: 'C123',
          ts: '1234567890.123456'
        }
      };
      const body = JSON.stringify(eventBody);

      // Generate valid signature
      const sigBasestring = `v0:${timestamp}:${body}`;
      const signature = 'v0=' + crypto
        .createHmac('sha256', SLACK_SIGNING_SECRET)
        .update(sigBasestring, 'utf8')
        .digest('hex');

      const response = await axios.post(`${API_GATEWAY_URL}/slack/events`, body, {
        headers: {
          'x-slack-request-timestamp': timestamp,
          'x-slack-signature': signature,
          'Content-Type': 'application/json'
        }
      });

      expect(response.status).toBe(200);
    });
  });

  describe('SQS Workflow', () => {
    let queueUrl;

    beforeAll(async () => {
      // Get queue URL
      const result = await sqs.getQueueUrl({ QueueName: 'slack2backlog-queue' }).promise();
      queueUrl = result.QueueUrl;
    });

    test('should send message to SQS', async () => {
      const message = {
        data: {
          slackEvent: {
            type: 'message',
            text: 'Backlog登録希望 SQSテスト',
            user: 'U123',
            channel: 'C123',
            ts: '1234567890.123456'
          },
          metadata: {
            eventId: `test-${Date.now()}`
          }
        }
      };

      const params = {
        QueueUrl: queueUrl,
        MessageBody: JSON.stringify(message)
      };

      const result = await sqs.sendMessage(params).promise();
      expect(result.MessageId).toBeDefined();
    });

    test('should receive message from SQS', async () => {
      const params = {
        QueueUrl: queueUrl,
        MaxNumberOfMessages: 1,
        WaitTimeSeconds: 5
      };

      const result = await sqs.receiveMessage(params).promise();
      
      if (result.Messages && result.Messages.length > 0) {
        const message = JSON.parse(result.Messages[0].Body);
        expect(message.data.slackEvent).toBeDefined();
        
        // Delete the message
        await sqs.deleteMessage({
          QueueUrl: queueUrl,
          ReceiptHandle: result.Messages[0].ReceiptHandle
        }).promise();
      }
    });
  });

  describe('DynamoDB Idempotency', () => {
    const tableName = 'slack2backlog-idempotency';

    beforeAll(async () => {
      // Create idempotency table if not exists
      try {
        await dynamodb.createTable({
          TableName: tableName,
          KeySchema: [
            { AttributeName: 'event_id', KeyType: 'HASH' }
          ],
          AttributeDefinitions: [
            { AttributeName: 'event_id', AttributeType: 'S' }
          ],
          BillingMode: 'PAY_PER_REQUEST'
        }).promise();
      } catch (error) {
        // Table might already exist
      }
    });

    test('should store idempotency key', async () => {
      const eventId = `test-event-${Date.now()}`;
      
      const params = {
        TableName: tableName,
        Item: {
          event_id: eventId,
          processed_at: new Date().toISOString(),
          ttl: Math.floor(Date.now() / 1000) + 86400
        }
      };

      await dynamodb.put(params).promise();

      // Verify the item was stored
      const getParams = {
        TableName: tableName,
        Key: { event_id: eventId }
      };

      const result = await dynamodb.get(getParams).promise();
      expect(result.Item).toBeDefined();
      expect(result.Item.event_id).toBe(eventId);
    });

    test('should detect duplicate events', async () => {
      const eventId = `duplicate-test-${Date.now()}`;
      
      // Store the event
      await dynamodb.put({
        TableName: tableName,
        Item: {
          event_id: eventId,
          processed_at: new Date().toISOString()
        }
      }).promise();

      // Check if it exists
      const result = await dynamodb.get({
        TableName: tableName,
        Key: { event_id: eventId }
      }).promise();

      expect(result.Item).toBeDefined();
    });
  });

  describe('Secrets Manager', () => {
    test('should retrieve Slack secrets', async () => {
      const result = await secretsManager.getSecretValue({
        SecretId: 'slack2backlog-slack-secrets'
      }).promise();

      const secrets = JSON.parse(result.SecretString);
      expect(secrets.bot_token).toBe('xoxb-test-token');
      expect(secrets.signing_secret).toBe('test-signing-secret');
    });

    test('should retrieve Backlog secrets', async () => {
      const result = await secretsManager.getSecretValue({
        SecretId: 'slack2backlog-backlog-secrets'
      }).promise();

      const secrets = JSON.parse(result.SecretString);
      expect(secrets.api_key).toBe('test-api-key');
      expect(secrets.space_id).toBe('test-space');
    });
  });
});