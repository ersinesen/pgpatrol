import 'package:intl/intl.dart';

class AnalysisResult {
  final DateTime timestamp;
  final String key;
  final int count;
  final List<Map<String, dynamic>> data;
  final List<String> columns;

  AnalysisResult({
    required this.timestamp,
    required this.key,
    required this.count,
    required this.data,
    required this.columns,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      key: json['key'] ?? '',
      count: json['count'] ?? 0,
      data: List<Map<String, dynamic>>.from(json['data'] ?? []),
      columns: List<String>.from(json['columns'] ?? []),
    );
  }

  factory AnalysisResult.empty(String key) {
    return AnalysisResult(
      timestamp: DateTime.now(),
      key: key, 
      count: 0,
      data: [],
      columns: [],
    );
  }
  
  String get formattedTimestamp {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
  }
}