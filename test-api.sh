#!/bin/bash

# Color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Server middleware is running at port 3001
PORT=3001

# Wait for the server to start
sleep 3

# Output a header
echo -e "${BLUE}================ TESTING API ENDPOINTS =================${NC}\n"

# 1. Test connection status
echo -e "${BLUE}1. Testing: ${YELLOW}Database Connection Status${NC}"
echo -e "${BLUE}Request: ${YELLOW}GET /api/connection${NC}"
curl -s http://localhost:${PORT}/api/connection
echo -e "\n${BLUE}----------------------------------------${NC}\n"

# 2. Test database statistics
echo -e "${BLUE}2. Testing: ${YELLOW}Database Statistics${NC}"
echo -e "${BLUE}Request: ${YELLOW}GET /api/stats${NC}"
curl -s http://localhost:${PORT}/api/stats
echo -e "\n${BLUE}----------------------------------------${NC}\n"

# 3. Test resource utilization
echo -e "${BLUE}3. Testing: ${YELLOW}Resource Utilization${NC}"
echo -e "${BLUE}Request: ${YELLOW}GET /api/resource-stats${NC}"
curl -s http://localhost:${PORT}/api/resource-stats
echo -e "\n${BLUE}----------------------------------------${NC}\n"

# 4. Test query logs
echo -e "${BLUE}4. Testing: ${YELLOW}Query Logs${NC}"
echo -e "${BLUE}Request: ${YELLOW}GET /api/query-logs${NC}"
curl -s http://localhost:${PORT}/api/query-logs
echo -e "\n${BLUE}----------------------------------------${NC}\n"

# 5. Test running a query
echo -e "${BLUE}5. Testing: ${YELLOW}Run a Test Query${NC}"
echo -e "${BLUE}Request: ${YELLOW}POST /api/run-query${NC}"
curl -s -X POST -H "Content-Type: application/json" -d '{"query":"SELECT current_timestamp as time"}' http://localhost:${PORT}/api/run-query
echo -e "\n${BLUE}----------------------------------------${NC}\n"

# All tests completed
echo -e "\n${GREEN}All tests completed!${NC}"
echo -e "${YELLOW}Shutting down server...${NC}"


exit 0