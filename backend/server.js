// PostgreSQL Monitor API Server with multi-database support
const express = require("express");
const cors = require("cors");
const dbManager = require("./db-manager");
const { v4: uuidv4 } = require("uuid");

// Create Express app
const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Session management
const activeSessions = {};

// Generate or validate session
function getSessionId(req) {
  const sessionId = req.headers["x-session-id"] || req.query.sessionId;

  if (sessionId && activeSessions[sessionId]) {
    // Update last activity time
    activeSessions[sessionId].lastActivity = Date.now();
    return sessionId;
  }

  // Create new session
  const newSessionId = uuidv4();
  activeSessions[newSessionId] = {
    createdAt: Date.now(),
    lastActivity: Date.now(),
  };

  return newSessionId;
}

// Clean up inactive sessions (runs every 30 minutes)
setInterval(
  () => {
    const now = Date.now();
    const SESSION_TIMEOUT = 30 * 60 * 1000; // 30 minutes

    Object.keys(activeSessions).forEach((sessionId) => {
      if (now - activeSessions[sessionId].lastActivity > SESSION_TIMEOUT) {
        delete activeSessions[sessionId];
      }
    });
  },
  30 * 60 * 1000,
);

// API Routes

// Session management
app.get("/api/session", (req, res) => {
  const sessionId = getSessionId(req);
  res.json({ sessionId });
});

// Get list of available database connections
app.get("/api/connections", (req, res) => {
  try {
    const connections = dbManager.getConnections();
    res.json(connections);
  } catch (error) {
    console.error("Error fetching connections:", error);
    res.status(500).json({ error: error.message });
  }
});

// Test a database connection using connection string
app.post("/api/test-connection", async (req, res) => {
  try {
    const { connectionString } = req.body;

    if (!connectionString) {
      return res.status(400).json({ error: "Connection string is required" });
    }

    const result = await dbManager.testConnection(connectionString);
    res.json(result);
  } catch (error) {
    console.error("Connection test error:", error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Test a database connection using individual parameters
app.post("/api/test-connection-params", async (req, res) => {
  try {
    const { host, port, database, username, password, ssl = true } = req.body;

    console.log(host, port, database, username, password, ssl);

    // Validate required parameters
    if (!host) {
      return res.status(400).json({ error: "Host is required" });
    }
    if (!port) {
      return res.status(400).json({ error: "Port is required" });
    }
    if (!database) {
      return res.status(400).json({ error: "Database name is required" });
    }
    if (!username) {
      return res.status(400).json({ error: "Username is required" });
    }
    // Password can be optional for some configurations

    const result = await dbManager.testConnectionParams(
      host,
      port,
      database,
      username,
      password,
      ssl,
    );
    res.json(result);
  } catch (error) {
    console.error("Connection test error (params):", error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Connect using a connection string
app.post("/api/connect-string", async (req, res) => {
  try {
    const { connectionString, name } = req.body;

    if (!connectionString) {
      return res.status(400).json({ error: "Connection string is required" });
    }

    // First test the connection
    const testResult = await dbManager.testConnection(connectionString);

    if (!testResult.success) {
      return res.status(400).json({
        success: false,
        error: testResult.error,
      });
    }

    // If successful, register the connection temporarily
    const connectionId = `db_${Date.now()}`;
    const sessionId = getSessionId(req);

    // Add to connections list with a name (temporary)
    dbManager.connections[connectionId] = {
      connectionString,
      name: name || `Connection ${connectionId}`,
      isDefault: false,
      temporary: true, // Mark as temporary
    };

    // Set as active for this session
    dbManager.setActiveDatabase(connectionId, sessionId);

    res.json({
      success: true,
      sessionId: sessionId,
      connectionId: connectionId,
      name: dbManager.connections[connectionId].name,
    });
  } catch (error) {
    console.error("Database connection error:", error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Connect to a database using parameters and get a session ID
app.post("/api/connect", async (req, res) => {
  try {
    const {
      host,
      port,
      database,
      username,
      password,
      name,
      ssl = true,
    } = req.body;

    console.log(
      "Connect: ",
      host,
      port,
      database,
      username,
      password,
      name,
      ssl,
    );

    // Validate required parameters
    if (!host) {
      return res.status(400).json({ error: "Host is required" });
    }
    if (!port) {
      return res.status(400).json({ error: "Port is required" });
    }
    if (!database) {
      return res.status(400).json({ error: "Database name is required" });
    }
    if (!username) {
      return res.status(400).json({ error: "Username is required" });
    }
    // Password can be optional for some configurations

    // First test the connection
    const testResult = await dbManager.testConnectionParams(
      host,
      port,
      database,
      username,
      password,
      ssl,
    );

    if (!testResult.success) {
      console.log('Test failed:', testResult.error);
      return res.status(400).json({
        success: false,
        error: testResult.error,
      });
    }

    // If successful, register the connection temporarily
    const connectionId = `db_${Date.now()}`;
    const sessionId = getSessionId(req);

    console.log("Session ID:", sessionId);

    // Build connection string from parameters with SSL option if needed
    const connectionString = ssl
      ? `postgresql://${username}:${password}@${host}:${port}/${database}?sslmode=require`
      : `postgresql://${username}:${password}@${host}:${port}/${database}`;

    // Add to connections list with a name (temporary)
    dbManager.connections[connectionId] = {
      connectionString,
      name: name || `${database}@${host}`,
      isDefault: false,
      temporary: true, // Mark as temporary
    };

    // Set as active for this session
    dbManager.setActiveDatabase(connectionId, sessionId);

    res.json({
      success: true,
      sessionId: sessionId,
      connectionId: connectionId,
      name: dbManager.connections[connectionId].name,
    });
  } catch (error) {
    console.error("Database connection error:", error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Remove a database connection
app.delete("/api/connections/:id", (req, res) => {
  try {
    const { id } = req.params;
    const result = dbManager.removeConnection(id);
    res.json(result);
  } catch (error) {
    console.error("Error removing connection:", error);
    res.status(500).json({ error: error.message });
  }
});

// Connection status
app.get("/api/connection", async (req, res) => {
  try {
    const sessionId = getSessionId(req);
    const dbId = dbManager.getCurrentDatabase(sessionId);
    const pool = dbManager.getPool(dbId, sessionId);

    const result = await pool.query("SELECT version()");
    res.json({
      status: "connected",
      version: result.rows[0].version,
      databaseId: dbId,
      databaseName: dbManager.connections[dbId].name,
    });
  } catch (err) {
    console.error("Database connection error:", err);
    res.status(500).json({
      status: "disconnected",
      error: err.message,
    });
  }
});

// Get database stats
app.get("/api/stats", async (req, res) => {
  try {
    const sessionId = getSessionId(req);
    const dbId = dbManager.getCurrentDatabase(sessionId);
    const pool = dbManager.getPool(dbId, sessionId);

    // Get database size
    const dbSizeQuery = await pool.query(`
      SELECT pg_size_pretty(pg_database_size(current_database())) as size
    `);

    // Get table count
    const tableCountQuery = await pool.query(`
      SELECT count(*) as table_count FROM information_schema.tables 
      WHERE table_schema = 'public'
    `);

    // Get active connections
    const connectionsQuery = await pool.query(`
      SELECT count(*) as connections FROM pg_stat_activity
    `);

    res.json({
      size: dbSizeQuery.rows[0].size,
      tableCount: parseInt(tableCountQuery.rows[0].table_count),
      connections: parseInt(connectionsQuery.rows[0].connections),
      databaseId: dbId,
      databaseName: dbManager.connections[dbId].name,
    });
  } catch (err) {
    console.error("Error fetching database stats:", err);
    res.status(500).json({ error: "Failed to fetch database stats" });
  }
});

// Get query logs
app.get("/api/query-logs", async (req, res) => {
  try {
    const sessionId = getSessionId(req);
    const dbId = dbManager.getCurrentDatabase(sessionId);
    const pool = dbManager.getPool(dbId, sessionId);

    try {
      // First try with pg_stat_statements
      const queryLogsResult = await pool.query(`
        SELECT 
          query,
          calls,
          total_time,
          min_time,
          max_time,
          mean_time,
          rows
        FROM pg_stat_statements
        ORDER BY total_time DESC
        LIMIT 50
      `);

      res.json(queryLogsResult.rows);
    } catch (statsErr) {
      console.warn(
        "pg_stat_statements not available, falling back to pg_stat_activity",
      );

      // Fallback to pg_stat_activity for basic query info
      const activityResult = await pool.query(`
        SELECT 
          query,
          state,
          backend_start,
          xact_start,
          query_start,
          wait_event_type,
          wait_event
        FROM pg_stat_activity
        WHERE state IS NOT NULL AND query <> '<insufficient privilege>'
        ORDER BY query_start DESC
        LIMIT 50
      `);

      // Transform into a compatible format
      const transformedResults = activityResult.rows.map((row) => ({
        query: row.query,
        state: row.state,
        duration: row.query_start
          ? Math.floor((new Date() - new Date(row.query_start)) / 1000)
          : null,
        backend_start: row.backend_start,
        wait_event_type: row.wait_event_type,
        wait_event: row.wait_event,
      }));

      res.json(transformedResults);
    }
  } catch (err) {
    console.error("Error fetching query logs:", err);
    res.status(500).json({
      error: "Failed to fetch query logs",
      details: err.message,
    });
  }
});

// Get resource utilization
app.get("/api/resource-stats", async (req, res) => {
  try {
    const sessionId = getSessionId(req);
    const dbId = dbManager.getCurrentDatabase(sessionId);
    const pool = dbManager.getPool(dbId, sessionId);

    let resourceStats = {
      cpuUsage: 0.0,
      memoryUsage: 0.0,
      diskUsage: 0.0,
      timestamp: new Date().toISOString(),
    };

    // Get CPU usage (active queries as a proxy for CPU load)
    try {
      const cpuResult = await pool.query(`
        SELECT count(*) AS active_queries
        FROM pg_stat_activity
        WHERE state = 'active' AND pid <> pg_backend_pid();
      `);

      resourceStats.cpuUsage = cpuResult.rows.length > 0
        ? parseFloat(cpuResult.rows[0].active_queries) || 0
        : 0;
    } catch (error) {
      console.warn("Error fetching CPU stats:", error.message);
    }

    // Get memory usage (calculate usage percentage from total memory)
    try {
      const memoryResult = await pool.query(`
        SELECT setting::bigint AS total_mem
        FROM pg_settings
        WHERE name = 'shared_buffers';
      `);

      if (memoryResult.rows.length > 0) {
        const totalMem = parseInt(memoryResult.rows[0].total_mem, 10);
        const usedMemResult = await pool.query(`
          SELECT sum(pg_database_size(datname)) AS used_mem
          FROM pg_database;
        `);

        if (usedMemResult.rows.length > 0) {
          const usedMem = parseInt(usedMemResult.rows[0].used_mem, 10);
          resourceStats.memoryUsage = totalMem > 0 ? (usedMem / totalMem) * 100 : 0;
        }
      }
    } catch (error) {
      console.warn("Error fetching memory stats:", error.message);
    }

    // Get disk usage (database size)
    try {
      const diskResult = await pool.query(`
        SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size,
               pg_database_size(current_database()) AS db_size_bytes;
      `);
      
      if (diskResult.rows.length > 0) {
        resourceStats.diskUsage = parseInt(diskResult.rows[0].db_size_bytes, 10);
      }
    } catch (error) {
      console.warn("Error fetching disk stats:", error.message);
    }

    res.json(resourceStats);
  } catch (error) {
    console.error("Error fetching resource stats:", error);
    res.status(500).json({ error: "Failed to fetch resource statistics" });
  }
});

// Get Table
app.get("/api/table-stats", async (req, res) => {
  try {
    const sessionId = getSessionId(req);
    const dbId = dbManager.getCurrentDatabase(sessionId);
    const pool = dbManager.getPool(dbId, sessionId);

    let resourceStats = {
      timestamp: new Date().toISOString(),
    };

    // Get tables sizes
    try {
      const sql = `SELECT schemaname || '.' || tablename AS table_name,                                             
        pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size      
        FROM                                                                                          
            pg_tables                                                                                 
        WHERE                                                                                         
            schemaname NOT IN ('pg_catalog', 'information_schema')                                    
        ORDER BY                                                                                      
            pg_total_relation_size(schemaname || '.' || tablename) DESC;`;
      const tableSizes = await pool.query(sql);
      resourceStats.tableSizes = tableSizes.rows;
    }
    catch (error) {
      console.warn("Error fetching table sizes:", error.message);
    }

    res.json(resourceStats);
  } catch (error) {
    console.error("Error fetching resource stats:", error);
    res.status(500).json({ error: "Failed to fetch resource statistics" });
  }
});

// Analysis
const queries = {
  'deadlock': "SELECT * FROM pg_stat_activity WHERE wait_event_type = 'Lock'",
  'total_tables': "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'",
  'idle': "SELECT pid, usename, query_start, state FROM pg_stat_activity WHERE state = 'idle in transaction';",
  'long_tables': "SELECT schemaname, relname, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 10;",
  'index_usage': "SELECT relname, idx_scan, idx_tup_read, idx_tup_fetch FROM pg_stat_user_indexes ORDER BY idx_scan DESC LIMIT 10;",
  'large_tables':"SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total_size FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;",
  'large_indices': "SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total_size FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;",
  'blocked_queries': "SELECT pid, usename, query_start, state, wait_event, query FROM pg_stat_activity WHERE wait_event IS NOT NULL;",
  'deadlock': "SELECT * FROM pg_stat_activity WHERE wait_event_type = 'Lock';",
  'max_connections': "SHOW max_connections;",
  'high_dead_tuple': "SELECT relname, n_dead_tup, last_autovacuum FROM pg_stat_user_tables WHERE n_dead_tup > 1000 ORDER BY n_dead_tup DESC;",
  'vacuum_progress': "SELECT * FROM pg_stat_progress_vacuum;",
  'frequent_queries': "SELECT query, calls FROM pg_stat_statements ORDER BY calls DESC LIMIT 10;",
  'index_bloat': "SELECT schemaname, relname, indexrelname, idx_blks_read, idx_blks_hit, idx_blks_read + idx_blks_hit as total_reads, CASE WHEN (idx_blks_read + idx_blks_hit) = 0 THEN 0 ELSE idx_blks_read / (idx_blks_read + idx_blks_hit) END as read_pct FROM pg_statio_user_indexes ORDER BY total_reads DESC LIMIT 10;",  
  'slow_queries': "SELECT query, total_exec_time, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;",
  'index_hit_rate': "SELECT CASE WHEN sum(seq_scan + idx_scan) = 0 THEN 0 ELSE sum(idx_scan) / sum(seq_scan + idx_scan) END AS index_hit_rate FROM pg_stat_user_tables;",
  'background_worker': "SELECT * FROM pg_stat_activity WHERE backend_type != 'client backend';",
  'active_locks': "SELECT pid, locktype, relation::regclass, mode, granted FROM pg_locks WHERE NOT granted;",
};

app.get("/api/analyze", async (req, res) => {
  try {
    const sessionId = getSessionId(req);
    const dbId = dbManager.getCurrentDatabase(sessionId);
    const pool = dbManager.getPool(dbId, sessionId);

    const key = req.query.key;
    if (!queries[key]) {
      return res.status(404).json({ error: "Key not found" });
    }
    const sql = queries[key];
    console.log(sql);
    const ret = await pool.query(sql);

    let result = {
      timestamp: new Date().toISOString(),
      key: key,
      count: ret.rows.length,
      data: ret.rows,
      columns: ret.fields.map(f => f.name),
    };

    res.json(result);

  } catch (error) {
    console.error("Error running analyze:", error);
    res.status(500).json({ error: "Failed to run analyze" });
  }
});

// Start the server
const PORT = process.env.PORT || 3001;
const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`API server listening on port ${PORT}`);
});

// Handle process termination
process.on("SIGINT", async () => {
  console.log("Shutting down API server...");
  await dbManager.shutdown();
  server.close();
  process.exit();
});

process.on("SIGTERM", async () => {
  console.log("Shutting down API server...");
  await dbManager.shutdown();
  server.close();
  process.exit();
});
