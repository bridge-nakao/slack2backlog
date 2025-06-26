/**
 * Slack Client wrapper
 */

const { WebClient } = require('@slack/web-api');

class SlackClient {
  constructor(token) {
    this.client = new WebClient(token);
  }

  /**
   * Post a message to a channel
   * @param {object} params - Message parameters
   * @returns {Promise<object>} - Posted message
   */
  async postMessage(params) {
    return this.client.chat.postMessage(params);
  }

  /**
   * Post a message to a thread
   * @param {string} channel - Channel ID
   * @param {string} threadTs - Thread timestamp
   * @param {string} text - Message text
   * @param {object} options - Additional options
   * @returns {Promise<object>} - Posted message
   */
  async postToThread(channel, threadTs, text, options = {}) {
    return this.postMessage({
      channel,
      thread_ts: threadTs,
      text,
      unfurl_links: false,
      ...options
    });
  }

  /**
   * Get user information
   * @param {string} userId - User ID
   * @returns {Promise<object>} - User information
   */
  async getUserInfo(userId) {
    return this.client.users.info({ user: userId });
  }

  /**
   * Get channel information
   * @param {string} channelId - Channel ID
   * @returns {Promise<object>} - Channel information
   */
  async getChannelInfo(channelId) {
    return this.client.conversations.info({ channel: channelId });
  }
}

module.exports = SlackClient;
