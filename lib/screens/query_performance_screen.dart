import 'package:flutter/material.dart';
import '../models/query_log.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

class QueryPerformanceScreen extends StatefulWidget {
  final DatabaseService databaseService;

  const QueryPerformanceScreen({
    Key? key,
    required this.databaseService,
  }) : super(key: key);

  @override
  _QueryPerformanceScreenState createState() => _QueryPerformanceScreenState();
}

class _QueryPerformanceScreenState extends State<QueryPerformanceScreen> {
  @override
  void initState() {
    super.initState();
    widget.databaseService.refreshQueryPerformance();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await widget.databaseService.refreshQueryPerformance();
      },
      child: StreamBuilder<List<QueryPerformance>>(
        stream: widget.databaseService.queryPerformanceStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final queryPerformance = snapshot.data ?? [];

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Query Performance Analysis',
                  style: Theme.of(context).textTheme.headline2,
                ),
                const SizedBox(height: 8),
                Text(
                  'Analyze query patterns and performance metrics',
                  style: Theme.of(context).textTheme.bodyText2,
                ),
                const SizedBox(height: 24),
                _buildQueryPerformanceTable(queryPerformance),
                const SizedBox(height: 24),
                if (queryPerformance.isNotEmpty) _buildPerformanceCharts(queryPerformance),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQueryPerformanceTable(List<QueryPerformance> performance) {
    if (performance.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.query_stats,
                  size: 48,
                  color: Theme.of(context).textTheme.bodyText2?.color?.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No query performance data available',
                  style: Theme.of(context).textTheme.bodyText1,
                ),
                const SizedBox(height: 8),
                Text(
                  'This may require enabling pg_stat_statements extension',
                  style: Theme.of(context).textTheme.bodyText2,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Queries by Average Duration',
              style: Theme.of(context).textTheme.headline3,
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingTextStyle: TextStyle(
                  color: Theme.of(context).textTheme.headline4?.color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                columns: const [
                  DataColumn(label: Text('Query Type')),
                  DataColumn(label: Text('Count')),
                  DataColumn(label: Text('Avg Time')),
                  DataColumn(label: Text('Max Time')),
                  DataColumn(label: Text('Rows Affected')),
                ],
                rows: performance.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Tooltip(
                            message: item.queryType,
                            child: Text(
                              item.queryType,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text(item.count.toString())),
                      DataCell(
                        Text(
                          item.formattedAvgDuration,
                          style: TextStyle(
                            color: _getTimeColor(item.avgDuration),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          _formatDuration(item.maxDuration),
                          style: TextStyle(
                            color: _getTimeColor(item.maxDuration),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DataCell(Text(item.rowsAffected.toString())),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceCharts(List<QueryPerformance> performance) {
    // Sort by average duration
    final sortedByTime = List<QueryPerformance>.from(performance)
      ..sort((a, b) => b.avgDuration.compareTo(a.avgDuration));
    
    // Take top 5
    final topByTime = sortedByTime.take(5).toList();
    
    // Sort by count
    final sortedByCount = List<QueryPerformance>.from(performance)
      ..sort((a, b) => b.count.compareTo(a.count));
    
    // Take top 5
    final topByCount = sortedByCount.take(5).toList();

    return Column(
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top 5 Queries by Duration',
                  style: Theme.of(context).textTheme.headline3,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  child: _buildBarChart(
                    topByTime, 
                    (item) => item.avgDuration.inMicroseconds / 1000, // Convert to milliseconds
                    (value) => '${value.toStringAsFixed(2)} ms',
                    AppTheme.chartColors[0],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top 5 Queries by Execution Count',
                  style: Theme.of(context).textTheme.headline3,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  child: _buildBarChart(
                    topByCount, 
                    (item) => item.count.toDouble(),
                    (value) => value.toInt().toString(),
                    AppTheme.chartColors[1],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart(
    List<QueryPerformance> data,
    double Function(QueryPerformance) getValue,
    String Function(double) formatLabel,
    Color barColor,
  ) {
    if (data.isEmpty) {
      return Center(
        child: Text(
          'No data available',
          style: Theme.of(context).textTheme.bodyText1,
        ),
      );
    }

    final maxValue = data.map(getValue).reduce((a, b) => a > b ? a : b);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: data.map((item) {
            final value = getValue(item);
            final percentage = value / maxValue;
            
            return Tooltip(
              message: '${item.queryType}\n${formatLabel(value)}',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: constraints.maxWidth / data.length - 16,
                    height: percentage * 200,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: constraints.maxWidth / data.length - 16,
                    child: Text(
                      formatLabel(value),
                      style: Theme.of(context).textTheme.caption,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: constraints.maxWidth / data.length - 16,
                    child: Text(
                      item.queryType.length > 10 
                          ? '${item.queryType.substring(0, 10)}...'
                          : item.queryType,
                      style: Theme.of(context).textTheme.caption,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      }
    );
  }

  Color _getTimeColor(Duration time) {
    if (time.inMilliseconds < 10) {
      return AppTheme.secondaryColor;
    } else if (time.inMilliseconds < 100) {
      return AppTheme.warningColor;
    } else {
      return AppTheme.errorColor;
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inMicroseconds < 1000) {
      return '${duration.inMicroseconds} μs';
    } else if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds} ms';
    } else if (duration.inSeconds < 60) {
      return '${duration.inSeconds} s';
    } else {
      return '${duration.inMinutes} min';
    }
  }
}
