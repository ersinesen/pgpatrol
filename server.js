const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 5000; // Use port 5000 for Replit

// Middleware
app.use(cors());
app.use(express.json());

// Serve Flutter web app static files from frontend directory
app.use(express.static(path.join(__dirname, 'frontend')));

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

// Test database connection
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('Database connection error:', err.stack);
  } else {
    console.log('Database connected successfully. Current time:', res.rows[0].now);
  }
});

// Enable pg_stat_statements extension if it's not already enabled
pool.query(`
  CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
`).catch(err => {
  console.warn('Unable to enable pg_stat_statements extension:', err.message);
  console.warn('Some query statistics may not be available');
});

// API Routes

// Get database stats
app.get('/api/stats', async (req, res) => {
  try {
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
      connections: parseInt(connectionsQuery.rows[0].connections)
    });
  } catch (err) {
    console.error('Error fetching database stats:', err);
    res.status(500).json({ error: 'Failed to fetch database stats' });
  }
});

// Get query logs
app.get('/api/query-logs', async (req, res) => {
  try {
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
  } catch (err) {
    console.error('Error fetching query logs:', err);
    res.status(500).json({ error: 'Failed to fetch query logs. Make sure pg_stat_statements extension is enabled.' });
  }
});

// Get resource utilization
app.get('/api/resource-stats', async (req, res) => {
  try {
    // CPU usage (from pg_stat_activity)
    const cpuQuery = await pool.query(`
      SELECT SUM(EXTRACT(EPOCH FROM (now() - query_start))) as total_cpu_time
      FROM pg_stat_activity
      WHERE state = 'active' AND query != '<IDLE>' AND query NOT ILIKE '%pg_stat_activity%'
    `);
    
    // Memory usage
    const memoryQuery = await pool.query(`
      SELECT SUM(total_bytes) as total_memory, SUM(free_bytes) as free_memory
      FROM (
        SELECT sum(block_size*total_blocks) as total_bytes, 
               sum(block_size*free_blocks) as free_bytes
        FROM pg_catalog.pg_freespace
      ) as x
    `);
    
    // Disk I/O
    const diskQuery = await pool.query(`
      SELECT sum(heap_blks_read) as heap_read,
             sum(heap_blks_hit) as heap_hit,
             sum(idx_blks_read) as idx_read,
             sum(idx_blks_hit) as idx_hit
      FROM pg_statio_user_tables
    `);
    
    res.json({
      cpu: {
        active_query_time: parseFloat(cpuQuery.rows[0].total_cpu_time || 0)
      },
      memory: {
        total: parseInt(memoryQuery.rows[0].total_memory || 0),
        free: parseInt(memoryQuery.rows[0].free_memory || 0),
        used: parseInt((memoryQuery.rows[0].total_memory || 0) - (memoryQuery.rows[0].free_memory || 0))
      },
      disk: {
        heap_read: parseInt(diskQuery.rows[0].heap_read || 0),
        heap_hit: parseInt(diskQuery.rows[0].heap_hit || 0),
        idx_read: parseInt(diskQuery.rows[0].idx_read || 0),
        idx_hit: parseInt(diskQuery.rows[0].idx_hit || 0)
      }
    });
  } catch (err) {
    console.error('Error fetching resource stats:', err);
    res.status(500).json({ error: 'Failed to fetch resource statistics' });
  }
});

// Connection status
app.get('/api/connection', async (req, res) => {
  try {
    const result = await pool.query('SELECT version()');
    res.json({
      status: 'connected',
      version: result.rows[0].version
    });
  } catch (err) {
    console.error('Database connection error:', err);
    res.status(500).json({ 
      status: 'disconnected',
      error: err.message
    });
  }
});

// Execute custom query
app.post('/api/run-query', async (req, res) => {
  try {
    const { query } = req.body;
    
    if (!query) {
      return res.status(400).json({ error: 'Query parameter is required' });
    }
    
    // Add safety checks to prevent harmful queries
    const lowercaseQuery = query.toLowerCase();
    if (
      lowercaseQuery.includes('drop table') || 
      lowercaseQuery.includes('drop database') ||
      lowercaseQuery.includes('truncate table') ||
      lowercaseQuery.includes('delete from') ||
      lowercaseQuery.includes('update ')
    ) {
      return res.status(403).json({ 
        error: 'Potentially harmful query detected. For safety reasons, DELETE, DROP, TRUNCATE, and UPDATE operations are not allowed through this API.'
      });
    }
    
    const startTime = Date.now();
    const result = await pool.query(query);
    const executionTime = (Date.now() - startTime) / 1000;
    
    console.log(`Query executed in ${executionTime}s:`, query);
    
    res.json(result.rows);
  } catch (err) {
    console.error('Error executing query:', err);
    res.status(500).json({ error: `Failed to execute query: ${err.message}` });
  }
});

// SPA fallback - this ensures all routes are handled by the Flutter app
app.get('*', (req, res) => {
  // Exclude API routes
  if (!req.url.startsWith('/api/')) {
    res.sendFile(path.join(__dirname, 'frontend/index.html'));
  }
});

// Start the server with specific console logs for Replit to detect the port
const server = app.listen(PORT, '0.0.0.0', () => {
  // These specific log messages help Replit detect the port properly
  console.log(`Server listening on port ${PORT}`);
  console.log(`Web server started`);
  console.log(`Listening on port ${PORT}`);
  console.log(`Server running at: http://0.0.0.0:${PORT}`);
});