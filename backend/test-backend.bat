REM Windows test utility for the backend

REM get an alive session id
SET SESSIOND=29c0c2ed-68c4-4835-8552-4feaaa0841e0

REM Resource stats
curl -s localhost:3001/api/resource-stats?sessionId=%SESSIOND%

REM Table stats
curl -s localhost:3001/api/table-stats?sessionId=%SESSIOND%