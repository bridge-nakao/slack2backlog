/**
 * Structured logging utility
 */

const LogLevels = {
  ERROR: 'error',
  WARN: 'warn',
  INFO: 'info',
  DEBUG: 'debug'
};

class Logger {
  constructor(context = {}) {
    this.context = {
      service: 'slack2backlog',
      environment: process.env.NODE_ENV || 'production',
      region: process.env.AWS_REGION || 'ap-northeast-1',
      ...context
    };
  }

  /**
   * Log a message with structured format
   * @param {string} level - Log level
   * @param {string} message - Log message
   * @param {object} data - Additional data to log
   */
  log(level, message, data = {}) {
    const logEntry = {
      timestamp: new Date().toISOString(),
      level,
      message,
      ...this.context,
      ...data
    };

    // Add Lambda context if available
    if (process.env.AWS_LAMBDA_FUNCTION_NAME) {
      logEntry.lambda = {
        functionName: process.env.AWS_LAMBDA_FUNCTION_NAME,
        functionVersion: process.env.AWS_LAMBDA_FUNCTION_VERSION,
        requestId: process.env.AWS_LAMBDA_REQUEST_ID,
        logGroup: process.env.AWS_LAMBDA_LOG_GROUP_NAME,
        logStream: process.env.AWS_LAMBDA_LOG_STREAM_NAME
      };
    }

    // Add X-Ray trace ID if available
    if (process.env._X_AMZN_TRACE_ID) {
      logEntry.traceId = process.env._X_AMZN_TRACE_ID;
    }

    // Output JSON for CloudWatch Logs
    console.log(JSON.stringify(logEntry));
  }

  error(message, error, data = {}) {
    const errorData = {
      ...data,
      error: {
        name: error.name,
        message: error.message,
        code: error.code,
        stack: process.env.NODE_ENV === 'development' ? error.stack : undefined
      }
    };

    this.log(LogLevels.ERROR, message, errorData);
  }

  warn(message, data = {}) {
    this.log(LogLevels.WARN, message, data);
  }

  info(message, data = {}) {
    this.log(LogLevels.INFO, message, data);
  }

  debug(message, data = {}) {
    if (process.env.NODE_ENV !== 'production' || process.env.DEBUG) {
      this.log(LogLevels.DEBUG, message, data);
    }
  }

  /**
   * Create a child logger with additional context
   * @param {object} additionalContext - Additional context to add
   * @returns {Logger} - New logger instance
   */
  child(additionalContext) {
    return new Logger({
      ...this.context,
      ...additionalContext
    });
  }

  /**
   * Log performance metrics
   * @param {string} operation - Operation name
   * @param {number} duration - Duration in milliseconds
   * @param {object} metadata - Additional metadata
   */
  metric(operation, duration, metadata = {}) {
    this.info(`Performance metric: ${operation}`, {
      metric: {
        operation,
        duration,
        unit: 'milliseconds',
        ...metadata
      }
    });
  }

  /**
   * Log API call
   * @param {string} api - API name
   * @param {string} operation - Operation name
   * @param {object} params - Request parameters
   * @param {object} response - Response data
   * @param {number} duration - Duration in milliseconds
   */
  apiCall(api, operation, params, response, duration) {
    const logData = {
      api: {
        name: api,
        operation,
        duration,
        success: !response.error
      }
    };

    // Add sanitized params (remove sensitive data)
    if (params) {
      logData.api.params = this.sanitizeData(params);
    }

    // Add response status/error
    if (response.error) {
      logData.api.error = response.error;
      this.error(`${api} API call failed: ${operation}`, response.error, logData);
    } else {
      if (response.statusCode) {
        logData.api.statusCode = response.statusCode;
      }
      this.info(`${api} API call completed: ${operation}`, logData);
    }
  }

  /**
   * Sanitize sensitive data from logs
   * @param {any} data - Data to sanitize
   * @returns {any} - Sanitized data
   */
  sanitizeData(data) {
    if (typeof data !== 'object' || data === null) {
      return data;
    }

    const sanitized = Array.isArray(data) ? [...data] : { ...data };
    const sensitiveKeys = ['password', 'token', 'secret', 'apiKey', 'api_key', 'authorization'];

    for (const key in sanitized) {
      if (sensitiveKeys.some(sensitive => key.toLowerCase().includes(sensitive))) {
        sanitized[key] = '[REDACTED]';
      } else if (typeof sanitized[key] === 'object') {
        sanitized[key] = this.sanitizeData(sanitized[key]);
      }
    }

    return sanitized;
  }
}

// Export singleton instance and class
const logger = new Logger();

module.exports = {
  Logger,
  logger,
  LogLevels
};