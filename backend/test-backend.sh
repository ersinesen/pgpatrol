#!/bin/bash

# PostgreSQL Monitor API Testing Script
# This script tests all available API endpoints with sample data

# Color codes for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# API base URL
API_URL="http://localhost:3001/api"

# Neon PostgreSQL test connection details
HOST="ep-hidden-cell-a6sicgzm.us-west-2.aws.neon.tech"
PORT="5432"
DATABASE="neondb"
USERNAME="neondb_owner"
PASSWORD="npg_MFngW07NVOTC"

# Function to print section header
print_header() {
  echo -e "\n${BLUE}======================================================${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}======================================================${NC}\n"
}

# Function to check if server is running
check_server() {
  if ! curl -s "$API_URL/connections" > /dev/null; then
    echo -e "${RED}Error: Server is not running. Please start the server with 'node server.js'${NC}"
    exit 1
  fi
}

# Start by checking if server is running
check_server

# Test 1: Get all connections
print_header "Testing GET /api/connections"
curl -s "$API_URL/connections" | jq .

# Test 2: Test connection with parameters
print_header "Testing POST /api/test-connection-params"
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"host\":\"$HOST\", \"port\":\"$PORT\", \"database\":\"$DATABASE\", \"username\":\"$USERNAME\", \"password\":\"$PASSWORD\", \"ssl\":true}" \
  "$API_URL/test-connection-params" | jq .

# Test 3: Connect using parameters (new approach)
print_header "Testing POST /api/connect"
CONNECT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"host\":\"$HOST\", \"port\":\"$PORT\", \"database\":\"$DATABASE\", \"username\":\"$USERNAME\", \"password\":\"$PASSWORD\", \"name\":\"Test Connection\", \"ssl\":true}" \
  "$API_URL/connect")

echo "$CONNECT_RESPONSE" | jq .

# Extract session ID and connection ID for subsequent requests
SESSION_ID=$(echo "$CONNECT_RESPONSE" | jq -r '.sessionId')
CONNECTION_ID=$(echo "$CONNECT_RESPONSE" | jq -r '.connectionId')

echo -e "${YELLOW}Connected with Session ID: $SESSION_ID${NC}"
echo -e "${YELLOW}Connection ID: $CONNECTION_ID${NC}"

# Test 4: Get connection status (with session)
print_header "Testing GET /api/connection (with session ID)"
curl -s -H "X-Session-ID: $SESSION_ID" "$API_URL/connection" | jq .

# Test 5: Get database stats
print_header "Testing GET /api/stats (with session ID)"
curl -s -H "X-Session-ID: $SESSION_ID" "$API_URL/stats" | jq .

# Test 6: Get resource stats
print_header "Testing GET /api/resource-stats (with session ID)"
curl -s -H "X-Session-ID: $SESSION_ID" "$API_URL/resource-stats" | jq .

# Test 7: Get query logs
print_header "Testing GET /api/query-logs (with session ID)"
curl -s -H "X-Session-ID: $SESSION_ID" "$API_URL/query-logs" | jq .

# Test 8: Test connection with connection string
print_header "Testing POST /api/connect-string"
CONNECTION_STRING="postgresql://$USERNAME:$PASSWORD@$HOST:$PORT/$DATABASE?sslmode=require"
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"connectionString\":\"$CONNECTION_STRING\", \"name\":\"String Connection Test\"}" \
  "$API_URL/connect-string" | jq .

echo -e "\n${GREEN}✓ All tests completed${NC}"