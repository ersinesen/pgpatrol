import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../models/resource_stats.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';

class PerformanceChart extends StatelessWidget {
  final List<TimeSeriesData> data;
  final String title;
  final Color lineColor;
  final String unit;
  final double maxY;

  const PerformanceChart({
    Key? key,
    required this.data,
    required this.title,
    required this.lineColor,
    required this.unit,
    required this.maxY,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white70 : Colors.black87;
    final gridColor = Theme.of(context).dividerTheme.color ?? Colors.grey.shade300;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (data.isEmpty)
            const SizedBox(
              height: 200,
              child: Center(
                child: Text('No data available'),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: SfCartesianChart(
                plotAreaBorderWidth: 0,
                margin: const EdgeInsets.all(0),
                primaryXAxis: DateTimeAxis(
                  majorGridLines: MajorGridLines(width: 0),
                  labelStyle: TextStyle(color: textColor, fontSize: 10),
                  dateFormat: DateFormat('HH:mm'),
                  intervalType: DateTimeIntervalType.minutes,
                ),
                primaryYAxis: NumericAxis(
                  minimum: 0,
                  maximum: maxY,
                  labelFormat: '{value}$unit',
                  majorGridLines: MajorGridLines(width: 0.5, color: gridColor),
                  labelStyle: TextStyle(color: textColor, fontSize: 10),
                ),
                series: <ChartSeries>[
                  AreaSeries<TimeSeriesData, DateTime>(
                    dataSource: data,
                    xValueMapper: (TimeSeriesData data, _) => data.time,
                    yValueMapper: (TimeSeriesData data, _) => data.value,
                    color: lineColor.withOpacity(0.1),
                    borderColor: lineColor,
                    borderWidth: 2,
                    name: title,
                  )
                ],
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  format: 'point.x: point.y$unit',
                  header: '',
                ),
                zoomPanBehavior: ZoomPanBehavior(
                  enablePanning: true,
                  zoomMode: ZoomMode.x,
                ),
                legend: Legend(
                  isVisible: false,
                ),
              ),
            ),
        ],
      ),
    );
  }
}