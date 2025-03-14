class ConnectionStatus {
  final bool isConnected;
  final String serverVersion;
  final int activeConnections;
  final int maxConnections;
  final DateTime lastChecked;
  final String statusMessage;
  final String connectionName;

  ConnectionStatus({
    required this.isConnected,
    required this.serverVersion,
    required this.activeConnections,
    required this.maxConnections,
    required this.lastChecked,
    required this.statusMessage,
    this.connectionName = 'Unknown',
  });

  factory ConnectionStatus.initial() {
    return ConnectionStatus(
      isConnected: false,
      serverVersion: 'Unknown',
      activeConnections: 0,
      maxConnections: 0,
      lastChecked: DateTime.now(),
      statusMessage: 'Not connected',
      connectionName: 'None',
    );
  }

  ConnectionStatus copyWith({
    bool? isConnected,
    String? serverVersion,
    int? activeConnections,
    int? maxConnections,
    DateTime? lastChecked,
    String? statusMessage,
    String? connectionName,
  }) {
    return ConnectionStatus(
      isConnected: isConnected ?? this.isConnected,
      serverVersion: serverVersion ?? this.serverVersion,
      activeConnections: activeConnections ?? this.activeConnections,
      maxConnections: maxConnections ?? this.maxConnections,
      lastChecked: lastChecked ?? this.lastChecked,
      statusMessage: statusMessage ?? this.statusMessage,
      connectionName: connectionName ?? this.connectionName,
    );
  }
}