/**
 * Backlog API Client
 */

const axios = require('axios');

class BacklogClient {
  constructor(space, apiKey) {
    this.space = space;
    this.apiKey = apiKey;
    this.baseUrl = `https://${space}/api/v2`;
  }

  /**
   * Create a new issue
   * @param {object} params - Issue parameters
   * @returns {Promise<object>} - Created issue
   */
  async createIssue(params) {
    const url = `${this.baseUrl}/issues`;
    
    const response = await axios.post(url, params, {
      params: { apiKey: this.apiKey },
      timeout: 10000,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      }
    });

    return response.data;
  }

  /**
   * Get issue types for a project
   * @param {string} projectId - Project ID
   * @returns {Promise<array>} - Issue types
   */
  async getIssueTypes(projectId) {
    const url = `${this.baseUrl}/projects/${projectId}/issueTypes`;
    
    const response = await axios.get(url, {
      params: { apiKey: this.apiKey }
    });

    return response.data;
  }

  /**
   * Get project details
   * @param {string} projectIdOrKey - Project ID or key
   * @returns {Promise<object>} - Project details
   */
  async getProject(projectIdOrKey) {
    const url = `${this.baseUrl}/projects/${projectIdOrKey}`;
    
    const response = await axios.get(url, {
      params: { apiKey: this.apiKey }
    });

    return response.data;
  }
}

module.exports = BacklogClient;
