const { Logger, logger, LogLevels } = require('../../src/shared/logger');

describe('Logger', () => {
  let consoleLogSpy;
  let testLogger;

  beforeEach(() => {
    consoleLogSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    testLogger = new Logger({ component: 'test' });
    
    // Clear environment variables
    delete process.env.AWS_LAMBDA_FUNCTION_NAME;
    delete process.env._X_AMZN_TRACE_ID;
  });

  afterEach(() => {
    consoleLogSpy.mockRestore();
  });

  describe('log method', () => {
    test('should log structured JSON', () => {
      testLogger.log('info', 'Test message', { userId: 'U123' });

      expect(consoleLogSpy).toHaveBeenCalledTimes(1);
      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      
      expect(logOutput.level).toBe('info');
      expect(logOutput.message).toBe('Test message');
      expect(logOutput.userId).toBe('U123');
      expect(logOutput.component).toBe('test');
      expect(logOutput.timestamp).toBeDefined();
    });

    test('should include Lambda context when available', () => {
      process.env.AWS_LAMBDA_FUNCTION_NAME = 'test-function';
      process.env.AWS_LAMBDA_REQUEST_ID = 'test-request-id';

      testLogger.info('Lambda test');

      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      expect(logOutput.lambda.functionName).toBe('test-function');
      expect(logOutput.lambda.requestId).toBe('test-request-id');
    });

    test('should include X-Ray trace ID when available', () => {
      process.env._X_AMZN_TRACE_ID = 'trace-123';

      testLogger.info('Trace test');

      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      expect(logOutput.traceId).toBe('trace-123');
    });
  });

  describe('log level methods', () => {
    test('should log error with error details', () => {
      const error = new Error('Test error');
      error.code = 'TEST_ERROR';

      testLogger.error('Error occurred', error, { operation: 'test' });

      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      expect(logOutput.level).toBe('error');
      expect(logOutput.error.message).toBe('Test error');
      expect(logOutput.error.code).toBe('TEST_ERROR');
      expect(logOutput.operation).toBe('test');
    });

    test('should log warning', () => {
      testLogger.warn('Warning message', { threshold: 80 });

      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      expect(logOutput.level).toBe('warn');
      expect(logOutput.message).toBe('Warning message');
      expect(logOutput.threshold).toBe(80);
    });

    test('should log info', () => {
      testLogger.info('Info message');

      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      expect(logOutput.level).toBe('info');
      expect(logOutput.message).toBe('Info message');
    });

    test('should not log debug in production', () => {
      process.env.NODE_ENV = 'production';
      
      testLogger.debug('Debug message');

      expect(consoleLogSpy).not.toHaveBeenCalled();
    });

    test('should log debug in development', () => {
      process.env.NODE_ENV = 'development';
      
      testLogger.debug('Debug message');

      expect(consoleLogSpy).toHaveBeenCalled();
      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      expect(logOutput.level).toBe('debug');
    });
  });

  describe('child logger', () => {
    test('should create child logger with additional context', () => {
      const childLogger = testLogger.child({ requestId: 'req-123' });

      childLogger.info('Child log');

      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      expect(logOutput.component).toBe('test');
      expect(logOutput.requestId).toBe('req-123');
    });
  });

  describe('metric logging', () => {
    test('should log performance metrics', () => {
      testLogger.metric('api-call', 250, { endpoint: '/users' });

      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      expect(logOutput.message).toBe('Performance metric: api-call');
      expect(logOutput.metric.operation).toBe('api-call');
      expect(logOutput.metric.duration).toBe(250);
      expect(logOutput.metric.unit).toBe('milliseconds');
      expect(logOutput.metric.endpoint).toBe('/users');
    });
  });

  describe('API call logging', () => {
    test('should log successful API call', () => {
      testLogger.apiCall(
        'Slack',
        'postMessage',
        { channel: 'C123', text: 'Hello' },
        { statusCode: 200, ok: true },
        150
      );

      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      expect(logOutput.message).toBe('Slack API call completed: postMessage');
      expect(logOutput.api.name).toBe('Slack');
      expect(logOutput.api.operation).toBe('postMessage');
      expect(logOutput.api.duration).toBe(150);
      expect(logOutput.api.success).toBe(true);
      expect(logOutput.api.statusCode).toBe(200);
    });

    test('should log failed API call', () => {
      const error = new Error('API Error');
      testLogger.apiCall(
        'Backlog',
        'createIssue',
        { projectId: '123' },
        { error },
        500
      );

      expect(consoleLogSpy).toHaveBeenCalled();
      const logOutput = JSON.parse(consoleLogSpy.mock.calls[0][0]);
      expect(logOutput.level).toBe('error');
      expect(logOutput.message).toBe('Backlog API call failed: createIssue');
      expect(logOutput.api.success).toBe(false);
    });
  });

  describe('data sanitization', () => {
    test('should sanitize sensitive data', () => {
      const data = {
        username: 'user123',
        password: 'secret123',
        api_key: 'key123',
        nested: {
          token: 'token123',
          safe: 'visible'
        }
      };

      const sanitized = testLogger.sanitizeData(data);

      expect(sanitized.username).toBe('user123');
      expect(sanitized.password).toBe('[REDACTED]');
      expect(sanitized.api_key).toBe('[REDACTED]');
      expect(sanitized.nested.token).toBe('[REDACTED]');
      expect(sanitized.nested.safe).toBe('visible');
    });

    test('should handle non-object data', () => {
      expect(testLogger.sanitizeData('string')).toBe('string');
      expect(testLogger.sanitizeData(123)).toBe(123);
      expect(testLogger.sanitizeData(null)).toBe(null);
    });
  });
});