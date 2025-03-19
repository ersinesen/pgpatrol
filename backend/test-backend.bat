REM Windows test utility for the backend

REM get an alive session id
SET SESSIOND=28299d36-70f6-4887-9f9d-ef0aea5802de

REM Resource stats
curl -s localhost:3001/api/resource-stats?sessionId=%SESSIOND%

REM Table stats
curl -s localhost:3001/api/table-stats?sessionId=%SESSIOND%