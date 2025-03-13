import 'package:flutter/material.dart';
import '../models/resource_stats.dart';
import '../services/database_service.dart';
import '../widgets/performance_chart.dart';
import '../widgets/metric_card.dart';
import '../theme/app_theme.dart';

class ResourceUtilizationScreen extends StatefulWidget {
  final DatabaseService databaseService;

  const ResourceUtilizationScreen({
    Key? key,
    required this.databaseService,
  }) : super(key: key);

  @override
  _ResourceUtilizationScreenState createState() => _ResourceUtilizationScreenState();
}

class _ResourceUtilizationScreenState extends State<ResourceUtilizationScreen> {
  @override
  void initState() {
    super.initState();
    widget.databaseService.refreshResourceStats();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await widget.databaseService.refreshResourceStats();
      },
      child: StreamBuilder<ResourceStats>(
        stream: widget.databaseService.resourceStatsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final resourceStats = snapshot.data ?? ResourceStats.empty();

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text(
                'System Resource Utilization',
                style: Theme.of(context).textTheme.headline2,
              ),
              const SizedBox(height: 8),
              Text(
                'Monitor system resources used by PostgreSQL',
                style: Theme.of(context).textTheme.bodyText2,
              ),
              const SizedBox(height: 24),
              
              // CPU and Memory section
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Processor & Memory',
                        style: Theme.of(context).textTheme.headline3,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: MetricCard(
                              title: 'CPU Usage',
                              value: '${resourceStats.cpuUsage.toStringAsFixed(1)}%',
                              icon: Icons.memory_outlined,
                              iconColor: _getCpuUsageColor(resourceStats.cpuUsage),
                              isCompact: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MetricCard(
                              title: 'Memory Usage',
                              value: resourceStats.memoryUsageFormatted,
                              icon: Icons.sd_card_outlined,
                              iconColor: AppTheme.chartColors[3],
                              isCompact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildCpuGauge(resourceStats.cpuUsage),
                      const SizedBox(height: 24),
                      if (resourceStats.cpuHistory.isNotEmpty)
                        PerformanceChart(
                          title: 'CPU Utilization History',
                          data: resourceStats.cpuHistory,
                          yAxisLabel: '%',
                          lineColor: _getCpuUsageColor(resourceStats.cpuUsage),
                          minY: 0,
                          maxY: 100,
                        ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Storage section
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Storage & I/O',
                        style: Theme.of(context).textTheme.headline3,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: MetricCard(
                              title: 'Disk Usage',
                              value: resourceStats.diskUsageFormatted,
                              icon: Icons.storage_outlined,
                              iconColor: AppTheme.chartColors[4],
                              isCompact: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MetricCard(
                              title: 'Free Space',
                              value: resourceStats.diskFreeFormatted,
                              icon: Icons.disc_full_outlined,
                              iconColor: AppTheme.secondaryColor,
                              isCompact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: MetricCard(
                              title: 'Read IOPS',
                              value: resourceStats.iopsRead.toString(),
                              icon: Icons.arrow_downward,
                              iconColor: AppTheme.primaryColor,
                              isCompact: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MetricCard(
                              title: 'Write IOPS',
                              value: resourceStats.iopsWrite.toString(),
                              icon: Icons.arrow_upward,
                              iconColor: AppTheme.warningColor,
                              isCompact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: MetricCard(
                              title: 'Read Bandwidth',
                              value: resourceStats.diskReadBandwidthFormatted,
                              icon: Icons.download_outlined,
                              iconColor: AppTheme.primaryColor,
                              isCompact: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MetricCard(
                              title: 'Write Bandwidth',
                              value: resourceStats.diskWriteBandwidthFormatted,
                              icon: Icons.upload_outlined,
                              iconColor: AppTheme.warningColor,
                              isCompact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildStorageGauge(
                        resourceStats.diskUsage,
                        resourceStats.diskUsage + resourceStats.diskFree
                      ),
                      const SizedBox(height: 24),
                      if (resourceStats.diskIoHistory.isNotEmpty)
                        PerformanceChart(
                          title: 'I/O Operations History',
                          data: resourceStats.diskIoHistory,
                          yAxisLabel: 'IOPS',
                          lineColor: AppTheme.chartColors[5],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCpuGauge(double cpuUsage) {
    final color = _getCpuUsageColor(cpuUsage);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CPU Usage',
                  style: Theme.of(context).textTheme.bodyText1,
                ),
                Text(
                  '${cpuUsage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: width,
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.darkTextSecondary.withOpacity(0.1)
                    : AppTheme.lightTextSecondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                children: [
                  Container(
                    width: (cpuUsage / 100) * width,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '0%',
                  style: Theme.of(context).textTheme.caption,
                ),
                Text(
                  '100%',
                  style: Theme.of(context).textTheme.caption,
                ),
              ],
            ),
          ],
        );
      }
    );
  }

  Widget _buildStorageGauge(double diskUsage, double totalDisk) {
    final usagePercentage = (diskUsage / totalDisk) * 100;
    final color = _getDiskUsageColor(usagePercentage);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Disk Usage',
                  style: Theme.of(context).textTheme.bodyText1,
                ),
                Text(
                  '${usagePercentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: width,
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.darkTextSecondary.withOpacity(0.1)
                    : AppTheme.lightTextSecondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                children: [
                  Container(
                    width: (usagePercentage / 100) * width,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatBytes(diskUsage),
                  style: Theme.of(context).textTheme.caption,
                ),
                Text(
                  _formatBytes(totalDisk),
                  style: Theme.of(context).textTheme.caption,
                ),
              ],
            ),
          ],
        );
      }
    );
  }

  Color _getCpuUsageColor(double usage) {
    if (usage < 50) {
      return AppTheme.secondaryColor;
    } else if (usage < 80) {
      return AppTheme.warningColor;
    } else {
      return AppTheme.errorColor;
    }
  }

  Color _getDiskUsageColor(double percentage) {
    if (percentage < 70) {
      return AppTheme.secondaryColor;
    } else if (percentage < 90) {
      return AppTheme.warningColor;
    } else {
      return AppTheme.errorColor;
    }
  }

  String _formatBytes(double bytes) {
    if (bytes < 1024) {
      return '${bytes.toStringAsFixed(2)} B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
}
