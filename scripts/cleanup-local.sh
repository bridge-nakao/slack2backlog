#!/bin/bash
set -e

echo "🧹 Cleaning up local environment..."

# Stop Docker services
echo "🛑 Stopping Docker services..."
docker-compose down

# Clean Docker volumes (optional)
read -p "Do you want to remove Docker volumes? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️ Removing Docker volumes..."
    docker-compose down -v
fi

# Clean build artifacts
echo "🗑️ Cleaning build artifacts..."
rm -rf .aws-sam/
rm -rf node_modules/.cache/

# Clean test artifacts
echo "🗑️ Cleaning test artifacts..."
rm -rf coverage/
rm -rf tests/performance/performance-report.*

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "📝 To set up the environment again, run:"
echo "  ./scripts/setup-local.sh"