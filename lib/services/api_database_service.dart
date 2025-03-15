import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/connection_status.dart';
import '../models/database_stats.dart';
import '../models/query_log.dart';
import '../models/resource_stats.dart';
import '../models/server_connection.dart';

/// DatabaseService implementation that uses our Node.js API instead of
/// connecting directly to PostgreSQL.
class ApiDatabaseService {
  // Base URL for API requests
  final String baseUrl;
  
  // Flag to track if the service is connected to the backend
  bool _isConnected = false;
  String? _sessionId;
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
  
  // Constructor
  ApiDatabaseService({
    this.baseUrl = '/api', // Default to relative URL for same-origin requests
  }) {
    // Initialize
    _initialize();
  }
  
  void _initialize() async {
    // Initial check of connection status
    await _checkConnectionStatus();
    
    // Start periodic updates if connection is successful
    if (_isConnected) {
      _startPeriodicUpdates();
    }
  }
  
  Future<void> _checkConnectionStatus() async {
    try {
      // Get session ID first to ensure proper session tracking
      await _getOrCreateSession();
      
      final response = await http.get(Uri.parse('$baseUrl/connection?sessionId=$_sessionId'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        _isConnected = data['status'] == 'connected';
        
        // Extract additional connection info if available
        final serverVersion = data['version'] ?? 'Unknown';
        final databaseName = data['databaseName'] ?? 'Default Database';
        
        _updateConnectionStatus(
          ConnectionStatus(
            isConnected: _isConnected,
            serverVersion: serverVersion,
            activeConnections: 0, // Will be updated with database stats
            maxConnections: 100, // Default value
            lastChecked: DateTime.now(),
            statusMessage: _isConnected 
              ? 'Connected to PostgreSQL server' 
              : 'Failed to connect to server',
            connectionName: databaseName,
          ),
        );
        
        // If connected, fetch initial data
        if (_isConnected) {
          await _fetchDatabaseStats();
          await _fetchResourceStats();
          await _fetchQueryLogs();
          _startPeriodicUpdates();
        }
      } else {
        _isConnected = false;
        _updateConnectionStatus(
          ConnectionStatus.initial().copyWith(
            statusMessage: 'API error: ${response.statusCode}',
          ),
        );
      }
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
  
  // Get or create a session from the API server
  Future<void> _getOrCreateSession() async {
    if (_sessionId != null) {
      return; // Already have a session ID
    }
    
    try {
      final response = await http.get(Uri.parse('$baseUrl/session'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _sessionId = data['sessionId'];
        print('Session established: $_sessionId');
      } else {
        print('Failed to establish session: ${response.statusCode}');
      }
    } catch (e) {
      print('Error establishing session: $e');
    }
  }
  
  // Set the session ID directly (used when the session is created through the ApiConnectionService)
  void setSessionId(String sessionId) {
    _sessionId = sessionId;
    _isConnected = true;
    _checkConnectionStatus(); // Update connection status with the new session
  }

  Future<void> _fetchDatabaseStats() async {
    try {
      if (_sessionId == null) {
        await _getOrCreateSession();
      }
      
      final response = await http.get(Uri.parse('$baseUrl/stats?sessionId=$_sessionId'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Create database info from the API response
        final dbInfo = DatabaseInfo(
          name: data['databaseName'] ?? 'primary',
          sizeInMB: _parseSize(data['size'] ?? '0 kB'),
          activeConnections: data['connections'] ?? 0,
          tables: data['tableCount'] ?? 0,
        );
        
        final stats = DatabaseStats(
          totalDatabases: 1,
          totalTables: data['tableCount'] ?? 0,
          dbSize: _parseSize(data['size'] ?? '0 kB'),
          databases: [dbInfo],
          lastUpdated: DateTime.now(),
        );
        
        // Update connection status with active connections
        _updateConnectionStatus(
          _latestConnectionStatus.copyWith(
            activeConnections: data['connections'] ?? 0,
            lastChecked: DateTime.now(),
          ),
        );
        
        _latestDatabaseStats = stats;
        _databaseStatsController.add(stats);
      }
    } catch (e) {
      print('Error fetching database stats: $e');
    }
  }
  
  Future<void> _fetchResourceStats() async {
    try {
      if (_sessionId == null) {
        await _getOrCreateSession();
      }
      
      final response = await http.get(Uri.parse('$baseUrl/resource-stats?sessionId=$_sessionId'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final now = DateTime.now();
        
        // Extract CPU usage
        final cpuUsage = data['cpu']?['active_query_time'] != null 
          ? (data['cpu']['active_query_time'] as num).toDouble() 
          : 0.0;
        
        // Extract memory info
        final memoryStats = data['memory'] ?? {};
        final memoryUsage = ((memoryStats['used'] ?? 0) / 
          (memoryStats['total'] ?? 1) * 100).clamp(0.0, 100.0);
        
        // Extract disk info
        final diskStats = data['io'] ?? {};  // Updated from disk to io to match backend
        final diskUsage = ((diskStats['heap_read'] ?? 0) + 
          (diskStats['idx_read'] ?? 0)).toDouble();
        
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
      }
    } catch (e) {
      print('Error fetching resource stats: $e');
    }
  }
  
  Future<void> _fetchQueryLogs() async {
    try {
      if (_sessionId == null) {
        await _getOrCreateSession();
      }
      
      final response = await http.get(Uri.parse('$baseUrl/query-logs?sessionId=$_sessionId'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        final logs = data.map((item) {
          final query = item['query'] as String?;
          final duration = item['duration'] != null 
            ? double.tryParse(item['duration'].toString()) ?? 0.0
            : (item['total_time'] != null 
                ? double.tryParse(item['total_time'].toString()) ?? 0.0 
                : 0.0);
          
          // Determine timestamp based on available data
          DateTime timestamp;
          try {
            timestamp = DateTime.parse(item['timestamp'] ?? '');
          } catch (e) {
            timestamp = DateTime.now().subtract(Duration(seconds: duration.ceil()));
          }
          
          return QueryLog(
            query: query ?? 'Unknown query',
            timestamp: timestamp,
            executionTime: duration,
            database: item['database'] ?? 'postgres',
            status: item['state'] ?? 'completed',
            state: item['state'] ?? 'idle',
            applicationName: item['application'] ?? 'PostgreSQL Monitor',
            clientAddress: item['client_addr'] ?? 'localhost',
          );
        }).toList();
        
        _latestQueryLogs = logs;
        _queryLogsController.add(logs);
      }
    } catch (e) {
      print('Error fetching query logs: $e');
    }
  }
  
  Future<List<Map<String, dynamic>>> runQuery(String query) async {
    if (!_isConnected) {
      throw Exception('Not connected to database');
    }
    
    try {
      if (_sessionId == null) {
        await _getOrCreateSession();
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/run-query?sessionId=$_sessionId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'query': query}),
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> results = json.decode(response.body);
        return results.map((item) => item as Map<String, dynamic>).toList();
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Query execution failed');
      }
    } catch (e) {
      print('Error executing query: $e');
      throw Exception('Query execution failed: ${e.toString()}');
    }
  }
  
  void _updateConnectionStatus(ConnectionStatus status) {
    _latestConnectionStatus = status;
    _connectionStatusController.add(status);
  }
  
  void dispose() {
    _statsRefreshTimer?.cancel();
    _resourceStatsTimer?.cancel();
    _connectionStatusController.close();
    _databaseStatsController.close();
    _queryLogsController.close();
    _resourceStatsController.close();
  }
  
  /// Helper to parse size strings like "7496 kB" to MB
  double _parseSize(String sizeStr) {
    try {
      final parts = sizeStr.split(' ');
      if (parts.length != 2) return 0.0;
      
      final value = double.tryParse(parts[0]) ?? 0.0;
      final unit = parts[1].toLowerCase();
      
      switch (unit) {
        case 'b':
          return value / (1024 * 1024);
        case 'kb':
          return value / 1024;
        case 'mb':
          return value;
        case 'gb':
          return value * 1024;
        case 'tb':
          return value * 1024 * 1024;
        default:
          return value / (1024 * 1024); // Assume bytes if unit not recognized
      }
    } catch (e) {
      return 0.0;
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
}