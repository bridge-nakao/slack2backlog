const crypto = require('crypto');

module.exports = {
  generateSignature: function(requestParams, context, ee, next) {
    // Get current timestamp
    const timestamp = Math.floor(Date.now() / 1000);
    context.vars.timestamp = timestamp;

    // Generate request body
    const body = JSON.stringify(requestParams.json);

    // Generate signature
    const signingSecret = context.vars.signingSecret || 'test-signing-secret';
    const sigBasestring = `v0:${timestamp}:${body}`;
    const signature = 'v0=' + crypto
      .createHmac('sha256', signingSecret)
      .update(sigBasestring, 'utf8')
      .digest('hex');

    context.vars.signature = signature;

    return next();
  }
};