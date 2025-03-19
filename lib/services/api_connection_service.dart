import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server_connection.dart';

class ApiConnectionService {
  // The base URL of the backend API
  final String baseUrl = 'https://105d264d-0bf6-4c6c-bb96-741253286912-00-2qmy6a592851x.worf.replit.dev:3001';
  //final String baseUrl = 'http://localhost:3001';
 
  // Test connection with the provided parameters
  Future<Map<String, dynamic>> testConnection(ServerConnection connection) async {
    final url = Uri.parse('$baseUrl/api/test-connection-params');
    print('URL: $url');
    
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'host': connection.host,
          'port': connection.port,
          'database': connection.database,
          'username': connection.username,
          'password': connection.password,
          'ssl': true, // Enable SSL mode by default
        }),
      );

      print('Response: $response');
      
      if (response.statusCode == 200) {
        return {
          'success': false,
          'message': 'Connection successful',
          'data': jsonDecode(response.body),
        };
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'message': 'Connection failed: ${errorData['error'] ?? 'Unknown error'}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection failed: ${e.toString()}',
      };
    }
  }
}