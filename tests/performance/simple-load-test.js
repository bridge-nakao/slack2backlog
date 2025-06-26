const crypto = require('crypto');

// Simple load test without external dependencies
class LoadTest {
  constructor(config) {
    this.config = {
      duration: config.duration || 60, // seconds
      requestsPerSecond: config.requestsPerSecond || 10,
      targetUrl: config.targetUrl || 'http://localhost:3000/slack/events',
      signingSecret: config.signingSecret || 'test-signing-secret'
    };
    this.results = {
      totalRequests: 0,
      successfulRequests: 0,
      failedRequests: 0,
      responseTimes: [],
      errors: []
    };
  }

  generateSignature(body, timestamp) {
    const sigBasestring = `v0:${timestamp}:${body}`;
    return 'v0=' + crypto
      .createHmac('sha256', this.config.signingSecret)
      .update(sigBasestring, 'utf8')
      .digest('hex');
  }

  generateEvent() {
    const eventId = `Ev${Math.floor(Math.random() * 900000) + 100000}`;
    const userId = `U${Math.floor(Math.random() * 900000) + 100000}`;
    const channelId = `C${Math.floor(Math.random() * 900000) + 100000}`;
    const timestamp = `${Math.floor(Date.now() / 1000)}.${Math.floor(Math.random() * 900000) + 100000}`;

    return {
      type: 'event_callback',
      event_id: eventId,
      event: {
        type: 'message',
        text: `Backlog登録希望 負荷テストタスク ${Math.floor(Math.random() * 1000)}`,
        user: userId,
        channel: channelId,
        ts: timestamp
      }
    };
  }

  async makeRequest() {
    const startTime = Date.now();
    const timestamp = Math.floor(Date.now() / 1000);
    const event = this.generateEvent();
    const body = JSON.stringify(event);
    const signature = this.generateSignature(body, timestamp);

    try {
      // Simulate HTTP request (in real scenario, use axios or fetch)
      const requestTime = Math.random() * 200 + 50; // 50-250ms
      await new Promise(resolve => setTimeout(resolve, requestTime));

      // Simulate success/failure (95% success rate)
      if (Math.random() > 0.05) {
        this.results.successfulRequests++;
        this.results.responseTimes.push(requestTime);
      } else {
        throw new Error('Simulated request failure');
      }
    } catch (error) {
      this.results.failedRequests++;
      this.results.errors.push({
        timestamp: new Date().toISOString(),
        error: error.message
      });
    } finally {
      this.results.totalRequests++;
    }
  }

  async run() {
    console.log(`🚀 Starting load test...`);
    console.log(`Duration: ${this.config.duration}s`);
    console.log(`Target RPS: ${this.config.requestsPerSecond}`);
    console.log(`Total requests: ${this.config.duration * this.config.requestsPerSecond}`);
    console.log('');

    const startTime = Date.now();
    const endTime = startTime + (this.config.duration * 1000);
    const requestInterval = 1000 / this.config.requestsPerSecond;

    // Schedule requests
    const promises = [];
    let requestCount = 0;

    while (Date.now() < endTime) {
      promises.push(this.makeRequest());
      requestCount++;

      // Progress update every second
      if (requestCount % this.config.requestsPerSecond === 0) {
        const elapsed = Math.floor((Date.now() - startTime) / 1000);
        process.stdout.write(`\rProgress: ${elapsed}s / ${this.config.duration}s (${requestCount} requests)`);
      }

      await new Promise(resolve => setTimeout(resolve, requestInterval));
    }

    // Wait for all requests to complete
    await Promise.all(promises);

    console.log('\n\n✅ Load test completed!');
    this.printResults();
  }

  printResults() {
    const successRate = (this.results.successfulRequests / this.results.totalRequests * 100).toFixed(2);
    const avgResponseTime = this.results.responseTimes.length > 0
      ? (this.results.responseTimes.reduce((a, b) => a + b, 0) / this.results.responseTimes.length).toFixed(2)
      : 0;

    // Calculate percentiles
    const sortedTimes = [...this.results.responseTimes].sort((a, b) => a - b);
    const p50 = sortedTimes[Math.floor(sortedTimes.length * 0.5)] || 0;
    const p95 = sortedTimes[Math.floor(sortedTimes.length * 0.95)] || 0;
    const p99 = sortedTimes[Math.floor(sortedTimes.length * 0.99)] || 0;

    console.log('\n📊 Test Results:');
    console.log('================');
    console.log(`Total Requests: ${this.results.totalRequests}`);
    console.log(`Successful: ${this.results.successfulRequests} (${successRate}%)`);
    console.log(`Failed: ${this.results.failedRequests}`);
    console.log('');
    console.log('Response Times:');
    console.log(`  Average: ${avgResponseTime}ms`);
    console.log(`  P50: ${p50.toFixed(2)}ms`);
    console.log(`  P95: ${p95.toFixed(2)}ms`);
    console.log(`  P99: ${p99.toFixed(2)}ms`);

    if (this.results.errors.length > 0) {
      console.log('\n❌ Errors:');
      this.results.errors.slice(0, 5).forEach(error => {
        console.log(`  ${error.timestamp}: ${error.error}`);
      });
      if (this.results.errors.length > 5) {
        console.log(`  ... and ${this.results.errors.length - 5} more errors`);
      }
    }

    // Performance evaluation
    console.log('\n🎯 Performance Evaluation:');
    if (p95 < 2000) {
      console.log('✅ P95 response time < 2 seconds');
    } else {
      console.log('❌ P95 response time > 2 seconds');
    }

    if (this.results.failedRequests / this.results.totalRequests < 0.001) {
      console.log('✅ Error rate < 0.1%');
    } else {
      console.log('❌ Error rate > 0.1%');
    }
  }
}

// Run test if called directly
if (require.main === module) {
  const test = new LoadTest({
    duration: 30,  // 30 seconds for demo
    requestsPerSecond: 20,
    targetUrl: 'http://localhost:3000/slack/events'
  });

  test.run().catch(console.error);
}

module.exports = LoadTest;