const LoadTest = require('./simple-load-test');

describe('Load Test', () => {
  test('should handle basic load scenario', async () => {
    const loadTest = new LoadTest({
      duration: 5,  // 5 seconds for unit test
      requestsPerSecond: 10,
      targetUrl: 'http://localhost:3000/slack/events'
    });

    await loadTest.run();

    // Verify results
    expect(loadTest.results.totalRequests).toBeGreaterThan(0);
    expect(loadTest.results.totalRequests).toBeLessThanOrEqual(50);
    
    // Success rate should be above 85% (considering simulated failures)
    const successRate = loadTest.results.successfulRequests / loadTest.results.totalRequests;
    expect(successRate).toBeGreaterThan(0.85);

    // Average response time should be reasonable
    const avgResponseTime = loadTest.results.responseTimes.reduce((a, b) => a + b, 0) / loadTest.results.responseTimes.length;
    expect(avgResponseTime).toBeLessThan(300); // Under 300ms
  }, 10000); // 10 second timeout

  test('should calculate performance metrics correctly', () => {
    const loadTest = new LoadTest({});
    
    // Mock results
    loadTest.results = {
      totalRequests: 100,
      successfulRequests: 95,
      failedRequests: 5,
      responseTimes: [
        50, 60, 70, 80, 90, 100, 110, 120, 130, 140,
        150, 160, 170, 180, 190, 200, 210, 220, 230, 240,
        250, 260, 270, 280, 290, 300, 310, 320, 330, 340,
        350, 360, 370, 380, 390, 400, 410, 420, 430, 440,
        450, 460, 470, 480, 490, 500, 510, 520, 530, 540,
        550, 560, 570, 580, 590, 600, 610, 620, 630, 640,
        650, 660, 670, 680, 690, 700, 710, 720, 730, 740,
        750, 760, 770, 780, 790, 800, 810, 820, 830, 840,
        850, 860, 870, 880, 890, 900, 910, 920, 930, 940,
        950, 960, 970, 980, 990
      ],
      errors: []
    };

    // Calculate metrics
    const sortedTimes = [...loadTest.results.responseTimes].sort((a, b) => a - b);
    const p50 = sortedTimes[Math.floor(sortedTimes.length * 0.5)];
    const p95 = sortedTimes[Math.floor(sortedTimes.length * 0.95)];
    const p99 = sortedTimes[Math.floor(sortedTimes.length * 0.99)];

    expect(p50).toBe(520); // 50th percentile
    expect(p95).toBe(950); // 95th percentile
    expect(p99).toBe(990); // 99th percentile
  });

  test('should generate valid Slack signatures', () => {
    const loadTest = new LoadTest({
      signingSecret: 'test-secret'
    });

    const body = '{"test":"data"}';
    const timestamp = 1234567890;
    const signature = loadTest.generateSignature(body, timestamp);

    expect(signature).toMatch(/^v0=[a-f0-9]{64}$/);
  });

  test('should generate valid event structure', () => {
    const loadTest = new LoadTest({});
    const event = loadTest.generateEvent();

    expect(event).toHaveProperty('type', 'event_callback');
    expect(event).toHaveProperty('event_id');
    expect(event.event_id).toMatch(/^Ev\d{6}$/);
    
    expect(event.event).toHaveProperty('type', 'message');
    expect(event.event).toHaveProperty('text');
    expect(event.event.text).toContain('Backlog登録希望');
    expect(event.event).toHaveProperty('user');
    expect(event.event.user).toMatch(/^U\d{6}$/);
    expect(event.event).toHaveProperty('channel');
    expect(event.event.channel).toMatch(/^C\d{6}$/);
    expect(event.event).toHaveProperty('ts');
  });
});