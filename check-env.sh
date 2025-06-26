#!/bin/bash

echo "=== slack2backlog Development Environment Check ==="
echo

# 色の定義
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# チェック関数
check_command() {
    if command -v $1 &> /dev/null; then
        if [ "$1" = "pytest" ]; then
            version=$(pytest --version 2>&1 | tail -n1)
        elif [ "$1" = "gh" ]; then
            version=$(gh --version | head -n1)
        else
            version=$($2 2>&1)
        fi
        echo -e "${GREEN}✓${NC} $1: $version"
    else
        echo -e "${RED}✗${NC} $1: Not installed"
    fi
}

# 各ツールのチェック
check_command "node" "node --version"
check_command "npm" "npm --version"
check_command "python3" "python3 --version"
check_command "pip" "pip --version"
check_command "git" "git --version"
check_command "aws" "aws --version | head -n1"
check_command "sam" "sam --version"
check_command "cdk" "cdk --version"
check_command "jest" "jest --version"
check_command "pytest" "pytest --version"
check_command "gh" "gh --version"
check_command "jq" "jq --version"
check_command "yq" "yq --version"

echo
echo "=== Check Complete ==="

# GitHub CLI詳細確認
echo
echo "=== GitHub CLI Authentication Check ==="
if command -v gh &> /dev/null; then
    echo "Checking GitHub authentication status..."
    gh auth status
    echo
    echo "Current repository:"
    if [ -d .git ]; then
        gh repo view --json name,owner,url 2>/dev/null | jq -r '"\(.owner.login)/\(.name) - \(.url)"' || echo "Not a GitHub repository or gh not configured"
    else
        echo "Not in a git repository"
    fi
    echo
    echo "Testing issue access:"
    gh issue list --limit 1 --state all &>/dev/null && echo -e "${GREEN}✓${NC} Issue operations: Available" || echo -e "${RED}✗${NC} Issue operations: Not available"
else
    echo -e "${RED}✗${NC} GitHub CLI not installed"
fi

echo
echo "=== Final Check Complete ==="