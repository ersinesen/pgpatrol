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

// Set active database for session
app.post("/api/set-active-connection", (req, res) => {
  try {
    const { connectionId } = req.body;
    const sessionId = getSessionId(req);

    const result = dbManager.setActiveDatabase(connectionId, sessionId);
    res.json(result);
  } catch (error) {
    console.error("Error setting active connection:", error);
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
      cpu: {},
      memory: {},
      io: {},
      timestamp: new Date().toISOString(),
    };

    // Get CPU proxy data (active query time)
    try {
      const cpuResult = await pool.query(`
        SELECT extract(epoch from (now() - query_start)) as active_query_time
        FROM pg_stat_activity 
        WHERE state = 'active' AND pid <> pg_backend_pid()
        ORDER BY active_query_time DESC
        LIMIT 1
      `);

      resourceStats.cpu.active_query_time =
        cpuResult.rows.length > 0
          ? parseFloat(cpuResult.rows[0].active_query_time) || 0
          : 0;
    } catch (error) {
      console.warn("Error fetching CPU stats:", error.message);
      resourceStats.cpu.active_query_time = 0;
    }

    // Get memory configuration
    try {
      const memoryResult = await pool.query(`
        SELECT name, setting, unit 
        FROM pg_settings 
        WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem')
      `);

      memoryResult.rows.forEach((row) => {
        resourceStats.memory[row.name] = parseInt(row.setting, 10);
      });
    } catch (error) {
      console.warn("Error fetching memory stats:", error.message);
      resourceStats.memory = {
        shared_buffers: 0,
        work_mem: 0,
        maintenance_work_mem: 0,
      };
    }

    // Get I/O statistics
    try {
      const ioResult = await pool.query(`
        SELECT 
          sum(heap_blks_read) as heap_read,
          sum(heap_blks_hit) as heap_hit,
          sum(idx_blks_read) as idx_read,
          sum(idx_blks_hit) as idx_hit
        FROM pg_statio_user_tables
      `);

      if (ioResult.rows.length > 0) {
        const row = ioResult.rows[0];
        resourceStats.io = {
          heap_read: parseInt(row.heap_read) || 0,
          heap_hit: parseInt(row.heap_hit) || 0,
          idx_read: parseInt(row.idx_read) || 0,
          idx_hit: parseInt(row.idx_hit) || 0,
        };

        // Calculate cache hit ratio
        const totalReads =
          resourceStats.io.heap_read + resourceStats.io.idx_read;
        const totalHits = resourceStats.io.heap_hit + resourceStats.io.idx_hit;
        const totalIO = totalReads + totalHits;

        resourceStats.io.cache_hit_ratio =
          totalIO > 0 ? ((totalHits / totalIO) * 100).toFixed(2) : 0;
      }
    } catch (error) {
      console.warn("Error fetching I/O stats:", error.message);
      resourceStats.io = {
        heap_read: 0,
        heap_hit: 0,
        idx_read: 0,
        idx_hit: 0,
        cache_hit_ratio: 0,
      };
    }

    res.json(resourceStats);
  } catch (error) {
    console.error("Error fetching resource stats:", error);
    res.status(500).json({ error: "Failed to fetch resource statistics" });
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
