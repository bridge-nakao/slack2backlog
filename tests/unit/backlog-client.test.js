const BacklogClient = require('../../src/shared/backlog-client');
const axios = require('axios');

jest.mock('axios');

describe('BacklogClient', () => {
  let client;

  beforeEach(() => {
    jest.clearAllMocks();
    client = new BacklogClient('test.backlog.com', 'test-api-key');
  });

  describe('constructor', () => {
    test('should initialize with correct properties', () => {
      expect(client.space).toBe('test.backlog.com');
      expect(client.apiKey).toBe('test-api-key');
      expect(client.baseUrl).toBe('https://test.backlog.com/api/v2');
    });
  });

  describe('createIssue', () => {
    test('should create issue successfully', async () => {
      const mockIssue = {
        id: 123,
        issueKey: 'TEST-123',
        summary: 'Test Issue'
      };

      axios.post.mockResolvedValueOnce({ data: mockIssue });

      const params = {
        projectId: '12345',
        summary: 'Test Issue',
        issueTypeId: '67890',
        priorityId: 3
      };

      const result = await client.createIssue(params);

      expect(result).toEqual(mockIssue);
      expect(axios.post).toHaveBeenCalledWith(
        'https://test.backlog.com/api/v2/issues',
        params,
        {
          params: { apiKey: 'test-api-key' },
          timeout: 10000,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded'
          }
        }
      );
    });

    test('should handle API errors', async () => {
      const error = new Error('API Error');
      error.response = { status: 400, data: { message: 'Bad Request' } };
      
      axios.post.mockRejectedValueOnce(error);

      const params = {
        projectId: '12345',
        summary: 'Test Issue'
      };

      await expect(client.createIssue(params)).rejects.toThrow('API Error');
    });
  });

  describe('getIssueTypes', () => {
    test('should get issue types successfully', async () => {
      const mockIssueTypes = [
        { id: 1, name: 'Bug' },
        { id: 2, name: 'Task' }
      ];

      axios.get.mockResolvedValueOnce({ data: mockIssueTypes });

      const result = await client.getIssueTypes('12345');

      expect(result).toEqual(mockIssueTypes);
      expect(axios.get).toHaveBeenCalledWith(
        'https://test.backlog.com/api/v2/projects/12345/issueTypes',
        {
          params: { apiKey: 'test-api-key' }
        }
      );
    });
  });

  describe('getProject', () => {
    test('should get project details successfully', async () => {
      const mockProject = {
        id: 12345,
        projectKey: 'TEST',
        name: 'Test Project'
      };

      axios.get.mockResolvedValueOnce({ data: mockProject });

      const result = await client.getProject('TEST');

      expect(result).toEqual(mockProject);
      expect(axios.get).toHaveBeenCalledWith(
        'https://test.backlog.com/api/v2/projects/TEST',
        {
          params: { apiKey: 'test-api-key' }
        }
      );
    });
  });
});