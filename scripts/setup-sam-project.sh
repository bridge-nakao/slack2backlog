#!/bin/bash

# SAM project initialization script for slack2backlog

set -e  # Exit on error

echo "=== Setting up AWS SAM project for slack2backlog ==="

# Create SAM template
echo "Creating template.yaml..."
cat > template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: >
  slack2backlog

  Slack to Backlog integration bot using AWS Lambda

# Global settings for all functions
Globals:
  Function:
    Timeout: 10
    MemorySize: 512
    Runtime: nodejs20.x
    Environment:
      Variables:
        NODE_ENV: production
        LOG_LEVEL: info

Parameters:
  Stage:
    Type: String
    Default: dev
    AllowedValues:
      - dev
      - staging
      - prod
    Description: Deployment stage

Resources:
  # API Gateway
  SlackApi:
    Type: AWS::Serverless::Api
    Properties:
      StageName: !Ref Stage
      Cors:
        AllowMethods: "'POST, OPTIONS'"
        AllowHeaders: "'Content-Type,X-Slack-Signature,X-Slack-Request-Timestamp'"
        AllowOrigin: "'*'"
      Auth:
        ApiKeyRequired: false

  # Event Ingest Lambda Function
  EventIngestFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: src/event_ingest/
      Handler: index.handler
      FunctionName: !Sub ${AWS::StackName}-event-ingest-${Stage}
      Description: Receives Slack events and queues them for processing
      Environment:
        Variables:
          SQS_QUEUE_URL: !Ref EventQueue
          SLACK_SIGNING_SECRET: !Sub '{{resolve:secretsmanager:${SlackSecrets}:SecretString:signing_secret}}'
      Policies:
        - SQSSendMessagePolicy:
            QueueName: !GetAtt EventQueue.QueueName
        - AWSSecretsManagerGetSecretValuePolicy:
            SecretArn: !Ref SlackSecrets
      Events:
        SlackEvent:
          Type: Api
          Properties:
            RestApiId: !Ref SlackApi
            Path: /slack/events
            Method: POST

  # Backlog Worker Lambda Function
  BacklogWorkerFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: src/backlog_worker/
      Handler: index.handler
      FunctionName: !Sub ${AWS::StackName}-backlog-worker-${Stage}
      Description: Processes queued events and creates Backlog issues
      ReservedConcurrentExecutions: 1  # Process one at a time
      Environment:
        Variables:
          SLACK_BOT_TOKEN: !Sub '{{resolve:secretsmanager:${SlackSecrets}:SecretString:bot_token}}'
          BACKLOG_API_KEY: !Sub '{{resolve:secretsmanager:${BacklogSecrets}:SecretString:api_key}}'
          BACKLOG_SPACE: !Ref BacklogSpace
          PROJECT_ID: !Ref BacklogProjectId
          ISSUE_TYPE_ID: !Ref BacklogIssueTypeId
          PRIORITY_ID: !Ref BacklogPriorityId
          IDEMPOTENCY_TABLE: !Ref IdempotencyTable
      Policies:
        - SQSPollerPolicy:
            QueueName: !GetAtt EventQueue.QueueName
        - AWSSecretsManagerGetSecretValuePolicy:
            SecretArn: !Ref SlackSecrets
        - AWSSecretsManagerGetSecretValuePolicy:
            SecretArn: !Ref BacklogSecrets
        - DynamoDBCrudPolicy:
            TableName: !Ref IdempotencyTable
      Events:
        SQSEvent:
          Type: SQS
          Properties:
            Queue: !GetAtt EventQueue.Arn
            BatchSize: 1

  # SQS Queue
  EventQueue:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub ${AWS::StackName}-event-queue-${Stage}
      VisibilityTimeout: 60
      MessageRetentionPeriod: 345600  # 4 days
      RedrivePolicy:
        deadLetterTargetArn: !GetAtt DeadLetterQueue.Arn
        maxReceiveCount: 3

  # Dead Letter Queue
  DeadLetterQueue:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub ${AWS::StackName}-dlq-${Stage}
      MessageRetentionPeriod: 1209600  # 14 days

  # DynamoDB Table for Idempotency
  IdempotencyTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: !Sub ${AWS::StackName}-idempotency-${Stage}
      AttributeDefinitions:
        - AttributeName: event_id
          AttributeType: S
      KeySchema:
        - AttributeName: event_id
          KeyType: HASH
      BillingMode: PAY_PER_REQUEST
      TimeToLiveSpecification:
        AttributeName: ttl
        Enabled: true

  # Secrets Manager for Slack credentials
  SlackSecrets:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub ${AWS::StackName}-slack-secrets-${Stage}
      Description: Slack Bot Token and Signing Secret
      SecretString: |
        {
          "bot_token": "xoxb-placeholder",
          "signing_secret": "placeholder"
        }

  # Secrets Manager for Backlog credentials
  BacklogSecrets:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub ${AWS::StackName}-backlog-secrets-${Stage}
      Description: Backlog API Key
      SecretString: |
        {
          "api_key": "placeholder"
        }

  # Parameters for Backlog configuration
  BacklogSpace:
    Type: AWS::SSM::Parameter
    Properties:
      Name: !Sub /${AWS::StackName}/${Stage}/backlog/space
      Type: String
      Value: example.backlog.com
      Description: Backlog space URL

  BacklogProjectId:
    Type: AWS::SSM::Parameter
    Properties:
      Name: !Sub /${AWS::StackName}/${Stage}/backlog/project_id
      Type: String
      Value: "12345"
      Description: Default Backlog project ID

  BacklogIssueTypeId:
    Type: AWS::SSM::Parameter
    Properties:
      Name: !Sub /${AWS::StackName}/${Stage}/backlog/issue_type_id
      Type: String
      Value: "67890"
      Description: Default Backlog issue type ID

  BacklogPriorityId:
    Type: AWS::SSM::Parameter
    Properties:
      Name: !Sub /${AWS::StackName}/${Stage}/backlog/priority_id
      Type: String
      Value: "3"
      Description: Default Backlog priority ID

Outputs:
  ApiUrl:
    Description: API Gateway endpoint URL
    Value: !Sub https://${SlackApi}.execute-api.${AWS::Region}.amazonaws.com/${Stage}/slack/events
    Export:
      Name: !Sub ${AWS::StackName}-api-url

  EventQueueUrl:
    Description: SQS Queue URL
    Value: !Ref EventQueue
    Export:
      Name: !Sub ${AWS::StackName}-queue-url

  EventQueueArn:
    Description: SQS Queue ARN
    Value: !GetAtt EventQueue.Arn
    Export:
      Name: !Sub ${AWS::StackName}-queue-arn
EOF

# Create samconfig.toml
echo "Creating samconfig.toml..."
cat > samconfig.toml << 'EOF'
version = 0.1

[default]
[default.global.parameters]
stack_name = "slack2backlog"

[default.build.parameters]
cached = true
parallel = true

[default.deploy.parameters]
capabilities = "CAPABILITY_IAM"
confirm_changeset = true
resolve_s3 = true
s3_prefix = "slack2backlog"
region = "ap-northeast-1"
parameter_overrides = "Stage=\"dev\""

[default.validate.parameters]
lint = true

[default.sync.parameters]
watch = true

[default.local_start_api.parameters]
warm_containers = "EAGER"

[default.local_start_lambda.parameters]
warm_containers = "EAGER"

# Production configuration
[prod]
[prod.deploy.parameters]
capabilities = "CAPABILITY_IAM"
confirm_changeset = true
resolve_s3 = true
parameter_overrides = "Stage=\"prod\""
EOF

# Create docker-compose.yml for local development
echo "Creating docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Local DynamoDB
  dynamodb-local:
    image: amazon/dynamodb-local:latest
    container_name: slack2backlog-dynamodb
    ports:
      - "8000:8000"
    command: "-jar DynamoDBLocal.jar -sharedDb -dbPath ./data"
    volumes:
      - "./docker/dynamodb:/home/dynamodblocal/data"
    working_dir: /home/dynamodblocal

  # LocalStack for SQS and Secrets Manager
  localstack:
    image: localstack/localstack:latest
    container_name: slack2backlog-localstack
    ports:
      - "4566:4566"
    environment:
      - SERVICES=sqs,secretsmanager,ssm
      - DEBUG=1
      - DATA_DIR=/tmp/localstack/data
      - DOCKER_HOST=unix:///var/run/docker.sock
    volumes:
      - "./docker/localstack:/tmp/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"
EOF

# Create local development scripts
echo "Creating local development scripts..."
mkdir -p scripts/local

# Script to start local services
cat > scripts/local/start-local.sh << 'EOF'
#!/bin/bash

echo "Starting local development services..."

# Start Docker services
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 5

# Create local DynamoDB table
aws dynamodb create-table \
  --table-name slack2backlog-idempotency-dev \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:8000 \
  2>/dev/null || echo "Table already exists"

# Create local SQS queues
aws sqs create-queue \
  --queue-name slack2backlog-event-queue-dev \
  --endpoint-url http://localhost:4566 \
  2>/dev/null || echo "Queue already exists"

aws sqs create-queue \
  --queue-name slack2backlog-dlq-dev \
  --endpoint-url http://localhost:4566 \
  2>/dev/null || echo "DLQ already exists"

echo "Local services are ready!"
echo ""
echo "To start SAM local API:"
echo "  sam local start-api"
echo ""
echo "To invoke a function directly:"
echo "  sam local invoke EventIngestFunction -e events/slack-event.json"
EOF

# Script to stop local services
cat > scripts/local/stop-local.sh << 'EOF'
#!/bin/bash

echo "Stopping local development services..."
docker-compose down

echo "Local services stopped."
EOF

# Make scripts executable
chmod +x scripts/local/*.sh

# Create buildspec.yml for CI/CD
echo "Creating buildspec.yml..."
cat > buildspec.yml << 'EOF'
version: 0.2

phases:
  install:
    runtime-versions:
      nodejs: 20
      python: 3.12
    commands:
      - echo Installing SAM CLI
      - pip install aws-sam-cli
      - echo Installing dependencies
      - npm install

  pre_build:
    commands:
      - echo Running tests
      - npm test
      - echo Running linter
      - npm run lint

  build:
    commands:
      - echo Building SAM application
      - sam build

  post_build:
    commands:
      - echo Build completed on `date`
      - echo Packaging application
      - |
        sam package \
          --s3-bucket ${BUCKET_NAME} \
          --output-template-file packaged-template.yaml

artifacts:
  files:
    - packaged-template.yaml
    - buildspec.yml

cache:
  paths:
    - 'node_modules/**/*'
    - '.aws-sam/**/*'
EOF

# Create sample event for testing
echo "Creating sample Slack event..."
mkdir -p events
cat > events/slack-event.json << 'EOF'
{
  "body": "{\"token\":\"verification_token\",\"team_id\":\"T123\",\"api_app_id\":\"A123\",\"event\":{\"type\":\"message\",\"channel\":\"C123\",\"user\":\"U123\",\"text\":\"Backlog登録希望 テストタスク\",\"ts\":\"1234567890.123456\",\"event_ts\":\"1234567890.123456\"},\"type\":\"event_callback\",\"event_id\":\"Ev123\",\"event_time\":1234567890}",
  "headers": {
    "X-Slack-Signature": "v0=a2114d57b48eac39b9ad189dd8316235a7b4a8d21a10bd27519666489c69b503",
    "X-Slack-Request-Timestamp": "1234567890",
    "Content-Type": "application/json"
  },
  "httpMethod": "POST",
  "path": "/slack/events"
}
EOF

# Create URL verification event
cat > events/url-verification.json << 'EOF'
{
  "body": "{\"token\":\"verification_token\",\"challenge\":\"3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P\",\"type\":\"url_verification\"}",
  "headers": {
    "Content-Type": "application/json"
  },
  "httpMethod": "POST",
  "path": "/slack/events"
}
EOF

echo "=== SAM project setup complete! ==="
echo ""
echo "Next steps:"
echo "1. Review and customize template.yaml"
echo "2. Update placeholder values in Secrets Manager"
echo "3. Run 'sam validate' to check the template"
echo "4. Run 'sam build' to build the application"
echo "5. Run 'sam local start-api' for local testing"
echo ""
echo "For local development:"
echo "  ./scripts/local/start-local.sh  # Start local services"
echo "  sam local start-api             # Start local API"
echo "  ./scripts/local/stop-local.sh   # Stop local services"