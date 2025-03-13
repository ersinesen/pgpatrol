class ResourceStats {
  final double cpuUsage;
  final double memoryUsage;
  final double diskUsage;
  final List<TimeSeriesData> historicalCpuUsage;
  final List<TimeSeriesData> historicalMemoryUsage;
  final List<TimeSeriesData> historicalDiskUsage;
  final DateTime timestamp;

  ResourceStats({
    required this.cpuUsage,
    required this.memoryUsage,
    required this.diskUsage,
    required this.historicalCpuUsage,
    required this.historicalMemoryUsage,
    required this.historicalDiskUsage,
    required this.timestamp,
  });

  factory ResourceStats.initial() {
    return ResourceStats(
      cpuUsage: 0.0,
      memoryUsage: 0.0,
      diskUsage: 0.0,
      historicalCpuUsage: [],
      historicalMemoryUsage: [],
      historicalDiskUsage: [],
      timestamp: DateTime.now(),
    );
  }

  ResourceStats copyWith({
    double? cpuUsage,
    double? memoryUsage,
    double? diskUsage,
    List<TimeSeriesData>? historicalCpuUsage,
    List<TimeSeriesData>? historicalMemoryUsage,
    List<TimeSeriesData>? historicalDiskUsage,
    DateTime? timestamp,
  }) {
    return ResourceStats(
      cpuUsage: cpuUsage ?? this.cpuUsage,
      memoryUsage: memoryUsage ?? this.memoryUsage,
      diskUsage: diskUsage ?? this.diskUsage,
      historicalCpuUsage: historicalCpuUsage ?? this.historicalCpuUsage,
      historicalMemoryUsage: historicalMemoryUsage ?? this.historicalMemoryUsage,
      historicalDiskUsage: historicalDiskUsage ?? this.historicalDiskUsage,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

class TimeSeriesData {
  final DateTime time;
  final double value;

  TimeSeriesData({
    required this.time,
    required this.value,
  });
}