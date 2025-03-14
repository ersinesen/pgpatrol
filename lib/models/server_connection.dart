import 'package:flutter/foundation.dart';

class ServerConnection {
  final String id; // Unique identifier for the connection
  final String name; // User-friendly name for the connection
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final bool isActive; // Whether this is the currently active connection
  final bool useSSL; // Whether to use SSL for the connection

  ServerConnection({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    this.isActive = false,
    this.useSSL = false,
  });

  // Constructor for creating a default connection
  factory ServerConnection.defaultConnection() {
    return ServerConnection(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Default Connection',
      host: 'localhost',
      port: 5432,
      database: 'postgres',
      username: 'postgres',
      password: 'postgres',
      isActive: true,
      useSSL: false,
    );
  }

  // Create a copy of this connection with some fields replaced
  ServerConnection copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
    bool? isActive,
    bool? useSSL,
  }) {
    return ServerConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      password: password ?? this.password,
      isActive: isActive ?? this.isActive,
      useSSL: useSSL ?? this.useSSL,
    );
  }

  // Convert connection to a map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'database': database,
      'username': username,
      'password': password,
      'isActive': isActive,
      'useSSL': useSSL,
    };
  }

  // Create a connection from a map
  factory ServerConnection.fromMap(Map<String, dynamic> map) {
    return ServerConnection(
      id: map['id'],
      name: map['name'],
      host: map['host'],
      port: map['port'],
      database: map['database'],
      username: map['username'],
      password: map['password'],
      isActive: map['isActive'] ?? false,
      useSSL: map['useSSL'] ?? false,
    );
  }

  // Get connection string
  String getConnectionString() {
    return 'postgresql://$username:$password@$host:$port/$database';
  }

  @override
  String toString() {
    return 'ServerConnection{id: $id, name: $name, host: $host, port: $port, database: $database, username: $username, isActive: $isActive, useSSL: $useSSL}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is ServerConnection &&
        other.id == id &&
        other.name == name &&
        other.host == host &&
        other.port == port &&
        other.database == database &&
        other.username == username &&
        other.password == password &&
        other.isActive == isActive &&
        other.useSSL == useSSL;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        host.hashCode ^
        port.hashCode ^
        database.hashCode ^
        username.hashCode ^
        password.hashCode ^
        isActive.hashCode ^
        useSSL.hashCode;
  }
}