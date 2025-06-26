#!/usr/bin/env node

const crypto = require('crypto');
const axios = require('axios');

// Configuration - これらの値がenv.local.jsonと一致していることを確認
const SIGNING_SECRET = 'test-signing-secret';  // env.local.jsonのSLACK_SIGNING_SECRETと同じ値
const API_URL = 'http://localhost:3000/slack/events';

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

// Create signature
const timestamp = Math.floor(Date.now() / 1000);
const sigBasestring = `v0:${timestamp}:${JSON.stringify(event)}`;
const signature = 'v0=' + crypto
  .createHmac('sha256', SIGNING_SECRET)
  .update(sigBasestring, 'utf8')
  .digest('hex');

console.log('Configuration:');
console.log('- Signing Secret:', SIGNING_SECRET);
console.log('- Timestamp:', timestamp);
console.log('- Signature:', signature);
console.log('');

// Send request
console.log('Sending test event to:', API_URL);
console.log('Event:', JSON.stringify(event, null, 2));

axios.post(API_URL, event, {
  headers: {
    'Content-Type': 'application/json',
    'X-Slack-Request-Timestamp': timestamp.toString(),
    'X-Slack-Signature': signature
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