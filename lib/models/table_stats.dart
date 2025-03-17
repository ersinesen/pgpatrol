class TableStats {
  final int totalTables;
  final List<TableInfo> tables;
  final DateTime lastUpdated;

  TableStats({
    required this.totalTables,
    required this.tables,
    required this.lastUpdated,
  });

  factory TableStats.initial() {
    return TableStats(
      totalTables: 0,
      tables: [],
      lastUpdated: DateTime.now(),
    );
  }
}

class TableInfo {
  final String name;
  final double size;

  TableInfo({
    required this.name,
    required this.size,
  });
}