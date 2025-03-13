import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import '../models/connection_status.dart';
import '../models/database_stats.dart';
import '../models/query_log.dart';
import '../models/resource_stats.dart';

class DatabaseService {
  PostgreSQLConnection? _connection;
  String? _connectionString;
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
  Stream<DatabaseStats> get databaseStats => _databaseStatsController.stream;
  Stream<List<QueryLog>> get queryLogs => _queryLogsController.stream;
  Stream<ResourceStats> get resourceStats => _resourceStatsController.stream;
  
  // Latest data
  ConnectionStatus _latestConnectionStatus = ConnectionStatus.initial();
  DatabaseStats _latestDatabaseStats = DatabaseStats.initial();
  List<QueryLog> _latestQueryLogs = [];
  ResourceStats _latestResourceStats = ResourceStats.initial();
  
  DatabaseService() {
    _initConnection();
  }
  
  void _initConnection() async {
    // Get connection details from environment variables
    final connectionString = Platform.environment['DATABASE_URL'];
    if (connectionString == null || connectionString.isEmpty) {
      _updateConnectionStatus(
        ConnectionStatus.initial().copyWith(
          statusMessage: 'DATABASE_URL environment variable not found',
        ),
      );
      return;
    }
    
    _connectionString = connectionString;
    await _connect();
    
    // Start periodic updates
    _startPeriodicUpdates();
  }
  
  Future<void> _connect() async {
    if (_connectionString == null) return;
    
    try {
      final uri = Uri.parse(_connectionString!);
      final userInfo = uri.userInfo.split(':');
      
      _connection = PostgreSQLConnection(
        uri.host,
        uri.port,
        uri.pathSegments.last,
        username: userInfo.first,
        password: userInfo.length > 1 ? userInfo.last : null,
        useSSL: uri.scheme == 'postgres',
      );
      
      await _connection!.open();
      _isConnected = true;
      
      // Get PostgreSQL version
      final result = await _connection!.query('SELECT version();');
      final serverVersion = result.first.first.toString();
      
      // Get active connections and max connections
      final connectionsResult = await _connection!.query('''
        SELECT 
          (SELECT count(*) FROM pg_stat_activity) as active,
          (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') as max
      ''');
      
      final activeConnections = connectionsResult.first[0] as int;
      final maxConnections = connectionsResult.first[1] as int;
      
      _updateConnectionStatus(
        ConnectionStatus(
          isConnected: true,
          serverVersion: serverVersion,
          activeConnections: activeConnections,
          maxConnections: maxConnections,
          lastChecked: DateTime.now(),
          statusMessage: 'Connected',
        ),
      );
      
      // Get initial stats
      await _fetchDatabaseStats();
      await _fetchResourceStats();
      await _fetchQueryLogs();
      
    } catch (e) {
      _isConnected = false;
      _updateConnectionStatus(
        ConnectionStatus.initial().copyWith(
          statusMessage: 'Connection error: ${e.toString()}',
        ),
      );
    }
  }
  
  void _startPeriodicUpdates() {
    // Fetch stats every 10 seconds
    _statsRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_isConnected) {
        await _fetchDatabaseStats();
        await _fetchQueryLogs();
      } else {
        await _connect();
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
    if (_connection == null || !_isConnected) return;
    
    try {
      // Get database list with size and tables
      final dbListResult = await _connection!.query('''
        SELECT 
          d.datname as database_name,
          pg_database_size(d.datname) as size,
          (SELECT count(*) FROM pg_stat_activity WHERE datname = d.datname) as connections,
          (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_catalog = d.datname) as tables
        FROM pg_database d
        WHERE d.datname NOT IN ('template0', 'template1', 'postgres')
        ORDER BY size DESC;
      ''');
      
      final dbList = dbListResult.map<DatabaseInfo>((row) {
        return DatabaseInfo(
          name: row[0] as String,
          sizeInMB: (row[1] as int) / (1024 * 1024),
          activeConnections: row[2] as int,
          tables: row[3] as int,
        );
      }).toList();
      
      // Calculate totals
      int totalDatabases = dbList.length;
      int totalTables = dbList.fold<int>(0, (prev, db) => prev + db.tables);
      double totalSizeMB = dbList.fold<double>(0, (prev, db) => prev + db.sizeInMB);
      
      final stats = DatabaseStats(
        totalDatabases: totalDatabases,
        totalTables: totalTables,
        dbSize: totalSizeMB,
        databases: dbList,
        lastUpdated: DateTime.now(),
      );
      
      _latestDatabaseStats = stats;
      _databaseStatsController.add(stats);
      
    } catch (e) {
      print('Error fetching database stats: $e');
    }
  }
  
  Future<void> _fetchResourceStats() async {
    if (_connection == null || !_isConnected) return;
    
    try {
      // Get CPU, memory, and disk IO stats
      final resourceResult = await _connection!.query('''
        SELECT 
          (SELECT 100 * (1 - idle / (idle + busy)) FROM (
            SELECT
              extract(epoch FROM now()) - extract(epoch FROM stats_reset) as busy,
              extract(epoch FROM now()) - extract(epoch FROM stats_reset) - (user_time + system_time) as idle
            FROM pg_stat_database, pg_stat_bgwriter
            WHERE datname = '${_connection!.databaseName}'
          ) as cpu) as cpu_usage,
          (SELECT (sum(buffers_alloc) * 8192) / 1024 / 1024 FROM pg_stat_database) as memory_mb,
          (SELECT (CASE WHEN total_bytes > 0 THEN used_bytes * 100 / total_bytes ELSE 0 END) 
            FROM (
              SELECT
                (SELECT setting::bigint FROM pg_settings WHERE name = 'shared_buffers') * 8192 as total_bytes,
                (SELECT sum(buffers_alloc) * 8192 FROM pg_stat_database) as used_bytes
            ) as disk) as disk_usage
      ''');
      
      double cpuUsage = resourceResult.first[0] != null ? (resourceResult.first[0] as double) : 0.0;
      double memoryUsage = resourceResult.first[1] != null ? (resourceResult.first[1] as double) : 0.0;
      double diskUsage = resourceResult.first[2] != null ? (resourceResult.first[2] as double) : 0.0;
      
      // Ensure values are within range
      cpuUsage = cpuUsage.isNaN || cpuUsage < 0 ? 0.0 : cpuUsage > 100 ? 100.0 : cpuUsage;
      diskUsage = diskUsage.isNaN || diskUsage < 0 ? 0.0 : diskUsage > 100 ? 100.0 : diskUsage;
      
      final now = DateTime.now();
      
      // Update historical data (keep the last 30 points)
      final newCpuHistory = List<TimeSeriesData>.from(_latestResourceStats.historicalCpuUsage);
      final newMemoryHistory = List<TimeSeriesData>.from(_latestResourceStats.historicalMemoryUsage);
      final newDiskHistory = List<TimeSeriesData>.from(_latestResourceStats.historicalDiskUsage);
      
      newCpuHistory.add(TimeSeriesData(time: now, value: cpuUsage));
      newMemoryHistory.add(TimeSeriesData(time: now, value: memoryUsage));
      newDiskHistory.add(TimeSeriesData(time: now, value: diskUsage));
      
      // Keep only the most recent 30 data points
      if (newCpuHistory.length > 30) newCpuHistory.removeAt(0);
      if (newMemoryHistory.length > 30) newMemoryHistory.removeAt(0);
      if (newDiskHistory.length > 30) newDiskHistory.removeAt(0);
      
      final stats = ResourceStats(
        cpuUsage: cpuUsage,
        memoryUsage: memoryUsage,
        diskUsage: diskUsage,
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
    if (_connection == null || !_isConnected) return;
    
    try {
      // Get recent queries from pg_stat_activity
      final logsResult = await _connection!.query('''
        SELECT 
          query,
          state,
          backend_start,
          query_start,
          application_name,
          client_addr,
          datname,
          CASE WHEN state = 'active' THEN
            EXTRACT(EPOCH FROM (now() - query_start))
          ELSE
            EXTRACT(EPOCH FROM (now() - backend_start))
          END as duration
        FROM pg_stat_activity
        WHERE query != '<insufficient privilege>'
          AND query IS NOT NULL
          AND state IS NOT NULL
          AND query NOT LIKE 'autovacuum:%'
          AND query NOT LIKE 'SELECT%FROM pg_stat_activity%'
        ORDER BY query_start DESC NULLS LAST
        LIMIT 20;
      ''');
      
      final logs = logsResult.map<QueryLog>((row) {
        final query = row[0] as String?;
        final state = row[1] as String?;
        final queryStart = row[3] as DateTime?;
        final appName = row[4] as String?;
        final clientAddr = row[5] != null ? row[5].toString() : 'localhost';
        final dbName = row[6] as String?;
        final duration = row[7] != null ? (row[7] as double) : 0.0;
        
        return QueryLog(
          query: query ?? 'Unknown query',
          timestamp: queryStart ?? DateTime.now(),
          executionTime: duration,
          database: dbName ?? _connection!.databaseName!,
          status: 'completed',
          state: state ?? 'idle',
          applicationName: appName ?? 'PostgreSQL Monitor',
          clientAddress: clientAddr,
        );
      }).toList();
      
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
  
  Future<PostgreSQLResult> runQuery(String query) async {
    if (_connection == null || !_isConnected) {
      throw Exception('Not connected to database');
    }
    
    try {
      final startTime = DateTime.now();
      final result = await _connection!.query(query);
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds / 1000;
      
      final queryLog = QueryLog(
        query: query,
        timestamp: startTime,
        executionTime: duration,
        database: _connection!.databaseName!,
        status: 'completed',
      );
      
      // Add to logs
      final updatedLogs = [queryLog, ..._latestQueryLogs];
      if (updatedLogs.length > 100) updatedLogs.removeLast();
      
      _latestQueryLogs = updatedLogs;
      _queryLogsController.add(updatedLogs);
      
      return result;
    } catch (e) {
      final queryLog = QueryLog(
        query: query,
        timestamp: DateTime.now(),
        executionTime: 0,
        database: _connection!.databaseName!,
        status: 'error',
        error: e.toString(),
      );
      
      // Add to logs
      final updatedLogs = [queryLog, ..._latestQueryLogs];
      if (updatedLogs.length > 100) updatedLogs.removeLast();
      
      _latestQueryLogs = updatedLogs;
      _queryLogsController.add(updatedLogs);
      
      throw e;
    }
  }
  
  // Get the latest data directly
  ConnectionStatus getConnectionStatus() => _latestConnectionStatus;
  DatabaseStats getDatabaseStats() => _latestDatabaseStats;
  List<QueryLog> getQueryLogs() => _latestQueryLogs;
  ResourceStats getResourceStats() => _latestResourceStats;
  
  void dispose() {
    _statsRefreshTimer?.cancel();
    _resourceStatsTimer?.cancel();
    _connection?.close();
    _connectionStatusController.close();
    _databaseStatsController.close();
    _queryLogsController.close();
    _resourceStatsController.close();
  }
}