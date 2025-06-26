#!/bin/bash

# Script to retrieve Backlog project information
# Helps users find their project ID, issue type IDs, etc.

set -e

echo "=== Backlog Information Retrieval Tool ==="
echo ""

# Configuration
API_KEY="${BACKLOG_API_KEY:-}"
SPACE="${BACKLOG_SPACE:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check environment variables
if [ -z "$API_KEY" ] || [ -z "$SPACE" ]; then
    echo -e "${RED}Error: Required environment variables not set${NC}"
    echo ""
    echo "Required variables:"
    echo "  BACKLOG_API_KEY - Your Backlog API key"
    echo "  BACKLOG_SPACE - Your Backlog space (e.g., yourspace.backlog.com)"
    echo ""
    echo "Example:"
    echo "  export BACKLOG_API_KEY=your-api-key"
    echo "  export BACKLOG_SPACE=yourspace.backlog.com"
    exit 1
fi

echo "Using Space: $SPACE"
echo ""

# Test API connection
echo "Testing API connection..."
response=$(curl -s -w "\n%{http_code}" \
    "https://${SPACE}/api/v2/space?apiKey=${API_KEY}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" != "200" ]; then
    echo -e "${RED}✗${NC} API connection failed"
    echo "   HTTP Code: $http_code"
    echo "   Response: $body"
    exit 1
fi

space_name=$(echo "$body" | jq -r .name 2>/dev/null || echo "Unknown")
echo -e "${GREEN}✓${NC} Connected to: $space_name"
echo ""

# Get user information
echo -e "${BLUE}User Information:${NC}"
response=$(curl -s "https://${SPACE}/api/v2/users/myself?apiKey=${API_KEY}")
user_name=$(echo "$response" | jq -r .name 2>/dev/null || echo "Unknown")
user_id=$(echo "$response" | jq -r .id 2>/dev/null || echo "Unknown")
echo "  Name: $user_name"
echo "  User ID: $user_id"
echo ""

# Get projects
echo -e "${BLUE}Available Projects:${NC}"
response=$(curl -s "https://${SPACE}/api/v2/projects?apiKey=${API_KEY}")
projects=$(echo "$response" | jq -r '.[] | "\(.id)|\(.projectKey)|\(.name)"' 2>/dev/null)

if [ -z "$projects" ]; then
    echo -e "${RED}No projects found or unable to parse response${NC}"
    exit 1
fi

echo ""
printf "%-10s %-15s %s\n" "ID" "Key" "Name"
printf "%-10s %-15s %s\n" "----------" "---------------" "--------------------------------"

while IFS='|' read -r id key name; do
    printf "%-10s %-15s %s\n" "$id" "$key" "$name"
done <<< "$projects"

echo ""
echo -n "Enter a Project ID to get more details (or press Enter to skip): "
read project_id

if [ -n "$project_id" ]; then
    echo ""
    echo -e "${BLUE}Project Details for ID: $project_id${NC}"
    
    # Get project details
    response=$(curl -s -w "\n%{http_code}" \
        "https://${SPACE}/api/v2/projects/${project_id}?apiKey=${API_KEY}")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" = "200" ]; then
        project_name=$(echo "$body" | jq -r .name 2>/dev/null)
        project_key=$(echo "$body" | jq -r .projectKey 2>/dev/null)
        echo "  Name: $project_name"
        echo "  Key: $project_key"
        echo ""
        
        # Get issue types
        echo -e "${BLUE}Issue Types:${NC}"
        response=$(curl -s "https://${SPACE}/api/v2/projects/${project_id}/issueTypes?apiKey=${API_KEY}")
        echo "$response" | jq -r '.[] | "  ID: \(.id) - \(.name)"' 2>/dev/null || echo "  Unable to retrieve issue types"
        echo ""
        
        # Get categories
        echo -e "${BLUE}Categories:${NC}"
        response=$(curl -s "https://${SPACE}/api/v2/projects/${project_id}/categories?apiKey=${API_KEY}")
        categories=$(echo "$response" | jq -r '.[]' 2>/dev/null)
        if [ -n "$categories" ]; then
            echo "$response" | jq -r '.[] | "  ID: \(.id) - \(.name)"' 2>/dev/null
        else
            echo "  No categories defined"
        fi
        echo ""
        
        # Get custom fields
        echo -e "${BLUE}Custom Fields:${NC}"
        response=$(curl -s "https://${SPACE}/api/v2/projects/${project_id}/customFields?apiKey=${API_KEY}")
        custom_fields=$(echo "$response" | jq -r '.[]' 2>/dev/null)
        if [ -n "$custom_fields" ]; then
            echo "$response" | jq -r '.[] | "  ID: \(.id) - \(.name) (Type: \(.typeId))"' 2>/dev/null
        else
            echo "  No custom fields defined"
        fi
        echo ""
        
    else
        echo -e "${RED}Failed to get project details${NC}"
        echo "HTTP Code: $http_code"
    fi
fi

# Get priorities (global)
echo -e "${BLUE}Available Priorities (Global):${NC}"
response=$(curl -s "https://${SPACE}/api/v2/priorities?apiKey=${API_KEY}")
echo "$response" | jq -r '.[] | "  ID: \(.id) - \(.name)"' 2>/dev/null || echo "  Unable to retrieve priorities"
echo ""

# Generate environment variables
echo -e "${BLUE}Environment Variables for slack2backlog:${NC}"
echo ""
echo "# Add these to your .env file or Lambda configuration"
echo "BACKLOG_API_KEY=$API_KEY"
echo "BACKLOG_SPACE=$SPACE"
if [ -n "$project_id" ]; then
    echo "PROJECT_ID=$project_id"
    echo "ISSUE_TYPE_ID=<select from issue types above>"
else
    echo "PROJECT_ID=<select from projects above>"
    echo "ISSUE_TYPE_ID=<run script again with project ID to see issue types>"
fi
echo "PRIORITY_ID=3  # 3 is usually 'Normal/Medium'"
echo ""

# Save to file option
echo -n "Save this information to a file? (y/N): "
read save_response

if [[ "$save_response" =~ ^[Yy]$ ]]; then
    output_file="backlog-info-$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "Backlog Information Export"
        echo "Generated: $(date)"
        echo "Space: $SPACE"
        echo ""
        echo "Projects:"
        while IFS='|' read -r id key name; do
            echo "  - ID: $id, Key: $key, Name: $name"
        done <<< "$projects"
    } > "$output_file"
    
    echo -e "${GREEN}✓${NC} Information saved to: $output_file"
fi