/**
 * Event Ingest Lambda Function
 * Receives Slack events and queues them for processing
 */

exports.handler = async (event) => {
  console.log('Received event:', JSON.stringify(event, null, 2));
  
  // TODO: Implement Slack signature verification
  // TODO: Handle URL verification challenge
  // TODO: Process events and send to SQS
  
  return {
    statusCode: 200,
    body: JSON.stringify({ message: 'Event received' }),
  };
};
