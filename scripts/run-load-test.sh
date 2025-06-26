#!/bin/bash
set -e

echo "🚀 Starting load test..."

# Check if Artillery is installed
if ! command -v artillery &> /dev/null; then
    echo "⚠️  Artillery not found. Using simple load test instead."
    echo ""
    
    # Run simple load test
    node tests/performance/simple-load-test.js
    
else
    echo "📊 Running Artillery load test..."
    echo ""
    
    # Ensure SAM application is built
    echo "🔨 Building SAM application..."
    sam build
    
    # Start SAM Local in background
    echo "🌐 Starting SAM Local API..."
    sam local start-api --env-vars env.json --port 3000 &
    SAM_PID=$!
    
    # Wait for SAM Local to start
    echo "⏳ Waiting for API to be ready..."
    sleep 10
    
    # Run Artillery test
    echo "💥 Running load test..."
    artillery run tests/performance/artillery-config.yml
    
    # Cleanup
    echo "🧹 Cleaning up..."
    kill $SAM_PID 2>/dev/null || true
fi

echo ""
echo "✅ Load test completed!"