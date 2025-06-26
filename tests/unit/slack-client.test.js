const SlackClient = require('../../src/shared/slack-client');
const { WebClient } = require('@slack/web-api');

jest.mock('@slack/web-api');

describe('SlackClient', () => {
  let client;
  let mockWebClient;

  beforeEach(() => {
    jest.clearAllMocks();
    
    mockWebClient = {
      chat: {
        postMessage: jest.fn()
      },
      users: {
        info: jest.fn()
      },
      conversations: {
        info: jest.fn()
      }
    };
    
    WebClient.mockImplementation(() => mockWebClient);
    client = new SlackClient('xoxb-test-token');
  });

  describe('constructor', () => {
    test('should initialize WebClient with token', () => {
      expect(WebClient).toHaveBeenCalledWith('xoxb-test-token');
    });
  });

  describe('postMessage', () => {
    test('should post message successfully', async () => {
      const mockResponse = { ok: true, ts: '1234567890.123456' };
      mockWebClient.chat.postMessage.mockResolvedValueOnce(mockResponse);

      const params = {
        channel: 'C123',
        text: 'Hello, world!'
      };

      const result = await client.postMessage(params);

      expect(result).toEqual(mockResponse);
      expect(mockWebClient.chat.postMessage).toHaveBeenCalledWith(params);
    });

    test('should handle errors', async () => {
      const error = new Error('API Error');
      mockWebClient.chat.postMessage.mockRejectedValueOnce(error);

      await expect(client.postMessage({ channel: 'C123', text: 'Test' }))
        .rejects.toThrow('API Error');
    });
  });

  describe('postToThread', () => {
    test('should post to thread successfully', async () => {
      const mockResponse = { ok: true, ts: '1234567890.123457' };
      mockWebClient.chat.postMessage.mockResolvedValueOnce(mockResponse);

      const result = await client.postToThread('C123', '1234567890.123456', 'Thread reply');

      expect(result).toEqual(mockResponse);
      expect(mockWebClient.chat.postMessage).toHaveBeenCalledWith({
        channel: 'C123',
        thread_ts: '1234567890.123456',
        text: 'Thread reply',
        unfurl_links: false
      });
    });

    test('should pass additional options', async () => {
      const mockResponse = { ok: true, ts: '1234567890.123457' };
      mockWebClient.chat.postMessage.mockResolvedValueOnce(mockResponse);

      const options = { mrkdwn: true };
      await client.postToThread('C123', '1234567890.123456', 'Thread reply', options);

      expect(mockWebClient.chat.postMessage).toHaveBeenCalledWith({
        channel: 'C123',
        thread_ts: '1234567890.123456',
        text: 'Thread reply',
        unfurl_links: false,
        mrkdwn: true
      });
    });
  });

  describe('getUserInfo', () => {
    test('should get user info successfully', async () => {
      const mockUser = {
        user: {
          id: 'U123',
          name: 'testuser',
          real_name: 'Test User'
        }
      };
      mockWebClient.users.info.mockResolvedValueOnce(mockUser);

      const result = await client.getUserInfo('U123');

      expect(result).toEqual(mockUser);
      expect(mockWebClient.users.info).toHaveBeenCalledWith({ user: 'U123' });
    });
  });

  describe('getChannelInfo', () => {
    test('should get channel info successfully', async () => {
      const mockChannel = {
        channel: {
          id: 'C123',
          name: 'general',
          is_channel: true
        }
      };
      mockWebClient.conversations.info.mockResolvedValueOnce(mockChannel);

      const result = await client.getChannelInfo('C123');

      expect(result).toEqual(mockChannel);
      expect(mockWebClient.conversations.info).toHaveBeenCalledWith({ channel: 'C123' });
    });
  });
});