#!/bin/bash
set -e

echo "🧪 Running local tests..."

# Check if Docker services are running
echo "🐳 Checking Docker services..."
if ! docker-compose ps | grep -q "Up"; then
    echo "❌ Docker services are not running. Please run ./scripts/setup-local.sh first."
    exit 1
fi

# Run unit tests
echo "📋 Running unit tests..."
npm test

# Run integration tests if SAM Local is running
if curl -s http://localhost:3000 > /dev/null 2>&1; then
    echo "🔗 Running integration tests..."
    npm test -- tests/integration/integration.test.js
else
    echo "⚠️  SAM Local is not running. Skipping integration tests."
    echo "   To run integration tests: sam local start-api --env-vars env.json"
fi

# Run mock integration tests
echo "🎭 Running mock integration tests..."
npm test -- tests/integration/mock-integration.test.js

# Check test coverage
echo "📊 Checking test coverage..."
npm run test:coverage

echo ""
echo "✅ All tests completed!"