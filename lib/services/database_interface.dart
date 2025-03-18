import 'dart:async';

import '../models/connection_status.dart';
import '../models/database_stats.dart';
import '../models/query_log.dart';
import '../models/resource_stats.dart';
import '../models/server_connection.dart';

/// Abstract interface for database services to ensure API and direct implementations
/// provide the same methods and functionality
abstract class DatabaseInterface {
  // Connection management
  Future<bool> connect(ServerConnection connection);
  Future<bool> disconnect();
  Future<Map<String, dynamic>> testConnection(ServerConnection connection);
  
  // Data streams
  Stream<ConnectionStatus> get connectionStatus;
  Stream<DatabaseStats> get databaseStatsStream;
  Stream<List<QueryLog>> get queryLogsStream;
  Stream<ResourceStats> get resourceStatsStream;
  
  // Current state getters
  ConnectionStatus getConnectionStatus();
  DatabaseStats getDatabaseStats();
  ResourceStats getResourceStats();
  List<QueryLog> getQueryLogs();
  bool isConnected();
  
  // Service cleanup
  void dispose();
}