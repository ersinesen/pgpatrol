import 'package:flutter/material.dart';
import '../models/analysis_result.dart';
import '../theme/app_theme.dart';

class AnalysisTable extends StatelessWidget {
  final AnalysisResult analysisResult;
  final Function(Map<String, dynamic>)? onRowTap;
  final List<String>? displayColumns; // Optional subset of columns to display
  final Map<String, String>? columnTitles; // Optional mapping of column names to display titles

  const AnalysisTable({
    Key? key,
    required this.analysisResult,
    this.onRowTap,
    this.displayColumns,
    this.columnTitles,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (analysisResult.data.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No data available for this analysis'),
        ),
      );
    }

    // Determine which columns to display
    final columns = displayColumns ?? analysisResult.columns;

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
            columns: columns.map((column) {
              final displayName = columnTitles?[column] ?? _formatColumnName(column);
              return DataColumn(label: Text(displayName));
            }).toList(),
            rows: analysisResult.data.map((row) {
              return DataRow(
                onSelectChanged: onRowTap != null ? (selected) {
                  if (selected == true) {
                    onRowTap!(row);
                  }
                } : null,
                cells: columns.map((column) {
                  final value = row[column]?.toString() ?? '';
                  return DataCell(
                    Text(
                      value,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _formatColumnName(String name) {
    // Convert snake_case to Title Case with spaces
    final words = name.split('_');
    final formattedWords = words.map((word) => 
      word.isNotEmpty 
        ? '${word[0].toUpperCase()}${word.substring(1)}' 
        : '');
    return formattedWords.join(' ').toUpperCase();
  }
}