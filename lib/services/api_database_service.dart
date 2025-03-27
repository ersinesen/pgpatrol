import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/connection_status.dart';
import '../models/analysis_result.dart';
import '../models/database_stats.dart';
import '../models/table_stats.dart';
import '../models/query_log.dart';
import '../models/resource_stats.dart';
import '../models/server_connection.dart';
import 'connection_manager.dart';

/// DatabaseService implementation that uses our Node.js API instead of
/// connecting directly to PostgreSQL.
class ApiDatabaseService {
  // Base URL for API requests
  final String baseUrl;
  
  // Session management
  String? _sessionId;
  String? _connectionId;
  String? _connectionName;
  
  // Flag to track if the service is connected to the backend
  bool _isConnected = false;
  Timer? _statsRefreshTimer;
  Timer? _resourceStatsTimer;
  
  // Stream controllers for real-time updates
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _databaseStatsController = StreamController<DatabaseStats>.broadcast();
  final _tableStatsController = StreamController<TableStats>.broadcast();
  final _queryLogsController = StreamController<List<QueryLog>>.broadcast();
  final _resourceStatsController = StreamController<ResourceStats>.broadcast();
  
  // Streams
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  Stream<DatabaseStats> get databaseStats => _databaseStatsController.stream;
  Stream<TableStats> get tableStats => _tableStatsController.stream;
  Stream<List<QueryLog>> get queryLogs => _queryLogsController.stream;
  Stream<ResourceStats> get resourceStats => _resourceStatsController.stream;
  
  // Latest data
  ConnectionStatus _latestConnectionStatus = ConnectionStatus.initial();
  DatabaseStats _latestDatabaseStats = DatabaseStats.initial();
  TableStats _latestTableStats = TableStats.initial();
  List<QueryLog> _latestQueryLogs = [];
  ResourceStats _latestResourceStats = ResourceStats.initial();
  
  // Constructor
  ApiDatabaseService({
    //this.baseUrl = 'https://105d264d-0bf6-4c6c-bb96-741253286912-00-2qmy6a592851x.worf.replit.dev:3001/api',
    this.baseUrl = 'http://localhost:3001/api',
  }) {
    // Will be initialized after connection
  }
  
  /// Connect to a PostgreSQL database using the connection parameters
  Future<bool> connect(ServerConnection connection) async {
    try {
      print('ApiDatabaseService: Connecting to ${connection.name} (ID: ${connection.id})');
      
      // If test is successful, connect to the database
      final response = await http.post(
        Uri.parse('$baseUrl/connect'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'host': connection.host,
          'port': connection.port,
          'database': connection.database,
          'username': connection.username,
          'password': connection.password,
          'name': connection.name,
          'ssl': false, // Enable SSL by default
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success']) {
          // Store session information for subsequent requests
          _sessionId = data['sessionId'];
          _connectionId = data['connectionId'];
          _connectionName = data['name'];
          _isConnected = true;
          
          print('ApiDatabaseService: Connected successfully with session ID: $_sessionId');
          
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
          
          // Store the connection ID on successful connection
          print('ApiDatabaseService: Setting active connection in ConnectionManager');
          
          // Update the connection manager to set this connection as active
          // This ensures all screens know which connection is active
          ConnectionManager().setActiveConnection(connection.id);
          
          // Initialize data fetching
          await _checkConnectionStatus();
          if (_isConnected) {
            await _fetchDatabaseStats();
            await _fetchTableStats();
            await _fetchResourceStats();
            await _fetchQueryLogs();
            _startPeriodicUpdates();
          }
          
          return true;
        } else {
          _updateConnectionStatus(
            ConnectionStatus.initial().copyWith(
              statusMessage: 'Connection failed: ${data['error'] ?? 'Unknown error'}',
            ),
          );
          return false;
        }
      } else {
        _isConnected = false;
        _updateConnectionStatus(
          ConnectionStatus.initial().copyWith(
            statusMessage: 'API error: ${response.statusCode}',
          ),
        );
        return false;
      }
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
    if (!_isConnected || _sessionId == null) {
      return true;
    }
    
    try {
      print('ApiDatabaseService: Disconnecting from database');
      
      // Update connection status to "disconnecting"
      _updateConnectionStatus(
        ConnectionStatus(
          isConnected: true,
          statusMessage: 'Disconnecting...',
          serverVersion: 'PostgreSQL',
          activeConnections: 0,
          maxConnections: 0,
          lastChecked: DateTime.now(),
          connectionName: _connectionName ?? '',
        ),
      );
      
      // Stop refresh timers
      _stopPeriodicUpdates();
      
      // Store connection id before resetting
      final connectionId = _connectionId;
      
      // Reset connection state
      _isConnected = false;
      _sessionId = null;
      _connectionId = null;
      _connectionName = null;
      
      // Update connection status to "disconnected"
      _updateConnectionStatus(
        ConnectionStatus.initial().copyWith(
          statusMessage: 'Disconnected',
        ),
      );
      
      print('ApiDatabaseService: Disconnected successfully');
      
      // Note: We still maintain the active connection in the connection manager
      // This allows the dashboard to show the active connection even when disconnected
      
      return true;
    } catch (e) {
      print('Error disconnecting: ${e.toString()}');
      return false;
    }
  }
  
  /// Test a connection without actually connecting
  Future<Map<String, dynamic>> _testConnection(ServerConnection connection) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/test-connection-params'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'host': connection.host,
          'port': connection.port,
          'database': connection.database,
          'username': connection.username,
          'password': connection.password,
          'ssl': false, // Enable SSL by default
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Connection test completed',
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'message': 'Connection test failed: ${errorData['error'] ?? 'Unknown error'}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection test error: ${e.toString()}',
      };
    }
  }
  
  Future<void> _checkConnectionStatus() async {
    if (_sessionId == null) {
      _isConnected = false;
      _updateConnectionStatus(
        ConnectionStatus.initial().copyWith(
          statusMessage: 'No active session',
        ),
      );
      return;
    }
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/connection'),
        headers: {'X-Session-ID': _sessionId!},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        _isConnected = data['status'] == 'connected';
        
        // Extract additional connection info if available
        final serverVersion = data['version'] ?? 'PostgreSQL';
        final databaseName = data['databaseName'] ?? _connectionName ?? 'Database';
        
        _updateConnectionStatus(
          ConnectionStatus(
            isConnected: _isConnected,
            serverVersion: serverVersion,
            activeConnections: 0, // Will be updated with database stats
            maxConnections: 100, // Default value
            lastChecked: DateTime.now(),
            statusMessage: _isConnected 
              ? 'Connected to $databaseName' 
              : 'Disconnected from database',
            connectionName: databaseName,
          ),
        );
        
        // If connected, start periodic updates if not already running
        if (_isConnected && _statsRefreshTimer == null) {
          _startPeriodicUpdates();
        } else if (!_isConnected) {
          // Reset timers if disconnected
          _statsRefreshTimer?.cancel();
          _resourceStatsTimer?.cancel();
          _statsRefreshTimer = null;
          _resourceStatsTimer = null;
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
        await _fetchTableStats();
      } else {
        await _checkConnectionStatus();
      }
    });
    
    // Fetch resource stats every 5 seconds
    _resourceStatsTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_isConnected) {
        await _fetchResourceStats();
      }
    });
  }
  
  Future<void> _fetchDatabaseStats() async {
    if (_sessionId == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/stats'),
        headers: {'X-Session-ID': _sessionId!},
      );
      
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

  Future<void> _fetchTableStats() async {
    if (_sessionId == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/table-stats'),
        headers: {'X-Session-ID': _sessionId!},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Create database info from the API response
        var tableList = data['tableSizes'];
        var tables = List<TableInfo>.empty(growable: true);

        tableList.forEach((table) {
          final tableInfo = TableInfo(
            name: table['table_name'] ?? 'Unknown Table',
            size: _parseSize(table['total_size'] ?? '0 kB'),
          );
          tables.add(tableInfo);
        });
        
        final stats = TableStats(
          totalTables: tables.length ?? 0,
          tables: tables,
          lastUpdated: DateTime.now(),
        );
                
        _latestTableStats = stats;
        _tableStatsController.add(stats);
      }
    } catch (e) {
      print('Error fetching database stats: $e');
    }
  }
  
  Future<void> _fetchResourceStats() async {
    if (_sessionId == null) return;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/resource-stats'),
        headers: {'X-Session-ID': _sessionId!},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final now = DateTime.now();
        print(data);

        // Extract CPU, Memory, and Disk Usage
        final cpuUsage = (data['cpuUsage'] as num).toDouble();
        final memoryUsage = (data['memoryUsage'] as num) / (1024 * 1024); // Convert to MB
        final diskUsage = (data['diskUsage'] as num) / (1024 * 1024 * 1024); // Convert to GB

        // Maintain Historical Data (Last 30 points)
        final newCpuHistory = List<TimeSeriesData>.from(_latestResourceStats.historicalCpuUsage);
        final newMemoryHistory = List<TimeSeriesData>.from(_latestResourceStats.historicalMemoryUsage);
        final newDiskHistory = List<TimeSeriesData>.from(_latestResourceStats.historicalDiskUsage);

        newCpuHistory.add(TimeSeriesData(time: now, value: cpuUsage));
        newMemoryHistory.add(TimeSeriesData(time: now, value: memoryUsage));
        newDiskHistory.add(TimeSeriesData(time: now, value: diskUsage));

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
    if (_sessionId == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/query-logs'),
        headers: {'X-Session-ID': _sessionId!},
      );
      
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
            timestamp = item['query_start'] != null
              ? DateTime.parse(item['query_start'])
              : DateTime.now().subtract(Duration(seconds: duration.ceil()));
          } catch (e) {
            timestamp = DateTime.now().subtract(Duration(seconds: duration.ceil()));
          }
          
          return QueryLog(
            query: query ?? 'Unknown query',
            timestamp: timestamp,
            executionTime: duration,
            database: item['database'] ?? _connectionName ?? 'postgres',
            status: item['state'] ?? 'completed',
            state: item['state'] ?? 'idle',
            applicationName: item['application_name'] ?? 'PostgreSQL Monitor',
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
    if (!_isConnected || _sessionId == null) {
      throw Exception('Not connected to database');
    }
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/run-query'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-ID': _sessionId!,
        },
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
  

  
  Future<List<ServerConnection>> getAvailableConnections() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/connections'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        return data.map((item) {
          return ServerConnection(
            id: item['id'] ?? '',
            name: item['name'] ?? 'Unnamed',
            host: '', // These details are not returned by the API
            port: 0,
            database: '',
            username: '',
            password: '',
            isActive: _connectionId == item['id'],
          );
        }).toList();
      } else {
        return [];
      }
    } catch (e) {
      print('Error fetching connections: $e');
      return [];
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
    _tableStatsController.close();
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
  
  TableStats getTableStats() {
    return _latestTableStats;
  }

  ResourceStats getResourceStats() {
    return _latestResourceStats;
  }
  
  List<QueryLog> getQueryLogs() {
    return _latestQueryLogs;
  }
  
  bool isConnected() {
    return _isConnected && _sessionId != null;
  }
  
  // Stream getters
  Stream<DatabaseStats> get databaseStatsStream => _databaseStatsController.stream;
  Stream<TableStats> get tableStatsStream => _tableStatsController.stream;
  Stream<List<QueryLog>> get queryLogsStream => _queryLogsController.stream;
  Stream<ResourceStats> get resourceStatsStream => _resourceStatsController.stream;
  
  /// Execute database analysis with a specific key
  /// 
  /// The key parameter specifies which analysis to run on the backend.
  /// Possible values include:
  /// - 'deadlocks': Shows deadlock information
  /// - 'long_running_queries': Shows queries running for more than a specific duration
  /// - 'table_bloat': Shows tables with bloat (unused space)
  /// - 'index_usage': Shows index usage statistics
  /// - 'cache_hit_ratio': Shows cache hit ratio information
  /// 
  /// @param key The analysis key to execute
  /// @return AnalysisResult containing the analysis data
  Future<AnalysisResult> analyze(String key) async {
    if (_sessionId == null || !_isConnected) {
      return AnalysisResult.empty(key);
    }
    
    try {
      // Use query parameter instead of header for key
      final response = await http.get(
        Uri.parse('$baseUrl/analyze?key=$key'),
        headers: {
          'X-Session-ID': _sessionId!,
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return AnalysisResult.fromJson(data);
      } else {
        print('Error executing analysis: ${response.statusCode}');
        return AnalysisResult.empty(key);
      }
    } catch (e) {
      print('Exception executing analysis: $e');
      return AnalysisResult.empty(key);
    }
  }
}