import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/query_log.dart';
import '../theme/app_theme.dart';

class QueryLogTable extends StatelessWidget {
  final List<QueryLog> logs;
  final Function(QueryLog)? onLogTap;

  const QueryLogTable({
    Key? key,
    required this.logs,
    this.onLogTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No query logs available'),
        ),
      );
    }

    return Container(
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            headingRowColor: MaterialStateProperty.all(
              Theme.of(context).brightness == Brightness.light
                  ? const Color(0xFFF5F5F7) // Light gray for light theme
                  : const Color(0xFF2C2C2E), // Dark gray for dark theme
            ),
            headingTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            dataRowColor: MaterialStateProperty.resolveWith<Color?>(
              (Set<MaterialState> states) {
                if (states.contains(MaterialState.selected)) {
                  return Theme.of(context).colorScheme.primary.withOpacity(0.08);
                }
                return null;
              },
            ),
            columns: [
              DataColumn(label: Text(_getColumnName('Time'))),
              DataColumn(label: Text(_getColumnName('Database'))),
              DataColumn(label: Text(_getColumnName('Duration'))),
              DataColumn(label: Text(_getColumnName('Status'))),
              DataColumn(label: Text(_getColumnName('Query'))),
            ],
            rows: logs.map((log) {
              return DataRow(
                onSelectChanged: (selected) {
                  if (selected == true && onLogTap != null) {
                    onLogTap!(log);
                  }
                },
                cells: [
                  DataCell(Text(
                    DateFormat('HH:mm:ss').format(log.timestamp),
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
                  DataCell(Text(
                    log.database,
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
                  DataCell(Text(
                    log.formattedDuration,
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(log.status),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        log.status.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 300,
                      child: Text(
                        log.query,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _getColumnName(String name) {
    return name.toUpperCase();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppTheme.secondaryColor;
      case 'error':
        return AppTheme.errorColor;
      case 'running':
        return AppTheme.primaryColor;
      case 'waiting':
        return AppTheme.warningColor;
      default:
        return Colors.grey;
    }
  }
}