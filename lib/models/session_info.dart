import 'package:flutter/foundation.dart';

/// Model class to store session information received from the backend
class SessionInfo {
  final String sessionId;
  final String connectionId;
  final String connectionName;
  final bool isConnected;

  /// Constructor
  SessionInfo({
    required this.sessionId,
    required this.connectionId,
    required this.connectionName,
    this.isConnected = true,
  });

  /// Factory to create from API response
  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      sessionId: json['sessionId'] ?? '',
      connectionId: json['connectionId'] ?? '',
      connectionName: json['name'] ?? 'Unknown',
      isConnected: json['success'] ?? false,
    );
  }

  /// Create a copy with some fields replaced
  SessionInfo copyWith({
    String? sessionId,
    String? connectionId,
    String? connectionName,
    bool? isConnected,
  }) {
    return SessionInfo(
      sessionId: sessionId ?? this.sessionId,
      connectionId: connectionId ?? this.connectionId,
      connectionName: connectionName ?? this.connectionName,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  /// Convert to map
  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'connectionId': connectionId,
      'connectionName': connectionName,
      'isConnected': isConnected,
    };
  }

  @override
  String toString() {
    return 'SessionInfo{sessionId: $sessionId, connectionId: $connectionId, connectionName: $connectionName, isConnected: $isConnected}';
  }

  /// Empty session info constructor
  factory SessionInfo.empty() {
    return SessionInfo(
      sessionId: '',
      connectionId: '',
      connectionName: '',
      isConnected: false,
    );
  }
}