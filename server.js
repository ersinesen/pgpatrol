// PostgreSQL Monitor API Server
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

// Create Express app
const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Connect to PostgreSQL
const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

// Test database connection
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('Database connection error:', err.message);
  } else {
    console.log('Database connected successfully. Current time:', res.rows[0].now);
  }
});

// API Routes

// 1. Database Connection Status
app.get('/connection', async (req, res) => {
  try {
    const result = await pool.query('SELECT version()');
    res.json({
      status: 'connected',
      version: result.rows[0].version
    });
  } catch (error) {
    console.error('Connection check error:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// 2. Database Statistics
app.get('/stats', async (req, res) => {
  try {
    // Get database size
    const sizeResult = await pool.query(`
      SELECT pg_size_pretty(pg_database_size(current_database())) AS size
    `);
    
    // Get table count
    const tableCountResult = await pool.query(`
      SELECT count(*) AS table_count 
      FROM information_schema.tables 
      WHERE table_schema = 'public'
    `);
    
    // Get connection count
    const connectionCountResult = await pool.query(`
      SELECT count(*) AS connections 
      FROM pg_stat_activity
    `);
    
    res.json({
      size: sizeResult.rows[0].size,
      tableCount: parseInt(tableCountResult.rows[0].table_count, 10),
      connections: parseInt(connectionCountResult.rows[0].connections, 10)
    });
  } catch (error) {
    console.error('Database stats error:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// 3. Resource Utilization Stats
app.get('/resource-stats', async (req, res) => {
  try {
    // Try to get detailed resource information
    let resourceStats = {
      cpu: {},
      memory: {},
      cache: {},
      disk: {}
    };
    
    try {
      // Query active backend time (CPU proxy)
      const cpuResult = await pool.query(`
        SELECT extract(epoch from (now() - query_start)) as active_query_time
        FROM pg_stat_activity 
        WHERE state = 'active' AND pid <> pg_backend_pid()
        ORDER BY active_query_time DESC
        LIMIT 1
      `);
      
      if (cpuResult.rows.length > 0) {
        resourceStats.cpu.active_query_time = parseFloat(cpuResult.rows[0].active_query_time) || 0;
      } else {
        resourceStats.cpu.active_query_time = 0;
      }
    } catch (error) {
      console.warn('Error fetching CPU stats:', error.message);
      resourceStats.cpu.active_query_time = 0;
    }
    
    try {
      // Get memory usage statistics
      const memoryResult = await pool.query(`
        SELECT name, setting, unit 
        FROM pg_settings 
        WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem')
      `);
      
      memoryResult.rows.forEach(row => {
        resourceStats.memory[row.name] = parseInt(row.setting, 10);
      });
      
    } catch (error) {
      console.warn('Error fetching memory stats:', error.message);
      resourceStats.memory = {
        shared_buffers: 16384,
        work_mem: 4096,
        maintenance_work_mem: 65536
      };
    }
    
    try {
      // Get cache hit ratio
      const cacheResult = await pool.query(`
        SELECT 
          sum(heap_blks_read) as blocks_read,
          sum(heap_blks_hit) as blocks_hit,
          sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read) + 0.001) * 100 as hit_ratio
        FROM pg_statio_user_tables
      `);
      
      if (cacheResult.rows.length > 0) {
        resourceStats.cache.blocks_read = parseInt(cacheResult.rows[0].blocks_read, 10) || 0;
        resourceStats.cache.blocks_hit = parseInt(cacheResult.rows[0].blocks_hit, 10) || 0;
        
        // Fix for hit_ratio - handle when it's null or not a number
        const hitRatio = parseFloat(cacheResult.rows[0].hit_ratio);
        resourceStats.cache.hit_ratio = isNaN(hitRatio) ? "0.00" : hitRatio.toFixed(2);
      }
    } catch (error) {
      console.warn('Error fetching cache stats:', error.message);
      resourceStats.cache = {
        blocks_read: 0,
        blocks_hit: 0,
        hit_ratio: "0.00"
      };
    }
    
    try {
      // Get disk I/O stats
      const diskResult = await pool.query(`
        SELECT 
          sum(heap_blks_read) as heap_read,
          sum(heap_blks_hit) as heap_hit,
          sum(idx_blks_read) as idx_read,
          sum(idx_blks_hit) as idx_hit
        FROM pg_statio_user_tables
      `);
      
      if (diskResult.rows.length > 0) {
        resourceStats.disk.heap_read = parseInt(diskResult.rows[0].heap_read, 10) || 0;
        resourceStats.disk.heap_hit = parseInt(diskResult.rows[0].heap_hit, 10) || 0;
        resourceStats.disk.idx_read = parseInt(diskResult.rows[0].idx_read, 10) || 0;
        resourceStats.disk.idx_hit = parseInt(diskResult.rows[0].idx_hit, 10) || 0;
      }
    } catch (error) {
      console.warn('Error fetching disk I/O stats:', error.message);
      resourceStats.disk = {
        heap_read: 0,
        heap_hit: 0,
        idx_read: 0,
        idx_hit: 0
      };
    }
    
    res.json(resourceStats);
  } catch (error) {
    console.error('Resource stats error:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// 4. Query Logs
app.get('/query-logs', async (req, res) => {
  try {
    // Try pg_stat_statements first (if it's available)
    try {
      const logsResult = await pool.query(`
        SELECT 
          query, 
          calls,
          total_time,
          min_time,
          max_time,
          mean_time,
          rows,
          CURRENT_TIMESTAMP AS timestamp
        FROM pg_stat_statements
        WHERE query != '<insufficient privilege>'
        ORDER BY total_time DESC
        LIMIT 20
      `);
      
      if (logsResult.rows && logsResult.rows.length > 0) {
        res.json(logsResult.rows);
        return;
      }
    } catch (error) {
      console.warn('pg_stat_statements not available, falling back to pg_stat_activity');
    }
    
    // Fall back to pg_stat_activity if pg_stat_statements is not available
    const activityResult = await pool.query(`
      SELECT 
        query,
        state,
        EXTRACT(EPOCH FROM (now() - query_start)) as duration,
        COALESCE(application_name, 'unknown') as application,
        COALESCE(usename, 'postgres') as username,
        COALESCE(client_addr::text, 'localhost') as client_addr,
        query_start as timestamp
      FROM pg_stat_activity
      WHERE query IS NOT NULL 
        AND query != '<insufficient privilege>'
        AND query NOT LIKE '%pg_stat_activity%'
      ORDER BY query_start DESC NULLS LAST
      LIMIT 20
    `);
    
    res.json(activityResult.rows);
  } catch (error) {
    console.error('Query logs error:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// 5. Run Custom Query
app.post('/run-query', async (req, res) => {
  try {
    const { query } = req.body;
    
    if (!query) {
      return res.status(400).json({
        status: 'error',
        message: 'No query provided'
      });
    }
    
    // Restrict to SELECT queries only for security
    if (!query.trim().toLowerCase().startsWith('select')) {
      return res.status(403).json({
        status: 'error',
        message: 'Only SELECT queries are allowed'
      });
    }
    
    const startTime = Date.now();
    const result = await pool.query(query);
    const executionTime = ((Date.now() - startTime) / 1000).toFixed(3);
    
    console.log(`Query executed in ${executionTime}s: ${query}`);
    res.json(result.rows);
  } catch (error) {
    console.error('Query execution error:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// Start server
const PORT = process.env.API_PORT || 3001;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`API server listening on port ${PORT}`);
});