import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/connection_status.dart';
import '../models/database_stats.dart';
import '../models/query_log.dart';
import '../models/resource_stats.dart';
import '../models/server_connection.dart';
import 'database_interface.dart';

/// API-based implementation of DatabaseInterface that connects to PostgreSQL
/// through the Node.js backend API. Used for web and mobile platforms.
class ApiService implements DatabaseInterface {
  static const String baseUrl = 'http://localhost:3001/api';
  
  // API session details
  String? _sessionId;
  String? _connectionId;
  String? _connectionName;
  
  // Connection state
  bool _isConnected = false;
  Timer? _statsRefreshTimer;
  Timer? _resourceStatsTimer;
  
  // Stream controllers for real-time updates
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _databaseStatsController = StreamController<DatabaseStats>.broadcast();
  final _queryLogsController = StreamController<List<QueryLog>>.broadcast();
  final _resourceStatsController = StreamController<ResourceStats>.broadcast();
  
  // Streams
  @override
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  
  @override
  Stream<DatabaseStats> get databaseStatsStream => _databaseStatsController.stream;
  
  @override
  Stream<List<QueryLog>> get queryLogsStream => _queryLogsController.stream;
  
  @override
  Stream<ResourceStats> get resourceStatsStream => _resourceStatsController.stream;
  
  // Latest data
  ConnectionStatus _latestConnectionStatus = ConnectionStatus.initial();
  DatabaseStats _latestDatabaseStats = DatabaseStats.initial();
  List<QueryLog> _latestQueryLogs = [];
  ResourceStats _latestResourceStats = ResourceStats.initial();
  
  // Constructor - Use as a singleton
  static final ApiService _instance = ApiService._internal();
  
  factory ApiService() {
    return _instance;
  }
  
  ApiService._internal() {
    // Initialize session
    _initSession();
  }
  
  /// Initialize API session
  Future<void> _initSession() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/session'));
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        _sessionId = jsonResponse['sessionId'];
        print('ApiService: Session initialized with ID: $_sessionId');
      } else {
        print('ApiService: Failed to initialize session: ${response.statusCode}');
      }
    } catch (e) {
      print('ApiService: Error initializing session: $e');
    }
  }
  
  /// Connect to a PostgreSQL database using the connection parameters
  @override
  Future<bool> connect(ServerConnection connection) async {
    try {
      // Ensure we have a session
      if (_sessionId == null) {
        await _initSession();
      }
      
      print('ApiService: Connecting to ${connection.name} (ID: ${connection.id})');
      
      // Prepare request body
      final requestBody = {
        'host': connection.host,
        'port': connection.port,
        'database': connection.database,
        'username': connection.username,
        'password': connection.password,
        'name': connection.name,
        'ssl': connection.useSSL,
      };
      
      // Make API request to connect
      final response = await http.post(
        Uri.parse('$baseUrl/connect'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-ID': _sessionId ?? '',
        },
        body: json.encode(requestBody),
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        
        if (jsonResponse['success'] == true) {
          // Store connection details
          _connectionId = jsonResponse['connectionId'];
          _connectionName = jsonResponse['name'];
          _isConnected = true;
          
          print('ApiService: Connected successfully to ${connection.name}');
          
          // Start data fetching
          await _fetchConnectionStatus();
          await _fetchDatabaseStats();
          await _fetchResourceStats();
          await _fetchQueryLogs();
          _startPeriodicUpdates();
          
          return true;
        } else {
          print('ApiService: Failed to connect: ${jsonResponse['error']}');
          _updateConnectionStatus(
            ConnectionStatus.initial().copyWith(
              statusMessage: 'Connection error: ${jsonResponse['error']}',
            ),
          );
          return false;
        }
      } else {
        print('ApiService: Connection request failed with status ${response.statusCode}');
        _updateConnectionStatus(
          ConnectionStatus.initial().copyWith(
            statusMessage: 'Connection error: HTTP ${response.statusCode}',
          ),
        );
        return false;
      }
    } catch (e) {
      print('ApiService: Error connecting: $e');
      _updateConnectionStatus(
        ConnectionStatus.initial().copyWith(
          statusMessage: 'Connection error: ${e.toString()}',
        ),
      );
      return false;
    }
  }
  
  /// Disconnect from the currently connected database
  @override
  Future<bool> disconnect() async {
    if (!_isConnected || _connectionId == null) {
      return true;
    }
    
    try {
      print('ApiService: Disconnecting from database');
      
      // Update connection status to "disconnecting"
      _updateConnectionStatus(
        _latestConnectionStatus.copyWith(
          statusMessage: 'Disconnecting...',
        ),
      );
      
      // Stop refresh timers
      _stopPeriodicUpdates();
      
      // Make API request to disconnect (if implemented on backend)
      // For now, we'll just update our internal state
      
      // Reset connection state
      _isConnected = false;
      _connectionId = null;
      _connectionName = null;
      
      // Update connection status to "disconnected"
      _updateConnectionStatus(
        ConnectionStatus.initial().copyWith(
          statusMessage: 'Disconnected',
        ),
      );
      
      print('ApiService: Disconnected successfully');
      
      return true;
    } catch (e) {
      print('Error disconnecting: ${e.toString()}');
      return false;
    }
  }
  
  /// Test a connection without fully connecting
  @override
  Future<Map<String, dynamic>> testConnection(ServerConnection connection) async {
    try {
      print('ApiService: Testing connection to ${connection.host}:${connection.port}/${connection.database}');
      
      // Prepare request body
      final requestBody = {
        'host': connection.host,
        'port': connection.port,
        'database': connection.database,
        'username': connection.username,
        'password': connection.password,
        'ssl': connection.useSSL,
      };
      
      // Make API request to test connection
      final response = await http.post(
        Uri.parse('$baseUrl/test-connection-params'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Connection test failed: HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection test failed: ${e.toString()}',
      };
    }
  }
  
  // Fetch connection status from API
  Future<void> _fetchConnectionStatus() async {
    if (_sessionId == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/connection'),
        headers: {
          'X-Session-ID': _sessionId!,
        },
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        
        if (jsonResponse['status'] == 'connected') {
          _isConnected = true;
          _updateConnectionStatus(
            ConnectionStatus(
              isConnected: true,
              serverVersion: jsonResponse['version'] ?? 'PostgreSQL',
              activeConnections: 0, // Will be updated with stats
              maxConnections: 100, // Default
              lastChecked: DateTime.now(),
              statusMessage: 'Connected to $_connectionName',
              connectionName: _connectionName ?? 'Database',
            ),
          );
        } else {
          _isConnected = false;
          _updateConnectionStatus(
            ConnectionStatus.initial().copyWith(
              statusMessage: 'Disconnected: ${jsonResponse['error'] ?? 'Unknown error'}',
            ),
          );
        }
      } else {
        _isConnected = false;
        _updateConnectionStatus(
          ConnectionStatus.initial().copyWith(
            statusMessage: 'Connection status error: HTTP ${response.statusCode}',
          ),
        );
      }
    } catch (e) {
      print('ApiService: Error fetching connection status: $e');
      
      // Check if the error indicates we've lost connection
      _isConnected = false;
      _updateConnectionStatus(
        ConnectionStatus.initial().copyWith(
          statusMessage: 'Connection lost: ${e.toString()}',
        ),
      );
      
      // Stop the timers if we've lost connection
      _stopPeriodicUpdates();
    }
  }
  
  // Start periodic data updates
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
        await _fetchConnectionStatus();
      }
    });
    
    // Fetch resource stats every 2 seconds
    _resourceStatsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_isConnected) {
        await _fetchResourceStats();
      }
    });
  }
  
  // Stop periodic updates
  void _stopPeriodicUpdates() {
    _statsRefreshTimer?.cancel();
    _resourceStatsTimer?.cancel();
    _statsRefreshTimer = null;
    _resourceStatsTimer = null;
  }
  
  // Fetch database stats from API
  Future<void> _fetchDatabaseStats() async {
    if (!_isConnected || _sessionId == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/stats'),
        headers: {
          'X-Session-ID': _sessionId!,
        },
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        
        // Parse database size (e.g., "24 MB" -> 24.0)
        final sizeString = jsonResponse['size'] ?? '0 kB';
        final dbSize = _parseSize(sizeString);
        
        // Create database info list
        final dbInfo = DatabaseInfo(
          name: jsonResponse['databaseName'] ?? 'Unknown',
          sizeInMB: dbSize,
          tables: jsonResponse['tableCount'] ?? 0,
          activeConnections: jsonResponse['connections'] ?? 0,
        );
        
        // Create stats object
        final stats = DatabaseStats(
          totalDatabases: 1, // API only provides current DB info
          totalTables: jsonResponse['tableCount'] ?? 0,
          dbSize: dbSize,
          databases: [dbInfo],
          lastUpdated: DateTime.now(),
        );
        
        _latestDatabaseStats = stats;
        _databaseStatsController.add(stats);
      }
    } catch (e) {
      print('ApiService: Error fetching database stats: $e');
    }
  }
  
  // Fetch resource statistics from API
  Future<void> _fetchResourceStats() async {
    if (!_isConnected || _sessionId == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/resource-stats'),
        headers: {
          'X-Session-ID': _sessionId!,
        },
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final now = DateTime.now();
        
        // Parse values
        final cpuUsage = jsonResponse['cpuPercent'] ?? 0.0;
        final memoryUsage = jsonResponse['memoryUsageMB'] ?? 0.0;
        final diskUsage = jsonResponse['diskPercent'] ?? 0.0;
        
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
      print('ApiService: Error fetching resource stats: $e');
    }
  }
  
  // Fetch query logs from API
  Future<void> _fetchQueryLogs() async {
    if (!_isConnected || _sessionId == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/query-logs'),
        headers: {
          'X-Session-ID': _sessionId!,
        },
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final logs = <QueryLog>[];
        
        if (jsonResponse is List) {
          for (final item in jsonResponse) {
            try {
              logs.add(QueryLog(
                query: item['query'] ?? 'Unknown query',
                state: item['state'] ?? 'unknown',
                status: item['status'] ?? 'unknown',
                executionTime: item['executionTime'] ?? 0.0,
                database: item['database'] ?? 'unknown',
                timestamp: item['timestamp'] != null
                    ? DateTime.parse(item['timestamp'])
                    : DateTime.now(),
                applicationName: item['applicationName'] ?? 'unknown',
                clientAddress: item['clientAddress'] ?? 'unknown',
              ));
            } catch (e) {
              print('ApiService: Error parsing query log: $e');
            }
          }
        }
        
        _latestQueryLogs = logs;
        _queryLogsController.add(logs);
      }
    } catch (e) {
      print('ApiService: Error fetching query logs: $e');
    }
  }
  
  // Update connection status and send to stream
  void _updateConnectionStatus(ConnectionStatus status) {
    _latestConnectionStatus = status;
    _connectionStatusController.add(status);
  }
  
  @override
  void dispose() {
    _statsRefreshTimer?.cancel();
    _resourceStatsTimer?.cancel();
    _connectionStatusController.close();
    _databaseStatsController.close();
    _queryLogsController.close();
    _resourceStatsController.close();
  }
  
  // Getter methods for current values (for StreamBuilder initialData)
  @override
  ConnectionStatus getConnectionStatus() {
    return _latestConnectionStatus;
  }
  
  @override
  DatabaseStats getDatabaseStats() {
    return _latestDatabaseStats;
  }
  
  @override
  ResourceStats getResourceStats() {
    return _latestResourceStats;
  }
  
  @override
  List<QueryLog> getQueryLogs() {
    return _latestQueryLogs;
  }
  
  @override
  bool isConnected() {
    return _isConnected;
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