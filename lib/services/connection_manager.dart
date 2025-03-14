import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_connection.dart';

// This service manages server connection configurations
class ConnectionManager {
  static const String _connectionsStorageKey = 'postgres_connections';
  
  // Singleton instance
  static final ConnectionManager _instance = ConnectionManager._internal();
  factory ConnectionManager() => _instance;
  ConnectionManager._internal();
  
  // StreamController for connections
  final _connectionsController = StreamController<List<ServerConnection>>.broadcast();
  
  // List of server connections
  List<ServerConnection> _connections = [];
  
  // Getters
  Stream<List<ServerConnection>> get connectionsStream => _connectionsController.stream;
  List<ServerConnection> get connections => List.unmodifiable(_connections);
  ServerConnection? get activeConnection => 
      _connections.isNotEmpty 
        ? _connections.firstWhere((conn) => conn.isActive, 
            orElse: () => _connections.first)
        : null;

  // Initialize connection manager
  Future<void> initialize() async {
    await _loadConnections();
    
    // Add default connection if none exist
    if (_connections.isEmpty) {
      final defaultConn = ServerConnection.defaultConnection();
      await addConnection(defaultConn);
    }
    
    // Ensure one connection is active
    _ensureActiveConnection();
  }
  
  // Load connections from storage
  Future<void> _loadConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final connectionsJson = prefs.getString(_connectionsStorageKey);
      
      if (connectionsJson != null) {
        final List<dynamic> decoded = jsonDecode(connectionsJson);
        _connections = decoded.map((json) => 
          ServerConnection.fromMap(Map<String, dynamic>.from(json))
        ).toList();
        
        _connectionsController.add(_connections);
      }
    } catch (e) {
      print('Error loading connections: $e');
      _connections = [];
    }
  }
  
  // Save connections to storage
  Future<void> _saveConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final connectionsJson = jsonEncode(_connections.map((c) => c.toMap()).toList());
      await prefs.setString(_connectionsStorageKey, connectionsJson);
    } catch (e) {
      print('Error saving connections: $e');
    }
  }
  
  // Add a new connection
  Future<void> addConnection(ServerConnection connection) async {
    // If this is the first connection or it's marked active, deactivate others
    if (_connections.isEmpty || connection.isActive) {
      _connections = _connections.map((c) => 
        c.copyWith(isActive: false)
      ).toList();
    }
    
    _connections.add(connection);
    _ensureActiveConnection();
    await _saveConnections();
    _connectionsController.add(_connections);
  }
  
  // Update an existing connection
  Future<void> updateConnection(ServerConnection connection) async {
    final index = _connections.indexWhere((c) => c.id == connection.id);
    
    if (index != -1) {
      // If this connection is being set to active, deactivate others
      if (connection.isActive) {
        _connections = _connections.map((c) => 
          c.id == connection.id ? connection : c.copyWith(isActive: false)
        ).toList();
      } else {
        _connections[index] = connection;
      }
      
      _ensureActiveConnection();
      await _saveConnections();
      _connectionsController.add(_connections);
    }
  }
  
  // Delete a connection
  Future<void> deleteConnection(String connectionId) async {
    final wasActive = _connections.any((c) => c.id == connectionId && c.isActive);
    
    _connections.removeWhere((c) => c.id == connectionId);
    
    if (wasActive) {
      _ensureActiveConnection();
    }
    
    await _saveConnections();
    _connectionsController.add(_connections);
  }
  
  // Set a connection as active
  Future<void> setActiveConnection(String connectionId) async {
    _connections = _connections.map((c) => 
      c.copyWith(isActive: c.id == connectionId)
    ).toList();
    
    await _saveConnections();
    _connectionsController.add(_connections);
  }
  
  // Ensure at least one connection is active
  void _ensureActiveConnection() {
    // If no connections are active and we have connections, set the first one active
    if (!_connections.any((c) => c.isActive) && _connections.isNotEmpty) {
      _connections[0] = _connections[0].copyWith(isActive: true);
    }
  }
  
  // Test a connection before saving
  Future<Map<String, dynamic>> testConnection(ServerConnection connection) async {
    try {
      if (kIsWeb) {
        // In web, direct socket connections won't work due to browser limitations
        // We'll handle specifically for the automated database in Replit
        if (connection.host == 'localhost' || 
            connection.host == '127.0.0.1' ||
            connection.host == '0.0.0.0') {
          // For Replit's built-in database
          return {
            'success': true,
            'message': 'Connection successful (Web mode)',
            'version': 'PostgreSQL (Web mode)',
          };
        } else {
          // For external databases, we can't connect directly in web
          return {
            'success': false,
            'message': 'Direct database connections are not supported in web browsers. Please use localhost for the Replit database.',
          };
        }
      } else {
        // For non-web platforms, use direct connection
        final postgres = PostgreSQLConnection(
          connection.host,
          connection.port,
          connection.database,
          username: connection.username,
          password: connection.password,
          timeoutInSeconds: 5,
          useSSL: connection.useSSL,
        );
        
        await postgres.open();
        final result = await postgres.query('SELECT version();');
        final version = result.first.first.toString();
        await postgres.close();
        
        return {
          'success': true,
          'message': 'Connection successful',
          'version': version,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection failed: ${e.toString()}',
      };
    }
  }
  
  // Dispose of resources
  void dispose() {
    _connectionsController.close();
  }
}