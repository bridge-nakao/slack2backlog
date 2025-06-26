/**
 * Error handling utilities
 */

// Error codes
const ErrorCodes = {
  // Authentication errors (1xxx)
  INVALID_SIGNATURE: { code: 'E1001', message: 'Invalid Slack signature' },
  MISSING_HEADERS: { code: 'E1002', message: 'Required headers missing' },
  TIMESTAMP_TOO_OLD: { code: 'E1003', message: 'Request timestamp is too old' },
  
  // Validation errors (2xxx)
  INVALID_REQUEST: { code: 'E2001', message: 'Invalid request format' },
  MISSING_EVENT_DATA: { code: 'E2002', message: 'Event data is missing' },
  INVALID_EVENT_TYPE: { code: 'E2003', message: 'Unsupported event type' },
  
  // External API errors (3xxx)
  SLACK_API_ERROR: { code: 'E3001', message: 'Slack API error' },
  BACKLOG_API_ERROR: { code: 'E3002', message: 'Backlog API error' },
  RATE_LIMIT_ERROR: { code: 'E3003', message: 'API rate limit exceeded' },
  
  // AWS service errors (4xxx)
  SQS_ERROR: { code: 'E4001', message: 'SQS operation failed' },
  DYNAMODB_ERROR: { code: 'E4002', message: 'DynamoDB operation failed' },
  SECRETS_MANAGER_ERROR: { code: 'E4003', message: 'Secrets Manager error' },
  
  // Internal errors (5xxx)
  INTERNAL_ERROR: { code: 'E5001', message: 'Internal server error' },
  CONFIGURATION_ERROR: { code: 'E5002', message: 'Configuration error' },
  TIMEOUT_ERROR: { code: 'E5003', message: 'Operation timeout' }
};

/**
 * Custom error class with error codes and context
 */
class AppError extends Error {
  constructor(errorDef, details = {}, originalError = null) {
    const message = details.userMessage || errorDef.message;
    super(message);
    
    this.name = 'AppError';
    this.code = errorDef.code;
    this.statusCode = details.statusCode || 500;
    this.details = details;
    this.originalError = originalError;
    this.timestamp = new Date().toISOString();
  }

  toJSON() {
    return {
      name: this.name,
      code: this.code,
      message: this.message,
      statusCode: this.statusCode,
      details: this.details,
      timestamp: this.timestamp,
      stack: process.env.NODE_ENV === 'development' ? this.stack : undefined
    };
  }
}

/**
 * Error response formatter
 */
function formatErrorResponse(error, locale = 'ja') {
  const messages = {
    ja: {
      E1001: '署名の検証に失敗しました',
      E1002: '必要なヘッダーが不足しています',
      E1003: 'リクエストのタイムスタンプが古すぎます',
      E2001: 'リクエストの形式が正しくありません',
      E2002: 'イベントデータが含まれていません',
      E2003: 'サポートされていないイベントタイプです',
      E3001: 'Slack APIでエラーが発生しました',
      E3002: 'Backlog APIでエラーが発生しました',
      E3003: 'APIの利用制限に達しました',
      E4001: 'メッセージキューの操作に失敗しました',
      E4002: 'データベースの操作に失敗しました',
      E4003: 'シークレットの取得に失敗しました',
      E5001: 'サーバー内部エラーが発生しました',
      E5002: '設定エラーが発生しました',
      E5003: '処理がタイムアウトしました',
      DEFAULT: 'エラーが発生しました'
    },
    en: {
      E1001: 'Invalid signature verification',
      E1002: 'Required headers are missing',
      E1003: 'Request timestamp is too old',
      E2001: 'Invalid request format',
      E2002: 'Event data is missing',
      E2003: 'Unsupported event type',
      E3001: 'Slack API error occurred',
      E3002: 'Backlog API error occurred',
      E3003: 'API rate limit exceeded',
      E4001: 'Message queue operation failed',
      E4002: 'Database operation failed',
      E4003: 'Failed to retrieve secrets',
      E5001: 'Internal server error occurred',
      E5002: 'Configuration error occurred',
      E5003: 'Operation timeout',
      DEFAULT: 'An error occurred'
    }
  };

  const localizedMessages = messages[locale] || messages.en;
  const userMessage = error.code ? 
    (localizedMessages[error.code] || localizedMessages.DEFAULT) :
    localizedMessages.DEFAULT;

  return {
    error: {
      code: error.code || 'E5001',
      message: userMessage,
      requestId: process.env.AWS_LAMBDA_REQUEST_ID
    }
  };
}

/**
 * Wrap async functions with error handling
 */
function asyncHandler(fn) {
  return async (event, context) => {
    try {
      return await fn(event, context);
    } catch (error) {
      // Log the error
      console.error(JSON.stringify({
        timestamp: new Date().toISOString(),
        level: 'error',
        message: 'Lambda function error',
        error: {
          name: error.name,
          message: error.message,
          code: error.code,
          stack: error.stack
        },
        context: {
          functionName: context.functionName,
          requestId: context.awsRequestId,
          remainingTime: context.getRemainingTimeInMillis()
        }
      }));

      // Return appropriate error response
      if (error instanceof AppError) {
        return {
          statusCode: error.statusCode,
          headers: {
            'Content-Type': 'application/json',
            'X-Request-ID': context.awsRequestId
          },
          body: JSON.stringify(formatErrorResponse(error))
        };
      }

      // Unexpected error
      const internalError = new AppError(
        ErrorCodes.INTERNAL_ERROR,
        { statusCode: 500 },
        error
      );

      return {
        statusCode: 500,
        headers: {
          'Content-Type': 'application/json',
          'X-Request-ID': context.awsRequestId
        },
        body: JSON.stringify(formatErrorResponse(internalError))
      };
    }
  };
}

module.exports = {
  ErrorCodes,
  AppError,
  formatErrorResponse,
  asyncHandler
};