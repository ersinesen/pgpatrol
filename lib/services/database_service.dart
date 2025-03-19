import 'dart:async';
import 'dart:io';
import 'package:postgres/postgres.dart';
import '../models/connection_status.dart';
import '../models/database_stats.dart';
import '../models/query_log.dart';
import '../models/resource_stats.dart';
import '../models/table_stats.dart';
import '../models/server_connection.dart';
import '../models/analysis_result.dart';
import 'connection_manager.dart';

/// Direct DatabaseService implementation that connects directly to PostgreSQL
/// without using Node.js API. For desktop platforms.
class DatabaseService {
  // Connection management
  PostgreSQLConnection? _connection;
  String? _connectionName;
  String? _currentAnalysisKey; // Tracks the current analysis being performed

  // Flag to track if the service is connected to the database
  bool _isConnected = false;
  Timer? _statsRefreshTimer;
  Timer? _resourceStatsTimer;

  // Stream controllers for real-time updates
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _databaseStatsController = StreamController<DatabaseStats>.broadcast();
  final _queryLogsController = StreamController<List<QueryLog>>.broadcast();
  final _resourceStatsController = StreamController<ResourceStats>.broadcast();
  final _tableStatsController = StreamController<TableStats>.broadcast();
  
  // Streams
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  Stream<DatabaseStats> get databaseStatsStream => _databaseStatsController.stream;
  Stream<List<QueryLog>> get queryLogsStream => _queryLogsController.stream;
  Stream<ResourceStats> get resourceStatsStream => _resourceStatsController.stream;
  Stream<TableStats> get tableStatsStream => _tableStatsController.stream;

  // Latest data
  ConnectionStatus _latestConnectionStatus = ConnectionStatus.initial();
  DatabaseStats _latestDatabaseStats = DatabaseStats.initial();
  List<QueryLog> _latestQueryLogs = [];
  ResourceStats _latestResourceStats = ResourceStats.initial();
  TableStats _latestTableStats = TableStats.initial();
  
  // Analysis results cache
  Map<String, AnalysisResult> _analysisResultCache = {};
  
  // Analysis result stream controller
  final _analysisResultController = StreamController<AnalysisResult>.broadcast();
  
  // Analysis result stream
  Stream<AnalysisResult> get analysisResultStream => _analysisResultController.stream;

  // Analysis
  final StreamController<Map<String, dynamic>> _statsController = StreamController.broadcast();
  Map<String, dynamic> _analysisResults = {};
  final Map<String, String> _queries = {
    'deadlock': "SELECT * FROM pg_stat_activity WHERE wait_event_type = 'Lock'",
    'total_tables': "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'",
    'idle': "SELECT pid, usename, query_start, state FROM pg_stat_activity WHERE state = 'idle in transaction';",
    'long_tables': "SELECT schemaname, relname, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 10;",
    'index_usage': "SELECT relname, idx_scan, idx_tup_read, idx_tup_fetch FROM pg_stat_user_indexes ORDER BY idx_scan DESC LIMIT 10;",
    'large_tables':"SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total_size FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;",
    'large_indices': "SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total_size FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;",
    'blocked_queries': "SELECT pid, usename, query_start, state, wait_event, query FROM pg_stat_activity WHERE wait_event IS NOT NULL;",
    'max_connections': "SHOW max_connections;",
    'high_dead_tuple': "SELECT relname, n_dead_tup, last_autovacuum FROM pg_stat_user_tables WHERE n_dead_tup > 1000 ORDER BY n_dead_tup DESC;",
    'vacuum_progress': "SELECT * FROM pg_stat_progress_vacuum;",
    'frequent_queries': "SELECT query, calls FROM pg_stat_statements ORDER BY calls DESC LIMIT 10;",
    'index_bloat': "SELECT schemaname, relname, indexrelname, idx_blks_read, idx_blks_hit, idx_blks_read + idx_blks_hit as total_reads, idx_blks_read / (idx_blks_read + idx_blks_hit) as read_pct FROM pg_statio_user_indexes ORDER BY total_reads DESC LIMIT 10;",  
    'slow_queries': "SELECT query, total_exec_time, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;",
    'index_hit_rate': "SELECT sum(idx_scan) / sum(seq_scan + idx_scan) AS index_hit_rate FROM pg_stat_user_tables;",
    'background_worker': "SELECT * FROM pg_stat_activity WHERE backend_type != 'client backend';",
    'active_locks': "SELECT pid, locktype, relation::regclass, mode, granted FROM pg_locks WHERE NOT granted;",
  };
  Stream<Map<String, dynamic>> get analysisStream => _statsController.stream;


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
        useSSL: false, // Enable SSL by default
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
        await _fetchTableStats();
        await _fetchAnalysis('deadlock');
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
        useSSL: false, // Enable SSL by default
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
        await _fetchTableStats();
        await _fetchAnalysis('deadlock');
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

  Future<void> _fetchAnalysis(String analysisName) async {
    if (!_queries.containsKey(analysisName) || _connection == null) return;

    // Set the current analysis key for column name extraction
    _currentAnalysisKey = analysisName;
    
    final sql = _queries[analysisName];

    try {
      final results = await _connection!.query(sql!);
      
      // Use the improved query results processor that extracts column names
      final processedResults = _processQueryResults(results);
      _analysisResults[analysisName] = processedResults;

      print('Fetched $analysisName: ${_analysisResults[analysisName].length} rows');

      // Emit updated results
      _statsController.add(_analysisResults);
    } catch (e) {
      print('Error fetching $analysisName: $e');
    }
  }
  
  /// Analyze specific PostgreSQL metrics based on the provided key
  Future<AnalysisResult> analyze(String key) async {
    if (!_isConnected || _connection == null) {
      return AnalysisResult.empty(key);
    }
    
    try {
      // Check if we have a query for this key
      if (!_queries.containsKey(key)) {
        print('DatabaseService: No query defined for analysis key: $key');
        return AnalysisResult.empty(key);
      }
      
      // Check if we have a cached result
      if (_analysisResultCache.containsKey(key)) {
        final cacheTime = _analysisResultCache[key]!.timestamp;
        final now = DateTime.now();
        // If cache is less than 10 seconds old, return it
        if (now.difference(cacheTime).inSeconds < 10) {
          return _analysisResultCache[key]!;
        }
      }
      
      // Set the current analysis key
      _currentAnalysisKey = key;
      
      // Execute the query
      final sql = _queries[key]!;
      print('DatabaseService: Running analysis query for $key');
      
      final results = await _connection!.query(sql);
      final processedResults = _processQueryResults(results);
      
      // Create analysis result
      final columnsList = processedResults.isNotEmpty 
        ? processedResults[0].keys.map((key) => key.toString()).toList() 
        : <String>[];
      final analysisResult = AnalysisResult(
        key: key,
        timestamp: DateTime.now(),
        data: processedResults,
        count: processedResults.length,
        columns: columnsList,
      );
      
      // Cache the result
      _analysisResultCache[key] = analysisResult;
      
      // Emit the result through the stream
      _analysisResultController.add(analysisResult);
      
      return analysisResult;
    } catch (e) {
      print('Error executing analysis: $e');
      return AnalysisResult(
        key: key,
        timestamp: DateTime.now(),
        data: [],
        count: 0,
        columns: <String>[],
      );
    }
  }
  
  // Convert PostgreSQL query results to a list of maps with column names
  List<Map<String, dynamic>> _processQueryResults(List<List<dynamic>> results) {
    if (results.isEmpty) {
      return [];
    }
    
    try {
      // Extract column names from the active query
      // For direct PostgreSQL connection, we need to parse the column names from the SQL
      String? currentQuery = _queries[_currentAnalysisKey];
      if (currentQuery != null) {
        List<String>? columnNames = _extractColumnNames(currentQuery);
        if (columnNames != null && columnNames.length > 0) {
          return _processResultsWithColumns(results, columnNames);
        }
      }
      
      // Fallback if we can't extract column names
      return _processResults(results);
    } catch (e) {
      print('Error processing query results: $e');
      // Fallback with simple processing
      return _processResults(results);
    }
  }
  
  // Extract column names from SQL query
  List<String>? _extractColumnNames(String sql) {
    try {
      // Clean up the SQL and extract column section
      sql = sql.replaceAll('\n', ' ').replaceAll('\r', ' ');
      
      // Handle SELECT * case
      if (sql.toLowerCase().contains('select *')) {
        // For SELECT *, we can't determine column names from SQL
        // We'll use common column names based on the analysis key
        return _getDefaultColumnsForKey(_currentAnalysisKey);
      }
      
      // Extract column names from SELECT clause
      final selectMatch = RegExp(r'SELECT\s+(.*?)\s+FROM', caseSensitive: false).firstMatch(sql);
      if (selectMatch != null && selectMatch.groupCount >= 1) {
        String columnsSection = selectMatch.group(1)!;
        
        // Split by commas, but handle special cases (like functions with commas)
        List<String> columns = [];
        int depth = 0;
        String current = '';
        
        for (int i = 0; i < columnsSection.length; i++) {
          var char = columnsSection[i];
          if (char == '(' || char == '{') depth++;
          else if (char == ')' || char == '}') depth--;
          
          if (char == ',' && depth == 0) {
            columns.add(current.trim());
            current = '';
          } else {
            current += char;
          }
        }
        
        if (current.trim().isNotEmpty) {
          columns.add(current.trim());
        }
        
        // Extract column names or aliases
        return columns.map((col) {
          col = col.trim();
          
          // Check for AS keyword
          final asMatch = RegExp(r'.*\s+AS\s+([^\s,]+)$', caseSensitive: false).firstMatch(col);
          if (asMatch != null && asMatch.groupCount >= 1) {
            return asMatch.group(1)!.replaceAll('"', '').replaceAll('\'', '');
          }
          
          // No AS? Check if it's a direct column name
          if (!col.contains(' ') && !col.contains('(')) {
            return col.replaceAll('"', '').replaceAll('\'', '');
          }
          
          // For complex expressions, take the last part after a dot or space
          final parts = col.split(RegExp(r'[\.\s]'));
          return parts.last.replaceAll('"', '').replaceAll('\'', '');
        }).toList();
      }
      
      // Fallback - return null if we can't parse the query
      return null;
    } catch (e) {
      print('Error extracting column names: $e');
      return null;
    }
  }
  
  // Get default column names for known analysis types
  List<String>? _getDefaultColumnsForKey(String? key) {
    if (key == null) return null;
    
    // Common column names for each analysis type
    switch (key) {
      case 'deadlock':
        return ['pid', 'usename', 'application_name', 'client_addr', 'query_start', 'state', 'wait_event', 'wait_event_type', 'query'];
      case 'idle':
        return ['pid', 'usename', 'query_start', 'state'];
      case 'long_tables':
        return ['schemaname', 'relname', 'n_live_tup'];
      case 'index_usage':
        return ['relname', 'idx_scan', 'idx_tup_read', 'idx_tup_fetch'];
      case 'large_tables':
      case 'large_indices':
        return ['relname', 'total_size'];
      case 'blocked_queries':
        return ['pid', 'usename', 'query_start', 'state', 'wait_event', 'query'];
      case 'max_connections':
        return ['max_connections'];
      default:
        return null;
    }
  }

  // Process results with known column names
  List<Map<String, dynamic>> _processResultsWithColumns(List<List<dynamic>> results, List<String> columnNames) {
    return results.map((row) {
      final Map<String, dynamic> resultMap = {};
      for (var i = 0; i < row.length && i < columnNames.length; i++) {
        resultMap[columnNames[i]] = row[i];
      }
      
      // Add any remaining columns with generic names
      if (row.length > columnNames.length) {
        for (var i = columnNames.length; i < row.length; i++) {
          resultMap['col_$i'] = row[i];
        }
      }
      
      return resultMap;
    }).toList();
  }

  // Fallback processing with generic column names
  List<Map<String, dynamic>> _processResults(List<List<dynamic>> results) {
    // Generate generic column names
    // This matches the format returned by the API but uses generic column names
    return results.map((row) {
      final Map<String, dynamic> resultMap = {};
      for (var i = 0; i < row.length; i++) {
        // Use the same column naming convention as the API
        resultMap['col_$i'] = row[i];
      }
      return resultMap;
    }).toList();
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

  Future<void> _fetchTableStats() async {
    if (!_isConnected || _connection == null) return;

    try {
      // First, get the total table count
      final countResults = await _connection!.query(
        "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'"
      );
      final totalTables = countResults.isNotEmpty ? (countResults[0][0] as int) : 0;
      
      // Get the list of tables with sizes
      final tableResults = await _connection!.query('''
        SELECT 
          table_name,
          pg_size_pretty(pg_total_relation_size(quote_ident(table_name))) as size,
          pg_total_relation_size(quote_ident(table_name)) as raw_size
        FROM 
          information_schema.tables 
        WHERE 
          table_schema = 'public'
        ORDER BY 
          pg_total_relation_size(quote_ident(table_name)) DESC 
        LIMIT 20
      ''');

      final tables = <TableInfo>[];

      for (final row in tableResults) {
        try {
          final name = row[0].toString();
          final sizeStr = row[1].toString();
          
          tables.add(TableInfo(
            name: name,
            size: _parseSize(sizeStr),
          ));
        } catch (e) {
          print('Error parsing table info: $e');
        }
      }

      // Create TableStats object with fetched data
      final stats = TableStats(
        totalTables: totalTables,
        tables: tables,
        lastUpdated: DateTime.now(),
      );

      // Update the latest data and stream
      _latestTableStats = stats;
      _tableStatsController.add(stats);
    } catch (e) {
      print('Error fetching table stats: $e');
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
          final duration = row[2] != null ? double.tryParse(row[2].toString()) ?? 0.0 : 0.0;
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
    _tableStatsController.close();
    _statsController.close();
    _analysisResultController.close();

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

  TableStats getTableStats() {
    return _latestTableStats;
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