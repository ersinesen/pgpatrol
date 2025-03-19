import 'package:flutter/material.dart';
import '../models/analysis_result.dart';
import '../services/api_database_service.dart';
import '../widgets/analysis_table.dart';

class AnalysisScreen extends StatefulWidget {
  final ApiDatabaseService databaseService;

  const AnalysisScreen({
    Key? key,
    required this.databaseService,
  }) : super(key: key);

  @override
  _AnalysisScreenState createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  String selectedAnalysisType = 'index_usage';
  late Future<AnalysisResult> _analysisFuture;
  bool _isLoading = false;

  final Map<String, String> analysisTypes = {
    'index_usage': 'Index Usage',
    'long_tables': 'Large Tables (by row count)',
    'large_tables': 'Large Tables (by size)',
    'deadlock': 'Deadlocks',
    'idle': 'Idle Transactions',
    'blocked_queries': 'Blocked Queries',
    'high_dead_tuple': 'High Dead Tuple Count',
    'vacuum_progress': 'Vacuum Progress',
    'index_hit_rate': 'Index Hit Rate',
    'active_locks': 'Active Locks',
  };

  final Map<String, String> analysisDescriptions = {
    'index_usage': 'Shows how frequently indexes are being used in database operations',
    'long_tables': 'Lists tables with the highest number of rows',
    'large_tables': 'Identifies the largest tables by disk space',
    'deadlock': 'Shows sessions that are waiting for locks',
    'idle': 'Lists transactions that are idle but still holding resources',
    'blocked_queries': 'Shows queries that are blocked waiting for resources',
    'high_dead_tuple': 'Tables with high dead tuple counts that need VACUUM',
    'vacuum_progress': 'Current progress of VACUUM operations',
    'index_hit_rate': 'Ratio of index hits to total scans (higher is better)',
    'active_locks': 'Shows current locks that have not been granted',
  };

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _analysisFuture = widget.databaseService.analyze(selectedAnalysisType);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Analysis'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Analysis Type Selection
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analysis Type',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedAnalysisType,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  items: analysisTypes.entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null && value != selectedAnalysisType) {
                      setState(() {
                        selectedAnalysisType = value;
                      });
                      _loadAnalysis();
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  analysisDescriptions[selectedAnalysisType] ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),

          // Analysis Results
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Results',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _isLoading ? null : _loadAnalysis,
                        tooltip: 'Refresh Analysis',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : FutureBuilder<AnalysisResult>(
                          future: _analysisFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            
                            if (snapshot.hasError) {
                              return Center(
                                child: Text(
                                  'Error loading analysis: ${snapshot.error}',
                                  style: TextStyle(color: Colors.red),
                                ),
                              );
                            }
                            
                            final analysisResult = snapshot.data ?? AnalysisResult.empty(selectedAnalysisType);
                            
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Metadata
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Last updated: ${analysisResult.formattedTimestamp}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${analysisResult.count} results',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                
                                // Table
                                Expanded(
                                  child: AnalysisTable(
                                    analysisResult: analysisResult,
                                    onRowTap: (data) {
                                      // Show detailed information
                                      _showDetailDialog(data);
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Analysis Details'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: data.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatColumnName(entry.key),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          entry.value?.toString() ?? 'N/A',
                          style: const TextStyle(
                            fontFamily: 'monospace', 
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatColumnName(String name) {
    // Convert snake_case to Title Case with spaces
    final words = name.split('_');
    final formattedWords = words.map((word) => 
      word.isNotEmpty 
        ? '${word[0].toUpperCase()}${word.substring(1)}' 
        : '');
    return formattedWords.join(' ');
  }
}