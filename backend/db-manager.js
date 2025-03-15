// Database manager for multiple PostgreSQL connections
const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

const DB_CONFIG_FILE = path.join(__dirname, 'db-config.json');

class DatabaseManager {
  constructor() {
    this.connections = {};
    this.activeConnections = {};
    this.defaultConnection = null;
    this.loadConfigurations();
  }

  // Load saved database configurations
  loadConfigurations() {
    try {
      if (fs.existsSync(DB_CONFIG_FILE)) {
        const configData = fs.readFileSync(DB_CONFIG_FILE, 'utf8');
        const configs = JSON.parse(configData);
        
        // Initialize connections from saved configurations
        Object.entries(configs).forEach(([id, config]) => {
          this.connections[id] = config;
          
          // Set the first connection as default if none is set
          if (!this.defaultConnection && config.isDefault) {
            this.defaultConnection = id;
          }
        });
        
        console.log(`Loaded ${Object.keys(this.connections).length} database configurations`);
        
        // Initialize the default connection if available
        if (this.defaultConnection) {
          this.getPool(this.defaultConnection);
        } else if (Object.keys(this.connections).length > 0) {
          // Set the first connection as default if none is marked
          this.defaultConnection = Object.keys(this.connections)[0];
          this.connections[this.defaultConnection].isDefault = true;
          this.saveConfigurations();
          this.getPool(this.defaultConnection);
        }
      } else {
        // If no config file exists, create the default entry with env variable
        const defaultConfig = {
          connectionString: process.env.DATABASE_URL,
          name: 'Default Database',
          isDefault: true
        };
        
        this.connections['default'] = defaultConfig;
        this.defaultConnection = 'default';
        this.saveConfigurations();
        console.log('Created default database configuration');
      }
    } catch (error) {
      console.error('Error loading database configurations:', error);
      
      // Fallback to environment variable
      this.connections['default'] = {
        connectionString: process.env.DATABASE_URL,
        name: 'Default Database',
        isDefault: true
      };
      this.defaultConnection = 'default';
    }
  }

  // Save configurations to disk
  saveConfigurations() {
    try {
      fs.writeFileSync(DB_CONFIG_FILE, JSON.stringify(this.connections, null, 2));
    } catch (error) {
      console.error('Error saving database configurations:', error);
    }
  }

  // Test a database connection with connection string
  async testConnection(connectionString) {
    const testPool = new Pool({ connectionString });
    
    try {
      const result = await testPool.query('SELECT version()');
      await testPool.end();
      return {
        success: true,
        version: result.rows[0].version
      };
    } catch (error) {
      await testPool.end();
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  // Test a database connection with individual parameters
  async testConnectionParams(host, port, database, username, password, ssl = true) {
    const config = {
      host,
      port: parseInt(port, 10),
      database,
      user: username,
      password,
      // Set a shorter connection timeout for testing
      connectionTimeoutMillis: 5000,
      // Add SSL options
      ssl: ssl ? { rejectUnauthorized: false } : false
    };
    
    const testPool = new Pool(config);
    
    try {
      const result = await testPool.query('SELECT version()');
      await testPool.end();
      return {
        success: true,
        version: result.rows[0].version
      };
    } catch (error) {
      await testPool.end();
      return {
        success: false,
        error: error.message
      };
    }
  }

  // Register a new database connection using connection string
  async registerServer(config) {
    try {
      // Test the connection first
      const testResult = await this.testConnection(config.connectionString);
      
      if (!testResult.success) {
        return {
          success: false,
          error: testResult.error
        };
      }
      
      // Generate a unique ID if not provided
      const id = config.id || `db_${Date.now()}`;
      
      // Add to connections list
      this.connections[id] = {
        connectionString: config.connectionString,
        name: config.name || `Database ${Object.keys(this.connections).length + 1}`,
        isDefault: config.isDefault || false
      };
      
      // If this is marked as default, update other connections
      if (config.isDefault) {
        Object.keys(this.connections).forEach(connId => {
          if (connId !== id) {
            this.connections[connId].isDefault = false;
          }
        });
        
        this.defaultConnection = id;
      }
      
      // Save updated configurations
      this.saveConfigurations();
      
      return {
        success: true,
        id: id,
        name: this.connections[id].name
      };
    } catch (error) {
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  // Register a new database connection using individual parameters
  async registerServerParams(host, port, database, username, password, name, isDefault, ssl = true) {
    try {
      // Test the connection first
      const testResult = await this.testConnectionParams(host, port, database, username, password, ssl);
      
      if (!testResult.success) {
        return {
          success: false,
          error: testResult.error
        };
      }
      
      // Build connection string from parameters with SSL option if needed
      const connectionString = ssl
        ? `postgresql://${username}:${password}@${host}:${port}/${database}?sslmode=require`
        : `postgresql://${username}:${password}@${host}:${port}/${database}`;
      
      // Generate a unique ID
      const id = `db_${Date.now()}`;
      
      // Add to connections list
      this.connections[id] = {
        connectionString,
        name: name || `${database}@${host}`,
        isDefault: isDefault || false
      };
      
      // If this is marked as default, update other connections
      if (isDefault) {
        Object.keys(this.connections).forEach(connId => {
          if (connId !== id) {
            this.connections[connId].isDefault = false;
          }
        });
        
        this.defaultConnection = id;
      }
      
      // Save updated configurations
      this.saveConfigurations();
      
      return {
        success: true,
        id: id,
        name: this.connections[id].name
      };
    } catch (error) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  // Get or create a connection pool for a specific database
  getPool(id, sessionId = 'default') {
    // Use default connection if id is not specified
    const dbId = id || this.defaultConnection || 'default';
    
    // Check if connection exists
    if (!this.connections[dbId]) {
      throw new Error(`Database connection '${dbId}' not found`);
    }
    
    // Create session-specific active connections tracking
    if (!this.activeConnections[sessionId]) {
      this.activeConnections[sessionId] = {};
    }
    
    // Create or return existing pool
    if (!this.activeConnections[sessionId][dbId]) {
      this.activeConnections[sessionId][dbId] = new Pool({
        connectionString: this.connections[dbId].connectionString
      });
      
      // Initialize pg_stat_statements extension if possible
      this.activeConnections[sessionId][dbId].query(`
        CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
      `).catch(err => {
        console.warn(`Unable to enable pg_stat_statements extension for database ${dbId}:`, err.message);
      });
    }
    
    return this.activeConnections[sessionId][dbId];
  }

  // Get current active database for a session
  getCurrentDatabase(sessionId = 'default') {
    if (!this.activeConnections[sessionId]) {
      return this.defaultConnection;
    }
    
    const activeKeys = Object.keys(this.activeConnections[sessionId]);
    return activeKeys.length > 0 ? activeKeys[0] : this.defaultConnection;
  }

  // Switch active database for a session
  setActiveDatabase(dbId, sessionId = 'default') {
    if (!this.connections[dbId]) {
      throw new Error(`Database connection '${dbId}' not found`);
    }
    
    // Create a new pool for this session if it doesn't exist
    this.getPool(dbId, sessionId);
    
    return {
      id: dbId,
      name: this.connections[dbId].name
    };
  }

  // Get list of all registered database connections
  getConnections() {
    return Object.entries(this.connections).map(([id, config]) => ({
      id,
      name: config.name,
      isDefault: config.isDefault || false
    }));
  }

  // Remove a database connection
  removeConnection(id) {
    // Cannot remove default connection
    if (this.defaultConnection === id) {
      throw new Error('Cannot remove default database connection');
    }
    
    // Close any active pools for this connection
    Object.keys(this.activeConnections).forEach(sessionId => {
      if (this.activeConnections[sessionId][id]) {
        this.activeConnections[sessionId][id].end();
        delete this.activeConnections[sessionId][id];
      }
    });
    
    // Remove from connections list
    delete this.connections[id];
    this.saveConfigurations();
    
    return { success: true };
  }

  // Clean up resources
  async shutdown() {
    // Close all active connection pools
    for (const sessionId of Object.keys(this.activeConnections)) {
      for (const poolId of Object.keys(this.activeConnections[sessionId])) {
        await this.activeConnections[sessionId][poolId].end();
      }
    }
    
    this.activeConnections = {};
  }
}

module.exports = new DatabaseManager();