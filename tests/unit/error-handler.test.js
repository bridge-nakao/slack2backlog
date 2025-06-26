const { ErrorCodes, AppError, formatErrorResponse, asyncHandler } = require('../../src/shared/error-handler');

describe('Error Handler', () => {
  describe('AppError', () => {
    test('should create error with code and details', () => {
      const error = new AppError(
        ErrorCodes.INVALID_SIGNATURE,
        { statusCode: 401, userId: 'U123' }
      );

      expect(error.code).toBe('E1001');
      expect(error.message).toBe('Invalid Slack signature');
      expect(error.statusCode).toBe(401);
      expect(error.details.userId).toBe('U123');
      expect(error.timestamp).toBeDefined();
    });

    test('should include original error', () => {
      const originalError = new Error('Original error');
      const error = new AppError(
        ErrorCodes.INTERNAL_ERROR,
        {},
        originalError
      );

      expect(error.originalError).toBe(originalError);
    });

    test('should serialize to JSON correctly', () => {
      const error = new AppError(ErrorCodes.RATE_LIMIT_ERROR, { retryAfter: 60 });
      const json = error.toJSON();

      expect(json.code).toBe('E3003');
      expect(json.message).toBe('API rate limit exceeded');
      expect(json.details.retryAfter).toBe(60);
      expect(json.stack).toBeUndefined(); // In production mode
    });
  });

  describe('formatErrorResponse', () => {
    test('should format error response in Japanese', () => {
      const error = new AppError(ErrorCodes.BACKLOG_API_ERROR);
      const response = formatErrorResponse(error, 'ja');

      expect(response.error.code).toBe('E3002');
      expect(response.error.message).toBe('Backlog APIでエラーが発生しました');
    });

    test('should format error response in English', () => {
      const error = new AppError(ErrorCodes.BACKLOG_API_ERROR);
      const response = formatErrorResponse(error, 'en');

      expect(response.error.code).toBe('E3002');
      expect(response.error.message).toBe('Backlog API error occurred');
    });

    test('should use default message for unknown error code', () => {
      const error = new Error('Unknown error');
      const response = formatErrorResponse(error, 'ja');

      expect(response.error.code).toBe('E5001');
      expect(response.error.message).toBe('エラーが発生しました');
    });
  });

  describe('asyncHandler', () => {
    const mockContext = {
      functionName: 'test-function',
      awsRequestId: 'test-request-id',
      getRemainingTimeInMillis: () => 30000
    };

    beforeEach(() => {
      jest.spyOn(console, 'error').mockImplementation(() => {});
    });

    afterEach(() => {
      console.error.mockRestore();
    });

    test('should handle successful execution', async () => {
      const handler = asyncHandler(async (event, context) => {
        return {
          statusCode: 200,
          body: JSON.stringify({ success: true })
        };
      });

      const result = await handler({}, mockContext);
      expect(result.statusCode).toBe(200);
      expect(console.error).not.toHaveBeenCalled();
    });

    test('should handle AppError correctly', async () => {
      const handler = asyncHandler(async (event, context) => {
        throw new AppError(ErrorCodes.INVALID_REQUEST, { statusCode: 400 });
      });

      const result = await handler({}, mockContext);
      expect(result.statusCode).toBe(400);
      expect(result.headers['X-Request-ID']).toBe('test-request-id');
      
      const body = JSON.parse(result.body);
      expect(body.error.code).toBe('E2001');
      expect(console.error).toHaveBeenCalled();
    });

    test('should handle unexpected errors', async () => {
      const handler = asyncHandler(async (event, context) => {
        throw new Error('Unexpected error');
      });

      const result = await handler({}, mockContext);
      expect(result.statusCode).toBe(500);
      
      const body = JSON.parse(result.body);
      expect(body.error.code).toBe('E5001');
      expect(console.error).toHaveBeenCalled();
    });
  });
});