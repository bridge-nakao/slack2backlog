#!/bin/bash

# Backlog API connection test script
# Tests API connectivity and issue creation

set -e

echo "=== Backlog API Test ==="
echo ""

# Configuration
API_KEY="${BACKLOG_API_KEY:-}"
SPACE="${BACKLOG_SPACE:-}"
PROJECT_ID="${PROJECT_ID:-}"
ISSUE_TYPE_ID="${ISSUE_TYPE_ID:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check environment variables
if [ -z "$API_KEY" ] || [ -z "$SPACE" ] || [ -z "$PROJECT_ID" ] || [ -z "$ISSUE_TYPE_ID" ]; then
    echo -e "${RED}Error: Required environment variables not set${NC}"
    echo ""
    echo "Required variables:"
    echo "  BACKLOG_API_KEY"
    echo "  BACKLOG_SPACE"
    echo "  PROJECT_ID"
    echo "  ISSUE_TYPE_ID"
    echo ""
    echo "Example:"
    echo "  export BACKLOG_API_KEY=your-api-key"
    echo "  export BACKLOG_SPACE=yourspace.backlog.com"
    echo "  export PROJECT_ID=12345"
    echo "  export ISSUE_TYPE_ID=67890"
    exit 1
fi

echo "Configuration:"
echo "  Space: $SPACE"
echo "  Project ID: $PROJECT_ID"
echo "  Issue Type ID: $ISSUE_TYPE_ID"
echo ""

# Test 1: API Connection
echo "1. Testing API connection..."
response=$(curl -s -w "\n%{http_code}" \
    "https://${SPACE}/api/v2/space?apiKey=${API_KEY}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓${NC} API connection successful"
    space_name=$(echo "$body" | jq -r .name 2>/dev/null || echo "Unknown")
    echo "   Space Name: $space_name"
else
    echo -e "${RED}✗${NC} API connection failed"
    echo "   HTTP Code: $http_code"
    echo "   Response: $body"
    exit 1
fi
echo ""

# Test 2: Project Access
echo "2. Testing project access..."
response=$(curl -s -w "\n%{http_code}" \
    "https://${SPACE}/api/v2/projects/${PROJECT_ID}?apiKey=${API_KEY}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓${NC} Project access successful"
    project_name=$(echo "$body" | jq -r .name 2>/dev/null || echo "Unknown")
    project_key=$(echo "$body" | jq -r .projectKey 2>/dev/null || echo "Unknown")
    echo "   Project: $project_name ($project_key)"
else
    echo -e "${RED}✗${NC} Project access failed"
    echo "   HTTP Code: $http_code"
    echo "   Response: $body"
    exit 1
fi
echo ""

# Test 3: Issue Type Verification
echo "3. Verifying issue type..."
response=$(curl -s -w "\n%{http_code}" \
    "https://${SPACE}/api/v2/projects/${PROJECT_ID}/issueTypes?apiKey=${API_KEY}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    issue_type_found=$(echo "$body" | jq -r ".[] | select(.id == ${ISSUE_TYPE_ID})" 2>/dev/null || echo "")
    if [ -n "$issue_type_found" ]; then
        issue_type_name=$(echo "$issue_type_found" | jq -r .name)
        echo -e "${GREEN}✓${NC} Issue type verified"
        echo "   Issue Type: $issue_type_name (ID: $ISSUE_TYPE_ID)"
    else
        echo -e "${YELLOW}!${NC} Issue type ID not found in project"
        echo "   Available issue types:"
        echo "$body" | jq -r '.[] | "   - \(.name) (ID: \(.id))"' 2>/dev/null || echo "   Unable to parse"
    fi
else
    echo -e "${RED}✗${NC} Failed to get issue types"
    echo "   HTTP Code: $http_code"
fi
echo ""

# Test 4: Get Priorities
echo "4. Getting priority list..."
response=$(curl -s -w "\n%{http_code}" \
    "https://${SPACE}/api/v2/priorities?apiKey=${API_KEY}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓${NC} Priorities retrieved"
    echo "   Available priorities:"
    echo "$body" | jq -r '.[] | "   - \(.name) (ID: \(.id))"' 2>/dev/null || echo "   Unable to parse"
else
    echo -e "${YELLOW}!${NC} Failed to get priorities"
    echo "   Will use default priority ID: 3"
fi
echo ""

# Test 5: Create Test Issue
echo "5. Creating test issue..."
timestamp=$(date +%Y%m%d%H%M%S)
summary="slack2backlog API Test - $timestamp"
description="This is a test issue created by the Backlog API test script.\\n\\nTimestamp: $timestamp\\nTest successful if you see this issue!"

response=$(curl -s -w "\n%{http_code}" -X POST \
    "https://${SPACE}/api/v2/issues?apiKey=${API_KEY}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "projectId=${PROJECT_ID}" \
    -d "summary=${summary}" \
    -d "issueTypeId=${ISSUE_TYPE_ID}" \
    -d "priorityId=3" \
    -d "description=${description}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "201" ]; then
    issue_key=$(echo "$body" | jq -r .issueKey 2>/dev/null || echo "Unknown")
    issue_id=$(echo "$body" | jq -r .id 2>/dev/null || echo "Unknown")
    echo -e "${GREEN}✓${NC} Test issue created successfully"
    echo "   Issue Key: $issue_key"
    echo "   Issue ID: $issue_id"
    echo "   URL: https://${SPACE}/view/${issue_key}"
else
    echo -e "${RED}✗${NC} Issue creation failed"
    echo "   HTTP Code: $http_code"
    echo "   Response: $body"
    exit 1
fi
echo ""

# Test 6: API Rate Limit Check
echo "6. Checking API rate limit..."
# Make a simple request and check headers
response=$(curl -s -D - -o /dev/null \
    "https://${SPACE}/api/v2/space?apiKey=${API_KEY}")

rate_limit=$(echo "$response" | grep -i "x-ratelimit-limit" | awk '{print $2}' | tr -d '\r')
rate_remaining=$(echo "$response" | grep -i "x-ratelimit-remaining" | awk '{print $2}' | tr -d '\r')

if [ -n "$rate_limit" ] && [ -n "$rate_remaining" ]; then
    echo -e "${GREEN}✓${NC} Rate limit information"
    echo "   Limit: $rate_limit requests"
    echo "   Remaining: $rate_remaining requests"
else
    echo -e "${YELLOW}!${NC} Rate limit information not available"
fi
echo ""

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}✓${NC} All tests completed successfully!"
echo ""
echo "Next steps:"
echo "1. Save these settings to your environment variables or .env file"
echo "2. Configure AWS Lambda with these values"
echo "3. Test the full integration with Slack"
echo ""
echo "Environment configuration:"
echo "  BACKLOG_API_KEY=${API_KEY:0:10}..."
echo "  BACKLOG_SPACE=$SPACE"
echo "  PROJECT_ID=$PROJECT_ID"
echo "  ISSUE_TYPE_ID=$ISSUE_TYPE_ID"
echo "  PRIORITY_ID=3"