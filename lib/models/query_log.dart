class QueryLog {
  final String query;
  final DateTime timestamp;
  final double executionTime;
  final String database;
  final String status;
  final String? error;
  final String state;
  final String applicationName;
  final String clientAddress;

  QueryLog({
    required this.query,
    required this.timestamp,
    required this.executionTime,
    required this.database,
    required this.status,
    this.error,
    this.state = 'idle',
    this.applicationName = 'PostgreSQL Monitor',
    this.clientAddress = 'localhost',
  });

  factory QueryLog.fromMap(Map<String, dynamic> map) {
    return QueryLog(
      query: map['query'] ?? '',
      timestamp: DateTime.parse(map['timestamp'] ?? DateTime.now().toIso8601String()),
      executionTime: (map['execution_time'] ?? 0.0).toDouble(),
      database: map['database'] ?? '',
      status: map['status'] ?? 'unknown',
      error: map['error'],
      state: map['state'] ?? 'idle',
      applicationName: map['application_name'] ?? 'PostgreSQL Monitor',
      clientAddress: map['client_address'] ?? 'localhost',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'query': query,
      'timestamp': timestamp.toIso8601String(),
      'execution_time': executionTime,
      'database': database,
      'status': status,
      'error': error,
      'state': state,
      'application_name': applicationName,
      'client_address': clientAddress,
    };
  }
  
  String get formattedDuration {
    if (executionTime < 1) {
      return '${(executionTime * 1000).toStringAsFixed(2)} ms';
    } else if (executionTime < 60) {
      return '${executionTime.toStringAsFixed(2)} s';
    } else {
      int minutes = (executionTime / 60).floor();
      double seconds = executionTime % 60;
      return '$minutes m ${seconds.toStringAsFixed(2)} s';
    }
  }
}