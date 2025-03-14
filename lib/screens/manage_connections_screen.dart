import 'package:flutter/material.dart';
import '../models/server_connection.dart';
import '../services/connection_manager.dart';
import '../theme/app_theme.dart';
import 'server_connection_screen.dart';

class ManageConnectionsScreen extends StatefulWidget {
  const ManageConnectionsScreen({Key? key}) : super(key: key);

  @override
  _ManageConnectionsScreenState createState() => _ManageConnectionsScreenState();
}

class _ManageConnectionsScreenState extends State<ManageConnectionsScreen> {
  final ConnectionManager _connectionManager = ConnectionManager();
  List<ServerConnection> _connections = [];

  @override
  void initState() {
    super.initState();
    _loadConnections();
    
    // Listen for changes to connections
    _connectionManager.connectionsStream.listen((connections) {
      setState(() {
        _connections = connections;
      });
    });
  }

  Future<void> _loadConnections() async {
    setState(() {
      _connections = _connectionManager.connections;
    });
  }

  Future<void> _addConnection() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ServerConnectionScreen(),
      ),
    );
    
    if (result == true) {
      _loadConnections();
    }
  }

  Future<void> _editConnection(ServerConnection connection) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ServerConnectionScreen(
          connection: connection,
          isEditing: true,
        ),
      ),
    );
    
    if (result == true) {
      _loadConnections();
    }
  }

  Future<void> _deleteConnection(ServerConnection connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Connection'),
        content: Text('Are you sure you want to delete "${connection.name}"?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('Delete'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.errorColor,
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _connectionManager.deleteConnection(connection.id);
      _loadConnections();
    }
  }

  Future<void> _setActiveConnection(ServerConnection connection) async {
    await _connectionManager.setActiveConnection(connection.id);
    _loadConnections();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Connections'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Connection',
            onPressed: _addConnection,
          ),
        ],
      ),
      body: _connections.isEmpty
          ? _buildEmptyState()
          : _buildConnectionsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.storage_outlined,
            size: 64,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          Text(
            'No Database Connections',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Add a connection to start monitoring',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).disabledColor,
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Connection'),
            onPressed: _addConnection,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _connections.length,
      itemBuilder: (context, index) {
        final connection = _connections[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16.0),
          elevation: 2,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  connection.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  '${connection.username}@${connection.host}:${connection.port}/${connection.database}',
                ),
                leading: CircleAvatar(
                  backgroundColor: connection.isActive
                      ? AppTheme.secondaryColor
                      : Theme.of(context).disabledColor,
                  child: Icon(
                    Icons.storage,
                    color: Theme.of(context).canvasColor,
                  ),
                ),
                trailing: connection.isActive
                    ? Chip(
                        label: const Text('ACTIVE'),
                        backgroundColor: AppTheme.secondaryColor.withOpacity(0.1),
                        labelStyle: TextStyle(
                          color: AppTheme.secondaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      )
                    : null,
              ),
              Divider(
                height: 1,
                color: Theme.of(context).dividerColor,
              ),
              ButtonBar(
                alignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                    onPressed: () => _editConnection(connection),
                  ),
                  if (!connection.isActive)
                    TextButton.icon(
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Set Active'),
                      onPressed: () => _setActiveConnection(connection),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.errorColor,
                    ),
                    onPressed: () => _deleteConnection(connection),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}