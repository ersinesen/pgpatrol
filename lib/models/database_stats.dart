class DatabaseStats {
  final int totalDatabases;
  final int totalTables;
  final double dbSize;
  final List<DatabaseInfo> databases;
  final DateTime lastUpdated;

  DatabaseStats({
    required this.totalDatabases,
    required this.totalTables,
    required this.dbSize,
    required this.databases,
    required this.lastUpdated,
  });

  factory DatabaseStats.initial() {
    return DatabaseStats(
      totalDatabases: 0,
      totalTables: 0,
      dbSize: 0.0,
      databases: [],
      lastUpdated: DateTime.now(),
    );
  }
}

class DatabaseInfo {
  final String name;
  final int tables;
  final double sizeInMB;
  final int activeConnections;

  DatabaseInfo({
    required this.name,
    required this.tables,
    required this.sizeInMB,
    required this.activeConnections,
  });
}