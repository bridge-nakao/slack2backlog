#!/usr/bin/env node

/**
 * Local test script for Slack events
 * This bypasses signature verification for local testing
 */

const axios = require('axios');

// Configuration
const API_URL = process.env.API_URL || 'http://localhost:3000/slack/events';

// Create test event
const event = {
  token: 'test-token',
  team_id: 'T0001',
  api_app_id: 'A0001',
  event: {
    type: 'message',
    channel: 'C0001',
    user: 'U0001',
    text: 'Backlog登録希望 テストタスクの作成',
    ts: '1234567890.123456',
    event_ts: '1234567890.123456',
    channel_type: 'channel'
  },
  type: 'event_callback',
  event_id: `Ev${Date.now()}`,
  event_time: Math.floor(Date.now() / 1000)
};

// Send request without signature (for local testing only)
console.log('Sending test event to:', API_URL);
console.log('Event:', JSON.stringify(event, null, 2));

axios.post(API_URL, event, {
  headers: {
    'Content-Type': 'application/json',
    'X-Slack-Request-Timestamp': '1234567890',
    'X-Slack-Signature': 'v0=test-signature-for-local-development',
    'X-Local-Test': 'true'  // Special header for local testing
  }
})
.then(response => {
  console.log('\n✅ Success!');
  console.log('Status:', response.status);
  console.log('Response:', response.data);
})
.catch(error => {
  console.error('\n❌ Error!');
  if (error.response) {
    console.error('Status:', error.response.status);
    console.error('Response:', error.response.data);
  } else {
    console.error('Error:', error.message);
  }
});