import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/connection_status.dart';
import '../models/database_stats.dart';
import '../models/query_log.dart';
import '../models/resource_stats.dart';
import '../services/database_service.dart';
import '../services/connection_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/performance_chart.dart';
import '../widgets/query_log_table.dart';
import '../widgets/status_indicator.dart';
import '../main.dart';
import 'manage_connections_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _databaseService = DatabaseService();
  
  @override
  void dispose() {
    _databaseService.dispose();
    super.dispose();
  }

  // Connection manager
  final ConnectionManager _connectionManager = ConnectionManager();
  
  void _navigateToManageConnections() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ManageConnectionsScreen(),
      ),
    ).then((_) {
      // Refresh state when returning from connection management
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<ConnectionStatus>(
          stream: _databaseService.connectionStatus,
          initialData: _databaseService.getConnectionStatus(),
          builder: (context, snapshot) {
            final status = snapshot.data ?? ConnectionStatus.initial();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('PostgreSQL Monitor'),
                if (status.connectionName != 'None') ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: status.isConnected 
                          ? AppTheme.secondaryColor.withOpacity(0.1) 
                          : AppTheme.errorColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.connectionName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: status.isConnected 
                            ? AppTheme.secondaryColor 
                            : AppTheme.errorColor,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        actions: [
          // Database connection button
          IconButton(
            icon: const Icon(Icons.storage),
            onPressed: _navigateToManageConnections,
            tooltip: 'Manage connections',
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {});
            },
            tooltip: 'Refresh data',
          ),
          // Theme toggle button
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.light
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
            onPressed: () {
              // Toggle theme using Provider
              context.read<ThemeProvider>().toggleTheme();
            },
            tooltip: 'Toggle theme',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConnectionStatusSection(),
                const SizedBox(height: 24),
                _buildDatabaseStatsSection(),
                const SizedBox(height: 24),
                _buildResourceUsageSection(),
                const SizedBox(height: 24),
                _buildRecentQueriesSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatusSection() {
    return StreamBuilder<ConnectionStatus>(
      stream: _databaseService.connectionStatus,
      initialData: _databaseService.getConnectionStatus(),
      builder: (context, snapshot) {
        final connectionStatus = snapshot.data ?? ConnectionStatus.initial();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Status',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 16),
            StatusIndicator(
              isConnected: connectionStatus.isConnected,
              label: 'STATUS',
              statusMessage: connectionStatus.statusMessage,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: 'SERVER VERSION',
                    value: connectionStatus.serverVersion.split(' ').first,
                    icon: Icons.dns_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: MetricCard(
                    title: 'ACTIVE CONNECTIONS',
                    value: '${connectionStatus.activeConnections} / ${connectionStatus.maxConnections}',
                    icon: Icons.people_alt_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Last Updated: ${DateFormat('HH:mm:ss').format(connectionStatus.lastChecked)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  Widget _buildDatabaseStatsSection() {
    return StreamBuilder<DatabaseStats>(
      stream: _databaseService.databaseStats,
      initialData: _databaseService.getDatabaseStats(),
      builder: (context, snapshot) {
        final dbStats = snapshot.data ?? DatabaseStats.initial();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Database Statistics',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: 'DATABASES',
                    value: '${dbStats.totalDatabases}',
                    icon: Icons.storage_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: MetricCard(
                    title: 'TABLES',
                    value: '${dbStats.totalTables}',
                    icon: Icons.table_chart_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: MetricCard(
                    title: 'TOTAL SIZE',
                    value: '${dbStats.dbSize.toStringAsFixed(2)} MB',
                    icon: Icons.data_usage_rounded,
                  ),
                ),
              ],
            ),
            if (dbStats.databases.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
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
                      'Databases',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 16),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: dbStats.databases.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final db = dbStats.databases[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  db.name,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${db.tables} tables',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${db.sizeInMB.toStringAsFixed(2)} MB',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildResourceUsageSection() {
    return StreamBuilder<ResourceStats>(
      stream: _databaseService.resourceStats,
      initialData: _databaseService.getResourceStats(),
      builder: (context, snapshot) {
        final resourceStats = snapshot.data ?? ResourceStats.initial();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resource Utilization',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: 'CPU USAGE',
                    value: '${resourceStats.cpuUsage.toStringAsFixed(1)}%',
                    icon: Icons.memory_rounded,
                    iconColor: _getUtilizationColor(resourceStats.cpuUsage),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: MetricCard(
                    title: 'MEMORY',
                    value: '${resourceStats.memoryUsage.toStringAsFixed(1)} MB',
                    icon: Icons.memory_rounded,
                    iconColor: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: MetricCard(
                    title: 'DISK USAGE',
                    value: '${resourceStats.diskUsage.toStringAsFixed(1)}%',
                    icon: Icons.storage_rounded,
                    iconColor: _getUtilizationColor(resourceStats.diskUsage),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PerformanceChart(
              title: 'CPU USAGE OVER TIME',
              data: resourceStats.historicalCpuUsage,
              lineColor: _getUtilizationColor(resourceStats.cpuUsage),
              unit: '%',
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecentQueriesSection() {
    return StreamBuilder<List<QueryLog>>(
      stream: _databaseService.queryLogs,
      initialData: _databaseService.getQueryLogs(),
      builder: (context, snapshot) {
        final queryLogs = snapshot.data ?? [];
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Queries',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 16),
            QueryLogTable(
              logs: queryLogs,
              onLogTap: (log) {
                // Show query details dialog
                _showQueryDetailsDialog(log);
              },
            ),
          ],
        );
      },
    );
  }

  void _showQueryDetailsDialog(QueryLog log) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Query Details'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Query',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: SelectableText(
                    log.query,
                    style: TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Database', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text(log.database),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text(log.status),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Time', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text(DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Duration', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text(log.formattedDuration),
                        ],
                      ),
                    ),
                  ],
                ),
                if (log.error != null) ...[
                  SizedBox(height: 16),
                  Text('Error', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.errorColor)),
                  SizedBox(height: 4),
                  Text(
                    log.error!,
                    style: TextStyle(color: AppTheme.errorColor),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Color _getUtilizationColor(double value) {
    if (value < 60) {
      return AppTheme.secondaryColor;
    } else if (value < 80) {
      return AppTheme.warningColor;
    } else {
      return AppTheme.errorColor;
    }
  }
}