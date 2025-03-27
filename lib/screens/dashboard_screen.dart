import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/connection_status.dart';
import '../models/database_stats.dart';
import '../models/table_stats.dart';
import '../models/query_log.dart';
import '../models/resource_stats.dart';
import '../services/api_database_service.dart';
import '../services/database_service.dart';

import '../services/connection_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/performance_chart.dart';
import '../widgets/query_log_table.dart';
import '../widgets/status_indicator.dart';
import '../main.dart';
import 'manage_connections_screen.dart';
import 'analysis_screen.dart';

class DashboardScreen extends StatefulWidget {
  final bool isDirectConnection;

  const DashboardScreen({Key? key, required this.isDirectConnection}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final dynamic _databaseService;
  late bool _isDirectConnection;

  @override
  void initState() {
    super.initState();
    _isDirectConnection = widget.isDirectConnection;

    // Get the appropriate database service from the provider based on the connection type
    if (widget.isDirectConnection) {
      _databaseService = Provider.of<DatabaseService>(context, listen: false);
      print('Dashboard: Using direct database connection');
    } else {
      _databaseService = Provider.of<ApiDatabaseService>(context, listen: false);
      print('Dashboard: Using API database connection');
    }
    
    // Listen for connection changes
    _connectionManager.connectionsStream.listen((connections) {
      print('Dashboard: Connection list changed, active connection may have changed');
      
      // Check if we need to connect to a new database
      if (!_databaseService.isConnected()) {
        // If we're not connected, try to connect to the active connection
        _checkAndConnectToDatabase();
      } else {
        // If we're connected, check if we're connected to the correct database
        final activeConnection = _connectionManager.activeConnection;
        if (activeConnection != null) {
          final status = _databaseService.getConnectionStatus();
          
          // If the connection name doesn't match the active connection, reconnect
          if (status.connectionName != activeConnection.name) {
            print('Dashboard: Connected to ${status.connectionName}, but active connection is ${activeConnection.name}');
            // Disconnect and reconnect to the active connection
            _disconnectAndReconnect();
          }
        }
      }
    });
    
    // Check connection status
    final connectionStatus = _databaseService.getConnectionStatus();
    final activeConnection = _connectionManager.activeConnection;
    
    if (!_databaseService.isConnected()) {
      // If not connected, try to connect with the active connection
      print('Dashboard: Not connected, attempting to connect to active connection');
      _checkAndConnectToDatabase();
    } else if (activeConnection != null && 
              connectionStatus.connectionName != activeConnection.name) {
      // If we're connected but not to the active connection, reconnect
      print('Dashboard: Connected to ${connectionStatus.connectionName}, but active connection is ${activeConnection.name}');
      _disconnectAndReconnect();
    } else {
      print('Dashboard: Already connected to ${connectionStatus.connectionName}');
    }
  }
  
  /// Try to connect to the first available database connection
  Future<void> _checkAndConnectToDatabase() async {
    try {
      // Get available connections from the manager
      final connections = _connectionManager.connections;
      
      if (connections.isEmpty) {
        print('Dashboard: No connections available');
        return;
      }
      
      // Find the active connection if any
      final activeConnection = _connectionManager.activeConnection;
      
      if (activeConnection == null) {
        print('Dashboard: No active connection found');
        return;
      }
      
      print('Dashboard trying to connect to: ${activeConnection.name} (isActive: ${activeConnection.isActive})');
      
      // Skip if we're already connected
      if (_databaseService.isConnected()) {
        print('Dashboard: Already connected, skipping connection');
        setState(() {}); // Refresh UI state
        return;
      }
      
      // Connect to the database
      final result = await _databaseService.connect(activeConnection);
      if (!result) {
        print('Failed to connect to database from dashboard');
      } else {
        print('Successfully connected to database from dashboard');
        setState(() {}); // Refresh UI state
      }
    } catch (e) {
      print('Error connecting to database from dashboard: $e');
    }
  }
  
  /// Disconnect and reconnect to the active connection
  Future<void> _disconnectAndReconnect() async {
    try {
      print('Dashboard: Disconnecting and reconnecting to match active connection');
      
      // First disconnect from the current database
      await _databaseService.disconnect();
      
      // Wait a moment to let the system process
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Then connect to the active connection
      await _checkAndConnectToDatabase();
      
      // Refresh the UI
      setState(() {});
    } catch (e) {
      print('Dashboard: Error during disconnect/reconnect: $e');
    }
  }

  @override
  void dispose() {
    // Note: we don't call disconnect on the database service when navigating away
    // This ensures the connection remains active when returning to this screen
    super.dispose();
  }

  // Connection manager
  final ConnectionManager _connectionManager = ConnectionManager();
  
  void _navigateToManageConnections() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManageConnectionsScreen(isDirectConnection: _isDirectConnection),
      ),
    ).then((_) {
      // Refresh state when returning from connection management
      setState(() {});
      
      // Check if we need to connect to the active connection
      if (!_databaseService.isConnected()) {
        print('Dashboard: returning from connections screen, checking active connection');
        _checkAndConnectToDatabase();
      }
    });
  }

  void _openSupportPage() async {
    const url = 'https://buymeacoffee.com/esenbil';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank'); // Opens in new tab for web
    } else {
      throw 'Could not launch $url';
    }
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
                const Image(
                  image: AssetImage('assets/images/pgpatrol.png'),
                  width: 48,
                  height: 48,
                ),
                const SizedBox(width: 8),
                const Text('pgpatrol'),
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
          // Support
          IconButton(
            icon: const Icon(Icons.favorite),
            onPressed: _openSupportPage,
            tooltip: 'Support the developer',
          )
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
            child: 
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildConnectionStatusSection(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildResourceUsageSection(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDatabaseStatsSection(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 600,
                    child: _buildTabs(),
                  ),
                ]
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
            Row(
              children: [
                Expanded(
                  child: StatusIndicator(
                    isConnected: connectionStatus.isConnected,
                    label: 'STATUS',
                    statusMessage: connectionStatus.statusMessage,
                  ),
                ),
                const SizedBox(width: 16),
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
                    value: '${connectionStatus.activeConnections}',
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
      stream: _databaseService.databaseStatsStream,
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

  Widget _buildTableStatsSection() {
    return StreamBuilder<TableStats>(
      stream: _databaseService.tableStatsStream,
      initialData: _databaseService.getTableStats(),
      builder: (context, snapshot) {
        final tableStats = snapshot.data ?? TableStats.initial();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Table Sizes',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 16),

            if (tableStats.tables.isNotEmpty) ...[
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
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: tableStats.tables.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final table = tableStats.tables[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  table.name,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${table.size.toStringAsFixed(2)} MB',
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
      stream: _databaseService.resourceStatsStream,
      initialData: _databaseService.getResourceStats(),
      builder: (context, snapshot) {
        final resourceStats = snapshot.data ?? ResourceStats.initial();

        return DefaultTabController(
          length: 2,
          child: Column(
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
                      title: 'MEMORY USAGE',
                      value: '${resourceStats.memoryUsage.toStringAsFixed(1)} GB',
                      icon: Icons.memory_rounded,
                      iconColor: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MetricCard(
                      title: 'DISK USAGE',
                      value: '${resourceStats.diskUsage.toStringAsFixed(2)} GB',
                      icon: Icons.storage_rounded,
                      iconColor: _getUtilizationColor(resourceStats.diskUsage),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // TabBar for selecting different charts
              TabBar(
                labelColor: Theme.of(context).primaryColor,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Theme.of(context).primaryColor,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.memory),
                    text: 'Memory',
                  ),
                  Tab(
                    icon: Icon(Icons.sd_storage),
                    text: 'Disk',
                  ),
                ],
              ),

              // Wrap TabBarView 
              SizedBox(
                height: 300,
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: PerformanceChart(
                        title: 'MEMORY USAGE OVER TIME',
                        data: resourceStats.historicalMemoryUsage,
                        lineColor: AppTheme.primaryColor,
                        unit: 'GB',
                        maxY: 128,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: PerformanceChart(
                        title: 'DISK USAGE OVER TIME',
                        data: resourceStats.historicalDiskUsage,
                        lineColor: _getUtilizationColor(resourceStats.diskUsage),
                        unit: 'GB',
                        maxY: 1024,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabs() {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          // TabBar for selecting different charts
          TabBar(
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).primaryColor,
            tabs: const [
              Tab(
                icon: Icon(Icons.analytics),
                text: 'Analysis',
              ),
              Tab(
                icon: Icon(Icons.sd_storage),
                text: 'Queries',
              ),
            ],
          ),

          // Wrap TabBarView inside Expanded to avoid height issues
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _buildAnalysisSection(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _buildRecentQueriesSection(),
                ),
                
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentQueriesSection() {
    return StreamBuilder<List<QueryLog>>(
      stream: _databaseService.queryLogsStream,
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

  Widget _buildAnalysisSection() {
    if (!_databaseService.isConnected()) {
      return Center(
        child: Text(
          'Connect to a database to view analysis',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Analysis selection buttons
    final analysisTypes = [
      {'key': 'index_usage', 'title': 'Index Usage', 'icon': Icons.show_chart},
      {'key': 'long_tables', 'title': 'Large Tables', 'icon': Icons.table_chart},
      {'key': 'deadlock', 'title': 'Deadlocks', 'icon': Icons.lock},
      {'key': 'blocked_queries', 'title': 'Blocked Queries', 'icon': Icons.pause_circle},
      {'key': 'high_dead_tuple', 'title': 'Dead Tuples', 'icon': Icons.delete_outline},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Database Analysis',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 16),
        
        Text(
          'Select an analysis type to view detailed results:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        
        // Analysis type grid
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: analysisTypes.map((type) => 
            _buildAnalysisCard(
              title: type['title'] as String,
              icon: type['icon'] as IconData,
              key: type['key'] as String,
            )
          ).toList(),
        ),
        
        const SizedBox(height: 24),
        
        // View All button
        Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.analytics),
            label: const Text('View Full Analysis Dashboard'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AnalysisScreen(
                    databaseService: _databaseService,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisCard({
    required String title,
    required IconData icon,
    required String key,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AnalysisScreen(
              databaseService: _databaseService,
              initialAnalysisType: key,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}