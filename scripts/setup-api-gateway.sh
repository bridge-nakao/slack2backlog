#!/bin/bash

# API Gateway detailed configuration script for slack2backlog

set -e  # Exit on error

echo "=== Enhancing API Gateway configuration for slack2backlog ==="

# Create API Gateway OpenAPI specification
echo "Creating API specification..."
mkdir -p docs/api
cat > docs/api/openapi.yaml << 'EOF'
openapi: 3.0.0
info:
  title: Slack2Backlog API
  description: API for receiving Slack events and processing them to create Backlog issues
  version: 1.0.0
  contact:
    name: API Support
    email: nakao@bridge.vc

servers:
  - url: https://api.example.com/{stage}
    description: Production API
    variables:
      stage:
        default: prod
        enum:
          - dev
          - staging
          - prod
  - url: http://localhost:3000
    description: Local development server

paths:
  /slack/events:
    post:
      summary: Receive Slack Events
      description: Endpoint for Slack Events API to send workspace events
      operationId: receiveSlackEvent
      tags:
        - Slack Integration
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/SlackEvent'
            examples:
              message:
                summary: Message event
                value:
                  token: "verification_token"
                  team_id: "T123"
                  api_app_id: "A123"
                  event:
                    type: "message"
                    channel: "C123"
                    user: "U123"
                    text: "Backlog登録希望 テストタスク"
                    ts: "1234567890.123456"
                  type: "event_callback"
                  event_id: "Ev123"
              url_verification:
                summary: URL verification challenge
                value:
                  token: "verification_token"
                  challenge: "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P"
                  type: "url_verification"
      parameters:
        - in: header
          name: X-Slack-Signature
          schema:
            type: string
          required: true
          description: HMAC-SHA256 signature for request verification
        - in: header
          name: X-Slack-Request-Timestamp
          schema:
            type: string
          required: true
          description: Unix timestamp of when the request was sent
      responses:
        '200':
          description: Event received successfully
          content:
            application/json:
              schema:
                oneOf:
                  - $ref: '#/components/schemas/EventResponse'
                  - $ref: '#/components/schemas/ChallengeResponse'
        '400':
          description: Bad request - Invalid signature or timestamp
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'
        '500':
          description: Internal server error
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'
      x-amazon-apigateway-integration:
        uri:
          Fn::Sub: arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${EventIngestFunction.Arn}/invocations
        passthroughBehavior: when_no_match
        httpMethod: POST
        type: aws_proxy

components:
  schemas:
    SlackEvent:
      type: object
      required:
        - token
        - type
      properties:
        token:
          type: string
          description: Verification token (deprecated, use signing secret)
        team_id:
          type: string
          description: Slack workspace ID
        api_app_id:
          type: string
          description: Slack app ID
        event:
          type: object
          description: The actual event data
          properties:
            type:
              type: string
              enum: [message, app_mention, reaction_added]
            channel:
              type: string
            user:
              type: string
            text:
              type: string
            ts:
              type: string
        type:
          type: string
          enum: [url_verification, event_callback]
        challenge:
          type: string
          description: Challenge parameter for URL verification
        event_id:
          type: string
          description: Unique event identifier
        event_time:
          type: integer
          description: Unix timestamp of event

    EventResponse:
      type: object
      properties:
        ok:
          type: boolean
          default: true

    ChallengeResponse:
      type: object
      properties:
        challenge:
          type: string
          description: Echo back the challenge parameter

    ErrorResponse:
      type: object
      properties:
        error:
          type: string
          description: Error message
        details:
          type: object
          description: Additional error details

  securitySchemes:
    SlackSignature:
      type: apiKey
      in: header
      name: X-Slack-Signature
      description: HMAC-SHA256 signature for request verification

security:
  - SlackSignature: []
EOF

# Create API Gateway request validation models
echo "Creating request validation models..."
cat > docs/api/models.json << 'EOF'
{
  "SlackEventModel": {
    "$schema": "http://json-schema.org/draft-04/schema#",
    "title": "Slack Event",
    "type": "object",
    "required": ["type"],
    "properties": {
      "token": {
        "type": "string"
      },
      "team_id": {
        "type": "string"
      },
      "api_app_id": {
        "type": "string"
      },
      "event": {
        "type": "object",
        "properties": {
          "type": {
            "type": "string"
          },
          "channel": {
            "type": "string"
          },
          "user": {
            "type": "string"
          },
          "text": {
            "type": "string"
          },
          "ts": {
            "type": "string"
          }
        }
      },
      "type": {
        "type": "string",
        "enum": ["url_verification", "event_callback"]
      },
      "challenge": {
        "type": "string"
      },
      "event_id": {
        "type": "string"
      },
      "event_time": {
        "type": "integer"
      }
    }
  }
}
EOF

# Create enhanced SAM template with API Gateway specifics
echo "Creating enhanced API Gateway configuration..."
cat > template-api-enhanced.yaml << 'EOF'
# Additional API Gateway configurations to be merged with main template
Resources:
  SlackApi:
    Type: AWS::Serverless::Api
    Properties:
      StageName: !Ref Stage
      Name: !Sub ${AWS::StackName}-api
      Description: API Gateway for Slack2Backlog integration
      TracingEnabled: true
      MethodSettings:
        - ResourcePath: '/*'
          HttpMethod: '*'
          LoggingLevel: INFO
          DataTraceEnabled: true
          MetricsEnabled: true
          ThrottlingRateLimit: 100
          ThrottlingBurstLimit: 200
      AccessLogSetting:
        DestinationArn: !GetAtt ApiLogGroup.Arn
        Format: '$context.requestId $context.requestTime $context.httpMethod $context.path $context.status $context.responseLength $context.error.message $context.error.messageString'
      Cors:
        AllowMethods: "'POST, OPTIONS'"
        AllowHeaders: "'Content-Type,X-Slack-Signature,X-Slack-Request-Timestamp'"
        AllowOrigin: "'*'"
        MaxAge: 86400
      Auth:
        ApiKeyRequired: false
      EndpointConfiguration:
        Type: REGIONAL
      Tags:
        Environment: !Ref Stage
        Application: slack2backlog

  ApiLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub /aws/api-gateway/${AWS::StackName}-${Stage}
      RetentionInDays: 7

  ApiGatewayAccount:
    Type: AWS::ApiGateway::Account
    Properties:
      CloudWatchRoleArn: !GetAtt ApiGatewayCloudWatchRole.Arn

  ApiGatewayCloudWatchRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service:
                - apigateway.amazonaws.com
            Action: 'sts:AssumeRole'
      Path: /
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs

  # Request Validator
  RequestValidator:
    Type: AWS::ApiGateway::RequestValidator
    Properties:
      Name: RequestBodyValidator
      RestApiId: !Ref SlackApi
      ValidateRequestBody: true
      ValidateRequestParameters: true

  # Usage Plan for rate limiting
  ApiUsagePlan:
    Type: AWS::ApiGateway::UsagePlan
    DependsOn: SlackApiStage
    Properties:
      UsagePlanName: !Sub ${AWS::StackName}-usage-plan
      Description: Usage plan for Slack2Backlog API
      ApiStages:
        - ApiId: !Ref SlackApi
          Stage: !Ref Stage
      Throttle:
        RateLimit: 100
        BurstLimit: 200
      Quota:
        Limit: 1000000
        Period: MONTH

  # CloudWatch Dashboard
  ApiDashboard:
    Type: AWS::CloudWatch::Dashboard
    Properties:
      DashboardName: !Sub ${AWS::StackName}-api-dashboard
      DashboardBody: !Sub |
        {
          "widgets": [
            {
              "type": "metric",
              "properties": {
                "metrics": [
                  ["AWS/ApiGateway", "Count", {"stat": "Sum"}],
                  [".", "4XXError", {"stat": "Sum"}],
                  [".", "5XXError", {"stat": "Sum"}]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS::Region}",
                "title": "API Gateway Requests"
              }
            },
            {
              "type": "metric",
              "properties": {
                "metrics": [
                  ["AWS/ApiGateway", "Latency", {"stat": "Average"}],
                  [".", ".", {"stat": "p99"}]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS::Region}",
                "title": "API Gateway Latency"
              }
            }
          ]
        }
EOF

# Create API testing script
echo "Creating API testing script..."
cat > scripts/test-api-gateway.sh << 'EOF'
#!/bin/bash

# API Gateway testing script

set -e

echo "=== Testing API Gateway endpoints ==="

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for this script. Please install it."
    exit 1
fi

# Get API endpoint from CloudFormation stack
STACK_NAME="slack2backlog"
STAGE="${1:-dev}"

echo "Getting API endpoint for stage: $STAGE"

# For local testing
if [ "$STAGE" == "local" ]; then
    API_ENDPOINT="http://localhost:3000"
else
    # Get from CloudFormation outputs
    API_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$API_ENDPOINT" ]; then
        echo "Error: Could not find API endpoint. Is the stack deployed?"
        exit 1
    fi
fi

echo "API Endpoint: $API_ENDPOINT"
echo ""

# Test 1: URL Verification
echo "Test 1: URL Verification Challenge"
echo "--------------------------------"
CHALLENGE="test_challenge_string_12345"
RESPONSE=$(curl -s -X POST $API_ENDPOINT \
    -H "Content-Type: application/json" \
    -H "X-Slack-Signature: v0=dummy_signature" \
    -H "X-Slack-Request-Timestamp: $(date +%s)" \
    -d "{\"type\":\"url_verification\",\"challenge\":\"$CHALLENGE\"}")

echo "Response: $RESPONSE"
echo ""

# Test 2: Message Event
echo "Test 2: Message Event"
echo "--------------------"
TIMESTAMP=$(date +%s)
EVENT_JSON=$(cat <<EOF
{
  "token": "verification_token",
  "team_id": "T123",
  "api_app_id": "A123",
  "event": {
    "type": "message",
    "channel": "C123",
    "user": "U123",
    "text": "Backlog登録希望 API Gateway Test",
    "ts": "$TIMESTAMP.000000"
  },
  "type": "event_callback",
  "event_id": "Ev123TEST",
  "event_time": $TIMESTAMP
}
EOF
)

RESPONSE=$(curl -s -X POST $API_ENDPOINT \
    -H "Content-Type: application/json" \
    -H "X-Slack-Signature: v0=dummy_signature" \
    -H "X-Slack-Request-Timestamp: $TIMESTAMP" \
    -d "$EVENT_JSON")

echo "Response: $RESPONSE"
echo ""

# Test 3: Invalid Request (missing required fields)
echo "Test 3: Invalid Request"
echo "----------------------"
RESPONSE=$(curl -s -X POST $API_ENDPOINT \
    -H "Content-Type: application/json" \
    -H "X-Slack-Signature: v0=dummy_signature" \
    -H "X-Slack-Request-Timestamp: $(date +%s)" \
    -d "{}")

echo "Response: $RESPONSE"
echo ""

# Test 4: OPTIONS request (CORS preflight)
echo "Test 4: CORS Preflight"
echo "---------------------"
RESPONSE=$(curl -s -X OPTIONS $API_ENDPOINT \
    -H "Origin: https://slack.com" \
    -H "Access-Control-Request-Method: POST" \
    -H "Access-Control-Request-Headers: Content-Type,X-Slack-Signature" \
    -v 2>&1 | grep -E "(< HTTP|< Access-Control)")

echo "$RESPONSE"
echo ""

echo "=== API Gateway tests complete ==="
EOF

chmod +x scripts/test-api-gateway.sh

# Create monitoring setup script
echo "Creating monitoring setup script..."
cat > scripts/setup-api-monitoring.sh << 'EOF'
#!/bin/bash

# API Gateway monitoring setup

set -e

echo "=== Setting up API Gateway monitoring ==="

STACK_NAME="${1:-slack2backlog}"
STAGE="${2:-dev}"

# Create CloudWatch alarms
echo "Creating CloudWatch alarms..."

# 4XX Error Rate Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${STACK_NAME}-${STAGE}-4XX-Errors" \
    --alarm-description "Alert on high 4XX error rate" \
    --metric-name 4XXError \
    --namespace AWS/ApiGateway \
    --statistic Sum \
    --period 300 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --treat-missing-data notBreaching \
    --dimensions Name=ApiName,Value="${STACK_NAME}-api" Name=Stage,Value=$STAGE

# 5XX Error Rate Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${STACK_NAME}-${STAGE}-5XX-Errors" \
    --alarm-description "Alert on any 5XX errors" \
    --metric-name 5XXError \
    --namespace AWS/ApiGateway \
    --statistic Sum \
    --period 60 \
    --threshold 1 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --treat-missing-data notBreaching \
    --dimensions Name=ApiName,Value="${STACK_NAME}-api" Name=Stage,Value=$STAGE

# High Latency Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${STACK_NAME}-${STAGE}-High-Latency" \
    --alarm-description "Alert on high API latency" \
    --metric-name Latency \
    --namespace AWS/ApiGateway \
    --statistic Average \
    --period 300 \
    --threshold 1000 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --treat-missing-data notBreaching \
    --dimensions Name=ApiName,Value="${STACK_NAME}-api" Name=Stage,Value=$STAGE

echo "CloudWatch alarms created successfully!"
echo ""
echo "To view alarms:"
echo "  aws cloudwatch describe-alarms --alarm-name-prefix '${STACK_NAME}-${STAGE}'"
EOF

chmod +x scripts/setup-api-monitoring.sh

echo "=== API Gateway configuration enhancement complete! ==="
echo ""
echo "Created files:"
echo "  - docs/api/openapi.yaml        : OpenAPI specification"
echo "  - docs/api/models.json         : Request validation models"
echo "  - template-api-enhanced.yaml   : Enhanced API configurations"
echo "  - scripts/test-api-gateway.sh  : API testing script"
echo "  - scripts/setup-api-monitoring.sh : Monitoring setup script"
echo ""
echo "Next steps:"
echo "1. Review the OpenAPI specification"
echo "2. Deploy with 'sam deploy'"
echo "3. Run './scripts/test-api-gateway.sh' to test endpoints"
echo "4. Set up monitoring with './scripts/setup-api-monitoring.sh'"