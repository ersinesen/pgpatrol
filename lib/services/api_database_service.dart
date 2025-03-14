import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/connection_status.dart';
import '../models/database_stats.dart';
import '../models/query_log.dart';
import '../models/resource_stats.dart';

/// Service for communicating with the PostgreSQL database through API
class DatabaseService {
  // API base URL - Replit specific since both frontend and backend run on the same domain
  final String _baseUrl = '/api';
  
  // Stream controllers
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _databaseStatsController = StreamController<DatabaseStats>.broadcast();
  final _resourceStatsController = StreamController<ResourceStats>.broadcast();
  final _queryLogsController = StreamController<List<QueryLog>>.broadcast();
  
  // Current state
  ConnectionStatus _connectionStatus = ConnectionStatus.initial();
  DatabaseStats _databaseStats = DatabaseStats.initial();
  ResourceStats _resourceStats = ResourceStats.initial();
  List<QueryLog> _queryLogs = [];
  
  // Stream getters
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  Stream<DatabaseStats> get databaseStats => _databaseStatsController.stream;
  Stream<ResourceStats> get resourceStats => _resourceStatsController.stream;
  Stream<List<QueryLog>> get queryLogs => _queryLogsController.stream;
  Stream<List<QueryLog>> get queryLogsStream => _queryLogsController.stream;
  Stream<ResourceStats> get resourceStatsStream => _resourceStatsController.stream;
  Stream<List<QueryPerformance>> get queryPerformanceStream => Stream.value([]);  // Placeholder
  
  // Timer for auto-refresh
  Timer? _refreshTimer;
  
  DatabaseService() {
    // Initial fetch
    _checkConnection();
    _fetchDatabaseStats();
    _fetchResourceStats();
    _fetchQueryLogs();
    
    // Setup auto-refresh timer (every 10 seconds)
    _refreshTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _checkConnection();
      _fetchDatabaseStats();
      _fetchResourceStats();
      _fetchQueryLogs();
    });
  }
  
  // Dispose method to clean up resources
  void dispose() {
    _refreshTimer?.cancel();
    _connectionStatusController.close();
    _databaseStatsController.close();
    _resourceStatsController.close();
    _queryLogsController.close();
  }
  
  // Connection check
  Future<void> _checkConnection() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/connection'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _connectionStatus = ConnectionStatus(
          isConnected: data['status'] == 'connected',
          connectionName: 'PostgreSQL',
          serverVersion: data['version'] ?? 'Unknown',
          statusMessage: data['status'] == 'connected' ? 'Connected' : 'Disconnected',
          activeConnections: 1,  // Placeholder
          maxConnections: 100,   // Placeholder
          lastChecked: DateTime.now(),
        );
      } else {
        _connectionStatus = ConnectionStatus(
          isConnected: false,
          connectionName: 'PostgreSQL',
          serverVersion: 'Unknown',
          statusMessage: 'Connection failed: ${response.statusCode}',
          activeConnections: 0,
          maxConnections: 0,
          lastChecked: DateTime.now(),
        );
      }
    } catch (e) {
      _connectionStatus = ConnectionStatus(
        isConnected: false,
        connectionName: 'PostgreSQL',
        serverVersion: 'Unknown',
        statusMessage: 'Connection error: $e',
        activeConnections: 0,
        maxConnections: 0,
        lastChecked: DateTime.now(),
      );
    }
    
    _connectionStatusController.add(_connectionStatus);
  }
  
  // Fetch database statistics
  Future<void> _fetchDatabaseStats() async {
    if (!_connectionStatus.isConnected) return;
    
    try {
      final response = await http.get(Uri.parse('$_baseUrl/stats'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Parse size string (e.g., "10.5 MB" to double)
        double dbSize = 0;
        final sizeStr = data['size'] as String;
        if (sizeStr.contains('MB')) {
          dbSize = double.parse(sizeStr.replaceAll(' MB', ''));
        } else if (sizeStr.contains('GB')) {
          dbSize = double.parse(sizeStr.replaceAll(' GB', '')) * 1024;
        } else if (sizeStr.contains('KB')) {
          dbSize = double.parse(sizeStr.replaceAll(' KB', '')) / 1024;
        }
        
        _databaseStats = DatabaseStats(
          totalDatabases: 1,  // Just counting current database
          totalTables: data['tableCount'] ?? 0,
          dbSize: dbSize,
          databases: [
            DatabaseInfo(
              name: 'postgres',  // Default name
              tables: data['tableCount'] ?? 0,
              sizeInMB: dbSize,
              activeConnections: data['connections'] ?? 1,
            )
          ],
          lastUpdated: DateTime.now(),
        );
        
        _databaseStatsController.add(_databaseStats);
      }
    } catch (e) {
      print('Error fetching database stats: $e');
    }
  }
  
  // Fetch resource statistics
  Future<void> _fetchResourceStats() async {
    if (!_connectionStatus.isConnected) return;
    
    try {
      final response = await http.get(Uri.parse('$_baseUrl/resource-stats'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // CPU calculation (simplified)
        final cpuTime = data['cpu']['active_query_time'] ?? 0.0;
        final cpuUsage = cpuTime > 10 ? 100.0 : cpuTime * 10; // Scale for visualization
        
        // Memory usage
        final memoryUsed = (data['memory']['used'] ?? 0) / (1024 * 1024); // Convert to MB
        
        // Disk usage (percentage)
        final diskUsage = 50.0; // Placeholder, can be enhanced with real data
        
        // Update historical data
        final now = DateTime.now();
        final newHistoricalCpuUsage = List<TimeSeriesData>.from(_resourceStats.historicalCpuUsage);
        final newHistoricalMemoryUsage = List<TimeSeriesData>.from(_resourceStats.historicalMemoryUsage);
        final newHistoricalDiskUsage = List<TimeSeriesData>.from(_resourceStats.historicalDiskUsage);
        
        // Add new data points
        newHistoricalCpuUsage.add(TimeSeriesData(time: now, value: cpuUsage));
        newHistoricalMemoryUsage.add(TimeSeriesData(time: now, value: memoryUsed));
        newHistoricalDiskUsage.add(TimeSeriesData(time: now, value: diskUsage));
        
        // Keep only the last 20 data points
        if (newHistoricalCpuUsage.length > 20) {
          newHistoricalCpuUsage.removeAt(0);
        }
        if (newHistoricalMemoryUsage.length > 20) {
          newHistoricalMemoryUsage.removeAt(0);
        }
        if (newHistoricalDiskUsage.length > 20) {
          newHistoricalDiskUsage.removeAt(0);
        }
        
        _resourceStats = ResourceStats(
          cpuUsage: cpuUsage,
          memoryUsage: memoryUsed,
          diskUsage: diskUsage,
          historicalCpuUsage: newHistoricalCpuUsage,
          historicalMemoryUsage: newHistoricalMemoryUsage,
          historicalDiskUsage: newHistoricalDiskUsage,
          timestamp: DateTime.now(),
        );
        
        _resourceStatsController.add(_resourceStats);
      }
    } catch (e) {
      print('Error fetching resource stats: $e');
    }
  }
  
  // Fetch query logs
  Future<void> _fetchQueryLogs() async {
    if (!_connectionStatus.isConnected) return;
    
    try {
      final response = await http.get(Uri.parse('$_baseUrl/query-logs'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        final List<QueryLog> logs = data.map((item) {
          // Convert execution time from milliseconds to duration
          final durationMs = (item['mean_time'] as num?)?.toDouble() ?? 0.0;
          
          return QueryLog(
            query: item['query'] ?? 'Unknown query',
            timestamp: DateTime.now().subtract(Duration(minutes: 5)), // Placeholder
            executionTime: durationMs / 1000, // Convert to seconds
            database: 'postgres', // Placeholder
            status: 'completed',
            state: 'idle',
            applicationName: 'pgAdmin',
            clientAddress: '127.0.0.1',
          );
        }).toList();
        
        _queryLogs = logs;
        _queryLogsController.add(_queryLogs);
      }
    } catch (e) {
      print('Error fetching query logs: $e');
    }
  }
  
  // Execute a custom query
  Future<List<Map<String, dynamic>>> executeCustomQuery(String query) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/run-query'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'query': query}),
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Unknown error');
      }
    } catch (e) {
      print('Error executing custom query: $e');
      rethrow;
    }
  }
  
  // Public methods to refresh data manually
  Future<void> refreshConnection() async => _checkConnection();
  Future<void> refreshDatabaseStats() async => _fetchDatabaseStats();
  Future<void> refreshResourceStats() async => _fetchResourceStats();
  Future<void> refreshQueryLogs() async => _fetchQueryLogs();
  Future<void> refreshQueryPerformance() async => null; // Placeholder
  
  // Getters for current data
  ConnectionStatus getConnectionStatus() => _connectionStatus;
  DatabaseStats getDatabaseStats() => _databaseStats;
  ResourceStats getResourceStats() => _resourceStats;
  List<QueryLog> getQueryLogs() => _queryLogs;
}

// Placeholder for QueryPerformance model used in query_performance_screen.dart
class QueryPerformance {
  final String queryType;
  final int count;
  final Duration avgDuration;
  final Duration maxDuration;
  final int rowsAffected;

  QueryPerformance({
    required this.queryType,
    required this.count,
    required this.avgDuration,
    required this.maxDuration,
    required this.rowsAffected,
  });

  String get formattedAvgDuration {
    return _formatDuration(avgDuration);
  }

  String _formatDuration(Duration duration) {
    if (duration.inMicroseconds < 1000) {
      return '${duration.inMicroseconds} μs';
    } else if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds} ms';
    } else if (duration.inSeconds < 60) {
      return '${duration.inSeconds} s';
    } else {
      return '${duration.inMinutes} min';
    }
  }
}