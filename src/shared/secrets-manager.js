/**
 * Secrets Manager helper functions
 */

const AWS = require('aws-sdk');

// Configure AWS SDK
const secretsManager = new AWS.SecretsManager({
  region: process.env.AWS_REGION || 'ap-northeast-1',
  endpoint: process.env.LOCAL_SECRETS_ENDPOINT // For local testing with LocalStack
});

// Cache for secrets to avoid repeated API calls
const secretsCache = new Map();
const CACHE_TTL = 300000; // 5 minutes

/**
 * Get secret value from Secrets Manager
 * @param {string} secretId - The secret ID or ARN
 * @returns {Promise<object>} - The secret value as an object
 */
async function getSecret(secretId) {
  // Check cache first
  const cached = secretsCache.get(secretId);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    console.log(`Returning cached secret for ${secretId}`);
    return cached.value;
  }

  try {
    console.log(`Fetching secret: ${secretId}`);
    const data = await secretsManager.getSecretValue({ SecretId: secretId }).promise();
    
    let secretValue;
    if ('SecretString' in data) {
      secretValue = JSON.parse(data.SecretString);
    } else {
      // Binary secret
      const buff = Buffer.from(data.SecretBinary, 'base64');
      secretValue = JSON.parse(buff.toString('ascii'));
    }

    // Cache the secret
    secretsCache.set(secretId, {
      value: secretValue,
      timestamp: Date.now()
    });

    return secretValue;
  } catch (error) {
    console.error(`Error retrieving secret ${secretId}:`, error);
    throw error;
  }
}

/**
 * Get specific secret value
 * @param {string} secretId - The secret ID or ARN
 * @param {string} key - The key within the secret
 * @returns {Promise<string>} - The specific secret value
 */
async function getSecretValue(secretId, key) {
  const secret = await getSecret(secretId);
  if (!secret[key]) {
    throw new Error(`Key ${key} not found in secret ${secretId}`);
  }
  return secret[key];
}

/**
 * Clear secrets cache
 */
function clearCache() {
  secretsCache.clear();
}

/**
 * Initialize secrets from environment variables (for local development)
 * @returns {object} - Secrets object
 */
function getSecretsFromEnv() {
  return {
    slack: {
      bot_token: process.env.SLACK_BOT_TOKEN,
      signing_secret: process.env.SLACK_SIGNING_SECRET
    },
    backlog: {
      api_key: process.env.BACKLOG_API_KEY,
      space_id: process.env.BACKLOG_SPACE_ID
    }
  };
}

module.exports = {
  getSecret,
  getSecretValue,
  clearCache,
  getSecretsFromEnv
};
