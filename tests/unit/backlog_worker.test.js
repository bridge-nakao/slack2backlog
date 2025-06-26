const { handler } = require('../../src/backlog_worker');

describe('Backlog Worker Lambda', () => {
  test('should process SQS messages', async () => {
    const event = {
      Records: [{
        body: JSON.stringify({ test: 'message' })
      }]
    };
    
    const result = await handler(event);
    
    expect(result.batchItemFailures).toEqual([]);
  });
});
