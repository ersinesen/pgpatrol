import 'package:flutter/material.dart';
import '../models/query_log.dart';
import '../services/database_service.dart';
import '../widgets/query_log_table.dart';
import '../theme/app_theme.dart';

class QueryLogsScreen extends StatefulWidget {
  final DatabaseService databaseService;

  const QueryLogsScreen({
    Key? key,
    required this.databaseService,
  }) : super(key: key);

  @override
  _QueryLogsScreenState createState() => _QueryLogsScreenState();
}

class _QueryLogsScreenState extends State<QueryLogsScreen> {
  String _filterText = '';
  String _sortBy = 'time'; // 'time', 'duration', or 'user'
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    widget.databaseService.refreshQueryLogs();
  }

  List<QueryLog> _filterAndSortLogs(List<QueryLog> logs) {
    // First filter
    var filteredLogs = logs;
    if (_filterText.isNotEmpty) {
      filteredLogs = logs.where((log) {
        return log.query.toLowerCase().contains(_filterText.toLowerCase()) ||
            log.username.toLowerCase().contains(_filterText.toLowerCase()) ||
            log.database.toLowerCase().contains(_filterText.toLowerCase()) ||
            log.applicationName.toLowerCase().contains(_filterText.toLowerCase());
      }).toList();
    }

    // Then sort
    switch (_sortBy) {
      case 'time':
        filteredLogs.sort((a, b) => _sortAscending
            ? a.startTime.compareTo(b.startTime)
            : b.startTime.compareTo(a.startTime));
        break;
      case 'duration':
        filteredLogs.sort((a, b) => _sortAscending
            ? a.duration.compareTo(b.duration)
            : b.duration.compareTo(a.duration));
        break;
      case 'user':
        filteredLogs.sort((a, b) => _sortAscending
            ? a.username.compareTo(b.username)
            : b.username.compareTo(a.username));
        break;
    }

    return filteredLogs;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await widget.databaseService.refreshQueryLogs();
      },
      child: StreamBuilder<List<QueryLog>>(
        stream: widget.databaseService.queryLogsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snapshot.data ?? [];
          final filteredLogs = _filterAndSortLogs(logs);

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Query Logs',
                  style: Theme.of(context).textTheme.headline2,
                ),
                const SizedBox(height: 8),
                Text(
                  'Recent and active database queries',
                  style: Theme.of(context).textTheme.bodyText2,
                ),
                const SizedBox(height: 16),
                _buildFilterBar(),
                const SizedBox(height: 16),
                Expanded(
                  child: _buildDetailedQueryLogList(filteredLogs),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterBar() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Filter queries...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.darkBackground
                      : AppTheme.lightBackground,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _filterText = value;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort by',
              onSelected: (value) {
                setState(() {
                  if (_sortBy == value) {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortBy = value;
                    _sortAscending = false;
                  }
                });
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'time',
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: _sortBy == 'time' ? AppTheme.primaryColor : null,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Time',
                        style: TextStyle(
                          color: _sortBy == 'time' ? AppTheme.primaryColor : null,
                          fontWeight: _sortBy == 'time'
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const Spacer(),
                      if (_sortBy == 'time')
                        Icon(
                          _sortAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: AppTheme.primaryColor,
                          size: 16,
                        ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'duration',
                  child: Row(
                    children: [
                      Icon(
                        Icons.timer,
                        color: _sortBy == 'duration' ? AppTheme.primaryColor : null,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Duration',
                        style: TextStyle(
                          color: _sortBy == 'duration' ? AppTheme.primaryColor : null,
                          fontWeight: _sortBy == 'duration'
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const Spacer(),
                      if (_sortBy == 'duration')
                        Icon(
                          _sortAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: AppTheme.primaryColor,
                          size: 16,
                        ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'user',
                  child: Row(
                    children: [
                      Icon(
                        Icons.person,
                        color: _sortBy == 'user' ? AppTheme.primaryColor : null,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'User',
                        style: TextStyle(
                          color: _sortBy == 'user' ? AppTheme.primaryColor : null,
                          fontWeight: _sortBy == 'user'
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const Spacer(),
                      if (_sortBy == 'user')
                        Icon(
                          _sortAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: AppTheme.primaryColor,
                          size: 16,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedQueryLogList(List<QueryLog> logs) {
    return logs.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.query_stats,
                  size: 48,
                  color: Theme.of(context).textTheme.bodyText2?.color?.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No query logs found',
                  style: Theme.of(context).textTheme.headline4,
                ),
                const SizedBox(height: 8),
                Text(
                  _filterText.isNotEmpty
                      ? 'Try adjusting your filter criteria'
                      : 'There are no active queries at the moment',
                  style: Theme.of(context).textTheme.bodyText1,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        : ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildDetailedQueryItem(log);
            },
          );
  }

  Widget _buildDetailedQueryItem(QueryLog log) {
    final durationColor = _getDurationColor(log.duration);
    
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          log.shortQuery,
          style: Theme.of(context).textTheme.bodyText1?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 14,
                color: Theme.of(context).textTheme.bodyText2?.color,
              ),
              const SizedBox(width: 4),
              Text(
                log.username,
                style: Theme.of(context).textTheme.bodyText2,
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.access_time,
                size: 14,
                color: Theme.of(context).textTheme.bodyText2?.color,
              ),
              const SizedBox(width: 4),
              Text(
                _formatDateTime(log.startTime),
                style: Theme.of(context).textTheme.bodyText2,
              ),
            ],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: durationColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            log.formattedDuration,
            style: TextStyle(
              color: durationColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Full Query:',
                  style: Theme.of(context).textTheme.bodyText2?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.darkBackground
                        : AppTheme.lightBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    log.query,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodyText1?.color,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildInfoItem(context, 'Database', log.database),
                    _buildInfoItem(context, 'State', log.state),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildInfoItem(context, 'Application', log.applicationName),
                    _buildInfoItem(context, 'Client', log.clientAddress),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label: ',
              style: Theme.of(context).textTheme.bodyText2?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyText2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getDurationColor(Duration duration) {
    if (duration.inSeconds < 1) {
      return AppTheme.secondaryColor;
    } else if (duration.inSeconds < 10) {
      return AppTheme.warningColor;
    } else {
      return AppTheme.errorColor;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}
