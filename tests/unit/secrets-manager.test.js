const { getSecret, getSecretValue, clearCache, getSecretsFromEnv } = require('../../src/shared/secrets-manager');
const AWS = require('aws-sdk');

jest.mock('aws-sdk', () => {
  const SecretsManagerMock = {
    getSecretValue: jest.fn()
  };
  return {
    SecretsManager: jest.fn(() => SecretsManagerMock)
  };
});

// Mock console methods
const originalConsoleLog = console.log;
const originalConsoleError = console.error;

beforeAll(() => {
  console.log = jest.fn();
  console.error = jest.fn();
});

afterAll(() => {
  console.log = originalConsoleLog;
  console.error = originalConsoleError;
});

describe('Secrets Manager', () => {
  let mockSecretsManager;

  beforeEach(() => {
    jest.clearAllMocks();
    clearCache();
    mockSecretsManager = new AWS.SecretsManager();
  });

  describe('getSecret', () => {
    test('should get secret successfully with SecretString', async () => {
      const mockSecret = {
        bot_token: 'xoxb-test-token',
        signing_secret: 'test-signing-secret'
      };

      mockSecretsManager.getSecretValue.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({
          SecretString: JSON.stringify(mockSecret)
        })
      });

      const result = await getSecret('test-secret');

      expect(result).toEqual(mockSecret);
      expect(mockSecretsManager.getSecretValue).toHaveBeenCalledWith({
        SecretId: 'test-secret'
      });
    });

    test('should get secret successfully with SecretBinary', async () => {
      const mockSecret = {
        api_key: 'test-api-key'
      };
      const secretBinary = Buffer.from(JSON.stringify(mockSecret)).toString('base64');

      mockSecretsManager.getSecretValue.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({
          SecretBinary: secretBinary
        })
      });

      const result = await getSecret('test-binary-secret');

      expect(result).toEqual(mockSecret);
    });

    test('should cache secrets for 5 minutes', async () => {
      const mockSecret = {
        bot_token: 'xoxb-test-token'
      };

      mockSecretsManager.getSecretValue.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({
          SecretString: JSON.stringify(mockSecret)
        })
      });

      // First call
      const result1 = await getSecret('test-secret');
      expect(result1).toEqual(mockSecret);
      expect(mockSecretsManager.getSecretValue).toHaveBeenCalledTimes(1);

      // Second call (should use cache)
      const result2 = await getSecret('test-secret');
      expect(result2).toEqual(mockSecret);
      expect(mockSecretsManager.getSecretValue).toHaveBeenCalledTimes(1);
      expect(console.log).toHaveBeenCalledWith('Returning cached secret for test-secret');
    });

    test('should handle AWS errors', async () => {
      const error = new Error('AWS Error');
      mockSecretsManager.getSecretValue.mockReturnValueOnce({
        promise: jest.fn().mockRejectedValueOnce(error)
      });

      await expect(getSecret('test-secret')).rejects.toThrow('AWS Error');
      expect(console.error).toHaveBeenCalledWith(
        'Error retrieving secret test-secret:',
        error
      );
    });

    test('should handle JSON parse errors', async () => {
      mockSecretsManager.getSecretValue.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({
          SecretString: 'invalid-json'
        })
      });

      await expect(getSecret('test-secret')).rejects.toThrow();
    });
  });

  describe('getSecretValue', () => {
    test('should get specific secret value', async () => {
      const mockSecret = {
        bot_token: 'xoxb-test-token',
        signing_secret: 'test-signing-secret'
      };

      mockSecretsManager.getSecretValue.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({
          SecretString: JSON.stringify(mockSecret)
        })
      });

      const result = await getSecretValue('test-secret', 'bot_token');

      expect(result).toBe('xoxb-test-token');
    });

    test('should throw error if key not found', async () => {
      const mockSecret = {
        bot_token: 'xoxb-test-token'
      };

      mockSecretsManager.getSecretValue.mockReturnValueOnce({
        promise: jest.fn().mockResolvedValueOnce({
          SecretString: JSON.stringify(mockSecret)
        })
      });

      await expect(getSecretValue('test-secret', 'missing_key'))
        .rejects.toThrow('Key missing_key not found in secret test-secret');
    });
  });

  describe('clearCache', () => {
    test('should clear the cache', async () => {
      const mockSecret = {
        bot_token: 'xoxb-test-token'
      };

      mockSecretsManager.getSecretValue
        .mockReturnValueOnce({
          promise: jest.fn().mockResolvedValueOnce({
            SecretString: JSON.stringify(mockSecret)
          })
        })
        .mockReturnValueOnce({
          promise: jest.fn().mockResolvedValueOnce({
            SecretString: JSON.stringify(mockSecret)
          })
        });

      // First call
      await getSecret('test-secret');
      expect(mockSecretsManager.getSecretValue).toHaveBeenCalledTimes(1);

      // Clear cache
      clearCache();

      // Second call (should fetch again)
      await getSecret('test-secret');
      expect(mockSecretsManager.getSecretValue).toHaveBeenCalledTimes(2);
    });
  });

  describe('getSecretsFromEnv', () => {
    test('should get secrets from environment variables', () => {
      process.env.SLACK_BOT_TOKEN = 'env-bot-token';
      process.env.SLACK_SIGNING_SECRET = 'env-signing-secret';
      process.env.BACKLOG_API_KEY = 'env-api-key';
      process.env.BACKLOG_SPACE_ID = 'env-space-id';

      const result = getSecretsFromEnv();

      expect(result).toEqual({
        slack: {
          bot_token: 'env-bot-token',
          signing_secret: 'env-signing-secret'
        },
        backlog: {
          api_key: 'env-api-key',
          space_id: 'env-space-id'
        }
      });

      // Clean up
      delete process.env.SLACK_BOT_TOKEN;
      delete process.env.SLACK_SIGNING_SECRET;
      delete process.env.BACKLOG_API_KEY;
      delete process.env.BACKLOG_SPACE_ID;
    });
  });
});