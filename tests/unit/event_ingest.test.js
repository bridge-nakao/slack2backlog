const { handler } = require('../../src/event_ingest');

describe('Event Ingest Lambda', () => {
  test('should return 200 for valid event', async () => {
    const event = {
      body: JSON.stringify({ type: 'event_callback' }),
      headers: {}
    };
    
    const result = await handler(event);
    
    expect(result.statusCode).toBe(200);
  });
});
