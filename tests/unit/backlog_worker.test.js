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
    get: jest.fn(),
    put: jest.fn()
  };
  const SecretsManagerMock = {
    getSecretValue: jest.fn()
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
jest.mock('@slack/web-api');

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
    
    // Create mock Slack client
    mockSlackClient = {
      chat: {
        postMessage: jest.fn()
      }
    };
    
    // Mock WebClient constructor
    WebClient.mockImplementation(() => mockSlackClient);
    
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
          Body: JSON.stringify({
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

      // Mock secrets - getSecretValue returns an object with promise method
      mockSecretsManager.getSecretValue
        .mockReturnValueOnce({
          promise: jest.fn().mockResolvedValueOnce({
            SecretString: JSON.stringify({
              bot_token: 'xoxb-test-token'
            })
          })
        })
        .mockReturnValueOnce({
          promise: jest.fn().mockResolvedValueOnce({
            SecretString: JSON.stringify({
              api_key: 'test-api-key',
              space_id: 'test-space'
            })
          })
        });

      // Mock DynamoDB - get and put return objects with promise method
      mockDynamoDB.get.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({})  // No Item means not processed
      });
      mockDynamoDB.put.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({})
      });

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
          Body: JSON.stringify({
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
      mockSecretsManager.getSecretValue
        .mockReturnValueOnce({
          promise: jest.fn().mockResolvedValueOnce({
            SecretString: JSON.stringify({ bot_token: 'xoxb-test' })
          })
        })
        .mockReturnValueOnce({
          promise: jest.fn().mockResolvedValueOnce({
            SecretString: JSON.stringify({ api_key: 'test-key' })
          })
        });

      // Mock DynamoDB
      mockDynamoDB.get.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({})  // No Item
      });

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
      mockDynamoDB.get.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({
          Item: { event_id: 'Ev123', processed_at: '2025-06-26T00:00:00Z' }
        })
      });

      const result = await isAlreadyProcessed('Ev123');

      expect(result).toBe(true);
      expect(mockDynamoDB.get).toHaveBeenCalledWith({
        TableName: 'test-idempotency-table',
        Key: { event_id: 'Ev123' }
      });
    });

    test('should return false if not processed', async () => {
      mockDynamoDB.get.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({})  // No Item property
      });

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
