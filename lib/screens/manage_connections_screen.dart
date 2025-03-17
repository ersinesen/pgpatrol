import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/server_connection.dart';
import '../models/connection_status.dart';
import '../services/connection_manager.dart';
import '../services/api_database_service.dart';
import '../theme/app_theme.dart';
import 'server_connection_screen.dart';

class ManageConnectionsScreen extends StatefulWidget {
  const ManageConnectionsScreen({Key? key}) : super(key: key);

  @override
  _ManageConnectionsScreenState createState() => _ManageConnectionsScreenState();
}

class _ManageConnectionsScreenState extends State<ManageConnectionsScreen> {
  // Get ConnectionManager as a singleton
  final ConnectionManager _connectionManager = ConnectionManager();
  // Will get ApiDatabaseService from provider
  late final ApiDatabaseService _databaseService;
  
  List<ServerConnection> _connections = [];
  String? _connectedId; // Track which connection is currently connected
  String? _loadingConnectionId; // Track which connection is currently being processed

  @override
  void initState() {
    super.initState();
    // Get the shared database service from provider
    _databaseService = Provider.of<ApiDatabaseService>(context, listen: false);
    
    _loadConnections();
    _syncConnectionState();
    
    // Listen for changes to connections
    _connectionManager.connectionsStream.listen((connections) {
      setState(() {
        _connections = connections;
      });
    });
    
    // Listen for connection status changes
    _databaseService.connectionStatus.listen((status) {
      if (!mounted) return;
      
      setState(() {
        // Update the connected ID based on the connection status
        if (status.isConnected) {
          // Find the connection matching the connected name
          final connection = _connections.firstWhere(
            (conn) => conn.name == status.connectionName,
            orElse: () => _connections.first,
          );
          _connectedId = connection.id;
          print('ManageConnections: Setting connected ID to ${connection.id} (${connection.name})');
        } else {
          // If disconnected, clear the connected ID
          _connectedId = null;
        }
      });
    });
  }
  
  // Sync the connection state on initialization
  void _syncConnectionState() {
    final status = _databaseService.getConnectionStatus();
    if (status.isConnected) {
      // Find the connection that might be connected already
      final activeConn = _connectionManager.activeConnection;
      if (activeConn != null) {
        setState(() {
          _connectedId = activeConn.id;
        });
      }
    }
  }
  
  @override
  void dispose() {
    // Do NOT disconnect when navigating away - we want the connection to persist
    // between screens.
    
    // if (_connectedId != null) {
    //   _databaseService.disconnect();
    // }
    
    super.dispose();
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
    print("ManageConnectionsScreen: Setting active connection: ${connection.name}");
    
    // If we're currently connected to another database, disconnect first
    if (_connectedId != null) {
      print("ManageConnectionsScreen: Disconnecting from current database before setting new active connection");
      await _databaseService.disconnect();
      setState(() {
        _connectedId = null;
      });
    }
    
    // Set this connection as active in the connection manager
    await _connectionManager.setActiveConnection(connection.id);
    
    // Notify user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${connection.name} set as active connection'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
    
    // Update the connections list
    _loadConnections();
  }
  
  /// Connect to a database
  Future<void> _connectToDatabase(ServerConnection connection) async {
    if (_loadingConnectionId != null) return;
    
    setState(() {
      _loadingConnectionId = connection.id;
    });
    
    try {
      // First set this connection as active in the connection manager
      await _connectionManager.setActiveConnection(connection.id);
      
      print("ManageConnectionsScreen: Setting active connection: ${connection.name}");
      
      // Use the database service to establish connection
      final success = await _databaseService.connect(connection);
      
      if (success) {
        setState(() {
          _connectedId = connection.id;
        });
        
        // Make sure connections are updated in UI
        _loadConnections();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${connection.name}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to ${connection.name}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _loadingConnectionId = null;
      });
    }
  }
  
  /// Disconnect from the database
  Future<void> _disconnectFromDatabase() async {
    if (_loadingConnectionId != null || _connectedId == null) return;
    
    setState(() {
      _loadingConnectionId = _connectedId;
    });
    
    try {
      print("ManageConnectionsScreen: Disconnecting from database");
      
      // Use the database service to disconnect
      await _databaseService.disconnect();
      
      setState(() {
        _connectedId = null;
      });
      
      // Make sure connections are updated in UI
      _loadConnections();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected from database'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error disconnecting: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _loadingConnectionId = null;
      });
    }
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
        final bool isConnected = _connectedId == connection.id;
        
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${connection.username}@${connection.host}:${connection.port}/${connection.database}',
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isConnected ? 'Connected' : 'Disconnected',
                          style: TextStyle(
                            color: isConnected ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
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
                    onPressed: (_loadingConnectionId != null) || isConnected 
                      ? null 
                      : () => _editConnection(connection),
                  ),
                  if (!connection.isActive)
                    TextButton.icon(
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Set Active'),
                      onPressed: (_loadingConnectionId != null) || isConnected
                        ? null
                        : () => _setActiveConnection(connection),
                    ),
                  // Connect/Disconnect Button
                  _loadingConnectionId == connection.id
                  ? SizedBox(
                      height: 36,
                      width: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isConnected ? Colors.blue : Colors.green
                        ),
                      ),
                    )
                  : TextButton.icon(
                      icon: Icon(isConnected ? Icons.link_off : Icons.link),
                      label: Text(isConnected ? 'Disconnect' : 'Connect'),
                      style: TextButton.styleFrom(
                        foregroundColor: isConnected ? Colors.blue : Colors.green,
                      ),
                      onPressed: (_loadingConnectionId != null)
                        ? null
                        : isConnected
                          ? _disconnectFromDatabase
                          : () => _connectToDatabase(connection),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.errorColor,
                    ),
                    onPressed: (_loadingConnectionId != null) || isConnected
                      ? null
                      : () => _deleteConnection(connection),
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