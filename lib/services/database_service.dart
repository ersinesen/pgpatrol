import 'dart:async';
import 'dart:io';
import 'package:postgres/postgres.dart';
import '../models/connection_status.dart';
import '../models/database_stats.dart';
import '../models/query_log.dart';
import '../models/resource_stats.dart';
import '../models/server_connection.dart';
import 'connection_manager.dart';

/// Direct DatabaseService implementation that connects directly to PostgreSQL
/// without using Node.js API. For desktop platforms.
class DatabaseService {
  // Connection management
  PostgreSQLConnection? _connection;
  String? _connectionName;
  
  // Flag to track if the service is connected to the database
  bool _isConnected = false;
  Timer? _statsRefreshTimer;
  Timer? _resourceStatsTimer;
  
  // Stream controllers for real-time updates
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _databaseStatsController = StreamController<DatabaseStats>.broadcast();
  final _queryLogsController = StreamController<List<QueryLog>>.broadcast();
  final _resourceStatsController = StreamController<ResourceStats>.broadcast();
  
  // Streams
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  Stream<DatabaseStats> get databaseStatsStream => _databaseStatsController.stream;
  Stream<List<QueryLog>> get queryLogsStream => _queryLogsController.stream;
  Stream<ResourceStats> get resourceStatsStream => _resourceStatsController.stream;
  
  // Latest data
  ConnectionStatus _latestConnectionStatus = ConnectionStatus.initial();
  DatabaseStats _latestDatabaseStats = DatabaseStats.initial();
  List<QueryLog> _latestQueryLogs = [];
  ResourceStats _latestResourceStats = ResourceStats.initial();
  
  // Constructor - Use as a singleton
  static final DatabaseService _instance = DatabaseService._internal();
  
  factory DatabaseService() {
    return _instance;
  }
  
  DatabaseService._internal() {
    // Initialize as needed
  }
  
  /// Connect to a PostgreSQL database using the connection parameters
  Future<bool> connect(ServerConnection connection) async {
    try {
      print('DatabaseService: Connecting to ${connection.name} (ID: ${connection.id})');
      
      // Create a new postgres connection
      _connection = PostgreSQLConnection(
        connection.host,
        connection.port,
        connection.database,
        username: connection.username,
        password: connection.password,
        useSSL: true, // Enable SSL by default
      );
      
      // Try to connect
      await _connection!.open();
      
      // Store connection information
      _connectionName = connection.name;
      _isConnected = true;
      
      print('DatabaseService: Connected successfully to ${connection.name}');
      
      // Update connection status
      _updateConnectionStatus(
        ConnectionStatus(
          isConnected: true,
          serverVersion: 'PostgreSQL', // Will be updated with first status check
          activeConnections: 0,
          maxConnections: 100,
          lastChecked: DateTime.now(),
          statusMessage: 'Connected to ${connection.name}',
          connectionName: connection.name,
        ),
      );
      
      // Update the connection manager to set this connection as active
      ConnectionManager().setActiveConnection(connection.id);
      
      // Initialize data fetching
      await _checkConnectionStatus();
      if (_isConnected) {
        await _fetchDatabaseStats();
        await _fetchResourceStats();
        await _fetchQueryLogs();
        _startPeriodicUpdates();
      }
      
      return true;
    } catch (e) {
      _isConnected = false;
      _updateConnectionStatus(
        ConnectionStatus.initial().copyWith(
          statusMessage: 'Connection error: ${e.toString()}',
        ),
      );
      return false;
    }
  }
  
  /// Disconnect from the currently connected database
  Future<bool> disconnect() async {
    // If we're not connected, return immediately
    if (!_isConnected || _connection == null) {
      return true;
    }
    
    try {
      print('DatabaseService: Disconnecting from database');
      
      // Update connection status to "disconnecting"
      _updateConnectionStatus(
        ConnectionStatus(
          isConnected: true,
          statusMessage: 'Disconnecting...',
          serverVersion: _latestConnectionStatus.serverVersion,
          activeConnections: 0,
          maxConnections: 0,
          lastChecked: DateTime.now(),
          connectionName: _connectionName ?? '',
        ),
      );
      
      // Stop refresh timers
      _stopPeriodicUpdates();
      
      // Close the connection
      await _connection!.close();
      
      // Reset connection state
      _isConnected = false;
      _connection = null;
      _connectionName = null;
      
      // Update connection status to "disconnected"
      _updateConnectionStatus(
        ConnectionStatus.initial().copyWith(
          statusMessage: 'Disconnected',
        ),
      );
      
      print('DatabaseService: Disconnected successfully');
      
      // Note: We still maintain the active connection in the connection manager
      // This allows the dashboard to show the active connection even when disconnected
      
      return true;
    } catch (e) {
      print('Error disconnecting: ${e.toString()}');
      return false;
    }
  }
  
  /// Test a connection without fully connecting
  Future<Map<String, dynamic>> testConnection(ServerConnection connection) async {
    try {
      print('Testing connection to ${connection.host}:${connection.port}/${connection.database} as ${connection.username}');
      
      // Create a test connection
      final testConnection = PostgreSQLConnection(
        connection.host,
        connection.port,
        connection.database,
        username: connection.username,
        password: connection.password,
        useSSL: true, // Enable SSL by default
      );
      
      // Try to connect with a timeout
      await testConnection.open().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Connection timed out');
        },
      );
      
      // Run a simple query to verify the connection
      final results = await testConnection.query('SELECT version()');
      final versionString = results.isNotEmpty ? results[0][0].toString() : 'Unknown';
      
      // Close the test connection
      await testConnection.close();
      
      return {
        'success': true,
        'message': 'Connection successful: $versionString',
        'version': versionString,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection test failed: ${e.toString()}',
      };
    }
  }
  
  Future<void> _checkConnectionStatus() async {
    if (_connection == null || !_isConnected) {
      _isConnected = false;
      _updateConnectionStatus(
        ConnectionStatus.initial().copyWith(
          statusMessage: 'No active connection',
        ),
      );
      return;
    }
    
    try {
      // Check server version
      final versionResults = await _connection!.query('SELECT version()');
      final versionString = versionResults.isNotEmpty 
          ? versionResults[0][0].toString() 
          : 'PostgreSQL';
      
      // Get active connection count
      final connectionResults = await _connection!.query(
        'SELECT count(*) FROM pg_stat_activity'
      );
      final connectionCount = connectionResults.isNotEmpty 
          ? connectionResults[0][0] as int 
          : 0;
      
      // Get max connections
      final maxConnectionResults = await _connection!.query(
        'SHOW max_connections'
      );
      final maxConnections = maxConnectionResults.isNotEmpty 
          ? int.tryParse(maxConnectionResults[0][0].toString()) ?? 100 
          : 100;
      
      _updateConnectionStatus(
        ConnectionStatus(
          isConnected: true,
          serverVersion: versionString,
          activeConnections: connectionCount,
          maxConnections: maxConnections,
          lastChecked: DateTime.now(),
          statusMessage: 'Connected to $_connectionName',
          connectionName: _connectionName ?? 'Database',
        ),
      );
      
      // If connected, start periodic updates if not already running
      if (_isConnected && _statsRefreshTimer == null) {
        _startPeriodicUpdates();
      }
    } catch (e) {
      print('Error checking connection status: ${e.toString()}');
      
      // Check if the connection was lost
      if (e is PostgreSQLException || e is SocketException) {
        _isConnected = false;
        _connection = null;
        
        _updateConnectionStatus(
          ConnectionStatus.initial().copyWith(
            statusMessage: 'Connection lost: ${e.toString()}',
          ),
        );
        
        // Stop the timers
        _stopPeriodicUpdates();
      }
    }
  }
  
  void _startPeriodicUpdates() {
    // Stop existing timers if running
    _statsRefreshTimer?.cancel();
    _resourceStatsTimer?.cancel();
    
    // Fetch stats every 10 seconds
    _statsRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_isConnected) {
        await _fetchDatabaseStats();
        await _fetchQueryLogs();
      } else {
        await _checkConnectionStatus();
      }
    });
    
    // Fetch resource stats every 2 seconds
    _resourceStatsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_isConnected) {
        await _fetchResourceStats();
      }
    });
  }
  
  Future<void> _fetchDatabaseStats() async {
    if (!_isConnected || _connection == null) return;
    
    try {
      // Get database size
      final sizeResults = await _connection!.query(
        "SELECT pg_size_pretty(pg_database_size(current_database()))"
      );
      final sizeString = sizeResults.isNotEmpty 
          ? sizeResults[0][0].toString() 
          : '0 kB';
      
      // Get table count
      final tableResults = await _connection!.query(
        "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema')"
      );
      final tableCount = tableResults.isNotEmpty 
          ? tableResults[0][0] as int 
          : 0;
      
      // Get database list with sizes
      final dbListResults = await _connection!.query(
        "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datistemplate = false ORDER BY pg_database_size(datname) DESC"
      );
      
      final databases = <DatabaseInfo>[];
      
      for (final row in dbListResults) {
        final dbName = row[0].toString();
        final dbSizeString = row[1].toString();
        
        // Get table count for this database
        int dbTables = 0;
        if (dbName == _connection!.databaseName) {
          dbTables = tableCount;
        }
        
        databases.add(DatabaseInfo(
          name: dbName,
          sizeInMB: _parseSize(dbSizeString),
          tables: dbTables,
          activeConnections: 0, // We don't have this information per database
        ));
      }
      
      final stats = DatabaseStats(
        totalDatabases: databases.length,
        totalTables: tableCount,
        dbSize: _parseSize(sizeString),
        databases: databases,
        lastUpdated: DateTime.now(),
      );
      
      _latestDatabaseStats = stats;
      _databaseStatsController.add(stats);
    } catch (e) {
      print('Error fetching database stats: $e');
    }
  }
  
  Future<void> _fetchResourceStats() async {
    if (!_isConnected || _connection == null) return;
    
    try {
      final now = DateTime.now();
      
      // We don't have direct CPU usage in PostgreSQL, so we'll use active queries as a proxy
      final cpuResults = await _connection!.query(
        "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND pid <> pg_backend_pid()"
      );
      final activeQueries = cpuResults.isNotEmpty 
          ? cpuResults[0][0] as int 
          : 0;
      
      // Calculate a percentage based on active queries (this is just an approximation)
      final cpuUsage = activeQueries * 5.0; // Each query uses ~5% CPU (arbitrary)
      
      // Get memory stats from PostgreSQL
      final memResults = await _connection!.query(
        "SELECT setting FROM pg_settings WHERE name = 'shared_buffers'"
      );
      final sharedBuffersString = memResults.isNotEmpty 
          ? memResults[0][0].toString() 
          : '8MB';
      
      // Parse shared_buffers and convert to MB
      final memoryUsage = _parseSize(sharedBuffersString);
      
      // Get disk stats - we'll use database size as a proxy for disk usage
      final diskSize = _latestDatabaseStats.dbSize;
      final diskPercent = diskSize / 100.0; // Convert to percentage (assuming 100MB = 100%)
      
      // Update historical data (keep the last 30 points)
      final newCpuHistory = List<TimeSeriesData>.from(_latestResourceStats.historicalCpuUsage);
      final newMemoryHistory = List<TimeSeriesData>.from(_latestResourceStats.historicalMemoryUsage);
      final newDiskHistory = List<TimeSeriesData>.from(_latestResourceStats.historicalDiskUsage);
      
      newCpuHistory.add(TimeSeriesData(time: now, value: cpuUsage));
      newMemoryHistory.add(TimeSeriesData(time: now, value: memoryUsage));
      newDiskHistory.add(TimeSeriesData(time: now, value: diskPercent));
      
      // Keep only the most recent 30 data points
      if (newCpuHistory.length > 30) newCpuHistory.removeAt(0);
      if (newMemoryHistory.length > 30) newMemoryHistory.removeAt(0);
      if (newDiskHistory.length > 30) newDiskHistory.removeAt(0);
      
      final stats = ResourceStats(
        cpuUsage: cpuUsage,
        memoryUsage: memoryUsage,
        diskUsage: diskPercent,
        historicalCpuUsage: newCpuHistory,
        historicalMemoryUsage: newMemoryHistory,
        historicalDiskUsage: newDiskHistory,
        timestamp: now,
      );
      
      _latestResourceStats = stats;
      _resourceStatsController.add(stats);
    } catch (e) {
      print('Error fetching resource stats: $e');
    }
  }
  
  Future<void> _fetchQueryLogs() async {
    if (!_isConnected || _connection == null) return;
    
    try {
      // Get recent queries
      final queryResults = await _connection!.query('''
        SELECT 
          query, 
          state, 
          EXTRACT(EPOCH FROM now() - query_start) as duration, 
          datname, 
          query_start, 
          usename, 
          client_addr::text, 
          application_name
        FROM 
          pg_stat_activity 
        WHERE 
          query_start IS NOT NULL 
          AND query <> '<IDLE>' 
          AND pid <> pg_backend_pid() 
        ORDER BY 
          query_start DESC 
        LIMIT 20
      ''');
      
      final logs = <QueryLog>[];
      
      for (final row in queryResults) {
        try {
          final query = row[0]?.toString() ?? 'Unknown query';
          final state = row[1]?.toString() ?? 'unknown';
          final duration = row[2] != null ? (row[2] as double) : 0.0;
          final database = row[3]?.toString() ?? _connection!.databaseName;
          final timestamp = row[4] != null 
              ? (row[4] as DateTime) 
              : DateTime.now().subtract(Duration(seconds: duration.ceil()));
          final username = row[5]?.toString() ?? _connection!.username;
          final clientAddr = row[6]?.toString() ?? 'local';
          final appName = row[7]?.toString() ?? 'PostgreSQL Monitor';
          
          logs.add(QueryLog(
            query: query,
            state: state,
            status: state == 'active' ? 'running' : 'completed',
            executionTime: duration,
            database: database,
            timestamp: timestamp,
            applicationName: appName,
            clientAddress: clientAddr,
          ));
        } catch (e) {
          print('Error parsing query log: $e');
        }
      }
      
      _latestQueryLogs = logs;
      _queryLogsController.add(logs);
    } catch (e) {
      print('Error fetching query logs: $e');
    }
  }
  
  void _updateConnectionStatus(ConnectionStatus status) {
    _latestConnectionStatus = status;
    _connectionStatusController.add(status);
  }
  
  void _stopPeriodicUpdates() {
    _statsRefreshTimer?.cancel();
    _resourceStatsTimer?.cancel();
    _statsRefreshTimer = null;
    _resourceStatsTimer = null;
  }
  
  void dispose() {
    _statsRefreshTimer?.cancel();
    _resourceStatsTimer?.cancel();
    _connectionStatusController.close();
    _databaseStatsController.close();
    _queryLogsController.close();
    _resourceStatsController.close();
    
    // Close connection if open
    if (_isConnected && _connection != null) {
      _connection!.close();
    }
  }
  
  // Getter methods for current values for StreamBuilder initialData
  ConnectionStatus getConnectionStatus() {
    return _latestConnectionStatus;
  }
  
  DatabaseStats getDatabaseStats() {
    return _latestDatabaseStats;
  }
  
  ResourceStats getResourceStats() {
    return _latestResourceStats;
  }
  
  List<QueryLog> getQueryLogs() {
    return _latestQueryLogs;
  }
  
  bool isConnected() {
    return _isConnected && _connection != null;
  }
  
  // Helper method to parse sizes like "8 MB" to a numeric value in MB
  double _parseSize(String sizeStr) {
    // Clean the input
    final cleanedStr = sizeStr.toLowerCase().trim();
    
    // Extract the numeric part
    final RegExp numeric = RegExp(r'[0-9.]+');
    final match = numeric.firstMatch(cleanedStr);
    
    if (match == null) {
      return 0.0; // Return 0 if we can't find a number
    }
    
    final value = double.tryParse(match.group(0) ?? '0') ?? 0.0;
    
    // Check the unit
    if (cleanedStr.contains('kb') || cleanedStr.contains('kib')) {
      return value / 1024.0; // Convert KB to MB
    } else if (cleanedStr.contains('mb') || cleanedStr.contains('mib')) {
      return value; // Already in MB
    } else if (cleanedStr.contains('gb') || cleanedStr.contains('gib')) {
      return value * 1024.0; // Convert GB to MB
    } else if (cleanedStr.contains('tb') || cleanedStr.contains('tib')) {
      return value * 1024.0 * 1024.0; // Convert TB to MB
    } else if (cleanedStr.contains('b') && !cleanedStr.contains('kb') && !cleanedStr.contains('mb') && !cleanedStr.contains('gb')) {
      return value / (1024.0 * 1024.0); // Convert B to MB
    }
    
    // Default to MB if no unit is specified
    return value;
  }
}