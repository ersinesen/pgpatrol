import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/server_connection.dart';
import '../models/session_info.dart';

/// Service responsible for handling API connections to the backend
class ApiConnectionService {
  // Base URL for API requests
  final String baseUrl;
  
  // Current session information
  SessionInfo? _currentSession;
  
  // Stream controllers
  final _connectionResultController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Streams
  Stream<Map<String, dynamic>> get connectionResult => _connectionResultController.stream;
  
  // Constructor
  ApiConnectionService({
    this.baseUrl = '/api', // Default to relative URL for same-origin requests
  });
  
  /// Test a database connection using parameters
  Future<Map<String, dynamic>> testConnectionParams(ServerConnection connection) async {
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
          'ssl': connection.useSSL,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = {
          'success': data['success'] ?? false,
          'message': data['success'] ? 'Connection successful!' : data['error'] ?? 'Unknown error',
          'version': data['version'] ?? 'Unknown',
        };
        
        _connectionResultController.add(result);
        return result;
      } else {
        final data = json.decode(response.body);
        final result = {
          'success': false,
          'message': data['error'] ?? 'HTTP Error: ${response.statusCode}',
        };
        
        _connectionResultController.add(result);
        return result;
      }
    } catch (e) {
      final result = {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
      
      _connectionResultController.add(result);
      return result;
    }
  }
  
  /// Test a database connection using connection string
  Future<Map<String, dynamic>> testConnectionString(String connectionString) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/test-connection'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'connectionString': connectionString,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = {
          'success': data['success'] ?? false,
          'message': data['success'] ? 'Connection successful!' : data['error'] ?? 'Unknown error',
          'version': data['version'] ?? 'Unknown',
        };
        
        _connectionResultController.add(result);
        return result;
      } else {
        final data = json.decode(response.body);
        final result = {
          'success': false,
          'message': data['error'] ?? 'HTTP Error: ${response.statusCode}',
        };
        
        _connectionResultController.add(result);
        return result;
      }
    } catch (e) {
      final result = {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
      
      _connectionResultController.add(result);
      return result;
    }
  }
  
  /// Connect to a database using parameters and get a session
  Future<SessionInfo?> connect(ServerConnection connection) async {
    try {
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
          'ssl': connection.useSSL,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          _currentSession = SessionInfo.fromJson(data);
          return _currentSession;
        } else {
          _connectionResultController.add({
            'success': false,
            'message': data['error'] ?? 'Failed to establish connection',
          });
          return null;
        }
      } else {
        final data = json.decode(response.body);
        _connectionResultController.add({
          'success': false,
          'message': data['error'] ?? 'HTTP Error: ${response.statusCode}',
        });
        return null;
      }
    } catch (e) {
      _connectionResultController.add({
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      });
      return null;
    }
  }
  
  /// Connect using connection string
  Future<SessionInfo?> connectWithString(String connectionString, String name) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/connect-string'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'connectionString': connectionString,
          'name': name,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          _currentSession = SessionInfo.fromJson(data);
          return _currentSession;
        } else {
          _connectionResultController.add({
            'success': false,
            'message': data['error'] ?? 'Failed to establish connection',
          });
          return null;
        }
      } else {
        final data = json.decode(response.body);
        _connectionResultController.add({
          'success': false,
          'message': data['error'] ?? 'HTTP Error: ${response.statusCode}',
        });
        return null;
      }
    } catch (e) {
      _connectionResultController.add({
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      });
      return null;
    }
  }
  
  /// Set active database for the current session
  Future<bool> setActiveConnection(String connectionId) async {
    if (_currentSession == null) {
      return false;
    }
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/set-active-connection'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-ID': _currentSession!.sessionId,
        },
        body: json.encode({
          'connectionId': connectionId,
        }),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('Error setting active connection: $e');
      return false;
    }
  }
  
  /// Get the current session
  SessionInfo? get currentSession => _currentSession;
  
  /// Set the current session
  set currentSession(SessionInfo? session) {
    _currentSession = session;
  }
  
  /// Dispose resources
  void dispose() {
    _connectionResultController.close();
  }
}