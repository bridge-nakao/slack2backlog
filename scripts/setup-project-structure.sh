#!/bin/bash

# Project structure setup script for slack2backlog

set -e  # Exit on error

echo "=== Setting up slack2backlog project structure ==="

# Create directory structure
echo "Creating directory structure..."
mkdir -p src/{event_ingest,backlog_worker,shared}
mkdir -p tests/{unit,integration,load}
mkdir -p docs
mkdir -p scripts
mkdir -p .github/workflows
mkdir -p events  # For SAM test events

# Create package.json for Node.js Lambda functions
echo "Creating package.json files..."
cat > package.json << 'EOF'
{
  "name": "slack2backlog",
  "version": "1.0.0",
  "description": "Slack to Backlog integration bot using AWS Lambda",
  "main": "index.js",
  "scripts": {
    "test": "jest",
    "test:coverage": "jest --coverage",
    "lint": "eslint src/**/*.js",
    "format": "prettier --write src/**/*.js tests/**/*.js",
    "build": "sam build",
    "deploy": "sam deploy",
    "local": "sam local start-api"
  },
  "keywords": ["slack", "backlog", "lambda", "aws", "integration"],
  "author": "bridge-nakao",
  "license": "MIT",
  "devDependencies": {
    "eslint": "^8.57.0",
    "jest": "^30.0.0",
    "prettier": "^3.3.3",
    "@types/aws-lambda": "^8.10.145",
    "@types/node": "^20.0.0"
  },
  "dependencies": {
    "@slack/web-api": "^7.7.0",
    "aws-sdk": "^2.1691.0",
    "axios": "^1.7.7"
  }
}
EOF

# Create package.json for each Lambda function
for func in event_ingest backlog_worker; do
  cat > src/${func}/package.json << EOF
{
  "name": "slack2backlog-${func}",
  "version": "1.0.0",
  "description": "${func} Lambda function",
  "main": "index.js",
  "dependencies": {}
}
EOF
done

# Create requirements.txt for Python alternative
echo "Creating requirements.txt..."
cat > requirements.txt << 'EOF'
# AWS SDK (boto3 is included in Lambda runtime)
# boto3==1.35.0

# Slack SDK
slack-sdk==3.33.0

# HTTP client
requests==2.32.3

# Testing
pytest==8.3.3
pytest-cov==5.0.0
pytest-mock==3.14.0

# Linting
black==24.8.0
flake8==7.1.1
mypy==1.11.2

# Development
python-dotenv==1.0.1
EOF

# Create comprehensive .gitignore
echo "Creating .gitignore..."
cat > .gitignore << 'EOF'
# Node.js
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.npm

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
venv/
env/
.env
.venv

# AWS SAM
.aws-sam/
samconfig.toml
packaged.yaml

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Test coverage
coverage/
.coverage
htmlcov/
*.lcov

# Build artifacts
dist/
build/
*.egg-info/

# Logs
logs/
*.log

# Environment files
.env
.env.local
.env.*.local

# Temporary files
tmp/
temp/
*.tmp

# AWS
.aws/

# Secrets - NEVER commit these
secrets/
*.pem
*.key
EOF

# Create .eslintrc.json
echo "Creating .eslintrc.json..."
cat > .eslintrc.json << 'EOF'
{
  "env": {
    "node": true,
    "es2021": true,
    "jest": true
  },
  "extends": "eslint:recommended",
  "parserOptions": {
    "ecmaVersion": 2021,
    "sourceType": "module"
  },
  "rules": {
    "indent": ["error", 2],
    "quotes": ["error", "single"],
    "semi": ["error", "always"],
    "no-unused-vars": ["error", { "argsIgnorePattern": "^_" }]
  }
}
EOF

# Create .prettierrc
echo "Creating .prettierrc..."
cat > .prettierrc << 'EOF'
{
  "singleQuote": true,
  "trailingComma": "es5",
  "tabWidth": 2,
  "semi": true,
  "printWidth": 100
}
EOF

# Create jest.config.js
echo "Creating jest.config.js..."
cat > jest.config.js << 'EOF'
module.exports = {
  testEnvironment: 'node',
  coverageDirectory: 'coverage',
  collectCoverageFrom: [
    'src/**/*.js',
    '!src/**/*.test.js',
    '!**/node_modules/**'
  ],
  testMatch: [
    '**/tests/**/*.test.js',
    '**/tests/**/*.spec.js'
  ],
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    }
  }
};
EOF

# Create README template
echo "Updating README.md..."
cat > README_PROJECT.md << 'EOF'
# slack2backlog - Project Structure

## Directory Structure

```
slack2backlog/
├── src/                      # Source code
│   ├── event_ingest/        # Lambda function for receiving Slack events
│   │   ├── index.js         # Main handler
│   │   └── package.json     # Function-specific dependencies
│   ├── backlog_worker/      # Lambda function for processing Backlog tasks
│   │   ├── index.js         # Main handler
│   │   └── package.json     # Function-specific dependencies
│   └── shared/              # Shared utilities and libraries
│       ├── slack-client.js  # Slack API client
│       ├── backlog-client.js # Backlog API client
│       └── utils.js         # Common utilities
├── tests/                    # Test files
│   ├── unit/                # Unit tests
│   ├── integration/         # Integration tests
│   └── load/                # Load tests
├── docs/                     # Documentation
├── scripts/                  # Utility scripts
├── events/                   # SAM test events
├── .github/workflows/        # GitHub Actions
├── template.yaml            # SAM template (to be created)
├── samconfig.toml          # SAM configuration (to be created)
├── package.json            # Root package.json
├── requirements.txt        # Python dependencies (alternative)
├── jest.config.js          # Jest configuration
├── .eslintrc.json          # ESLint configuration
├── .prettierrc             # Prettier configuration
└── .gitignore              # Git ignore file
```

## Development Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Run tests:
   ```bash
   npm test
   ```

3. Run linter:
   ```bash
   npm run lint
   ```

4. Build SAM application:
   ```bash
   npm run build
   ```

5. Start local API:
   ```bash
   npm run local
   ```

## Available Scripts

- `npm test` - Run tests
- `npm run test:coverage` - Run tests with coverage
- `npm run lint` - Run ESLint
- `npm run format` - Format code with Prettier
- `npm run build` - Build SAM application
- `npm run deploy` - Deploy to AWS
- `npm run local` - Start local API with SAM

## Technology Stack

- **Runtime**: Node.js 20.x / Python 3.12
- **Framework**: AWS SAM
- **Testing**: Jest (Node.js) / pytest (Python)
- **Linting**: ESLint (Node.js) / flake8 (Python)
- **Formatting**: Prettier (Node.js) / black (Python)
EOF

# Create sample Lambda function templates
echo "Creating Lambda function templates..."

# event_ingest template
cat > src/event_ingest/index.js << 'EOF'
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
EOF

# backlog_worker template
cat > src/backlog_worker/index.js << 'EOF'
/**
 * Backlog Worker Lambda Function
 * Processes queued events and creates Backlog issues
 */

exports.handler = async (event) => {
  console.log('Processing SQS event:', JSON.stringify(event, null, 2));
  
  // TODO: Process SQS messages
  // TODO: Create Backlog issues
  // TODO: Send Slack thread replies
  // TODO: Handle errors and retries
  
  return {
    batchItemFailures: []
  };
};
EOF

# Create test templates
echo "Creating test templates..."

cat > tests/unit/event_ingest.test.js << 'EOF'
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
EOF

cat > tests/unit/backlog_worker.test.js << 'EOF'
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
EOF

echo "=== Project structure setup complete! ==="
echo ""
echo "Next steps:"
echo "1. Run 'npm install' to install dependencies"
echo "2. Review and merge README_PROJECT.md content into README.md"
echo "3. Start implementing Lambda functions in src/"
echo ""
echo "Directory structure created successfully!"
EOF