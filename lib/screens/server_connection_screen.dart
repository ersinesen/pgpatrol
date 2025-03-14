import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:postgres/postgres.dart';
import '../models/server_connection.dart';
import '../services/connection_manager.dart';
import '../theme/app_theme.dart';

class ServerConnectionScreen extends StatefulWidget {
  final ServerConnection? connection;
  final bool isEditing;
  
  const ServerConnectionScreen({
    Key? key, 
    this.connection,
    this.isEditing = false,
  }) : super(key: key);

  @override
  _ServerConnectionScreenState createState() => _ServerConnectionScreenState();
}

class _ServerConnectionScreenState extends State<ServerConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _databaseController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isActive = false;
  bool _isTestingConnection = false;
  String? _testConnectionResult;
  bool _testConnectionSuccess = false;
  bool _obscurePassword = true;
  
  // Connection manager instance
  final ConnectionManager _connectionManager = ConnectionManager();

  @override
  void initState() {
    super.initState();
    if (widget.connection != null) {
      // Pre-fill form with existing connection details
      _nameController.text = widget.connection!.name;
      _hostController.text = widget.connection!.host;
      _portController.text = widget.connection!.port.toString();
      _databaseController.text = widget.connection!.database;
      _usernameController.text = widget.connection!.username;
      _passwordController.text = widget.connection!.password;
      _isActive = widget.connection!.isActive;
    } else {
      // Default values for new connection
      _portController.text = '5432';
      _isActive = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isTestingConnection = true;
      _testConnectionResult = null;
      _testConnectionSuccess = false;
    });
    
    // Create a temporary connection for testing
    final connection = ServerConnection(
      id: widget.connection?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      host: _hostController.text,
      port: int.parse(_portController.text),
      database: _databaseController.text,
      username: _usernameController.text,
      password: _passwordController.text,
    );
    
    try {
      // Create a PostgreSQL connection just for testing
      final conn = PostgreSQLConnection(
        connection.host,
        connection.port,
        connection.database,
        username: connection.username,
        password: connection.password,
        useSSL: false,
      );
      
      await conn.open();
      final result = await conn.query('SELECT version();');
      final version = result.first.first.toString();
      await conn.close();
      
      setState(() {
        _isTestingConnection = false;
        _testConnectionResult = 'Connected successfully!\nServer: $version';
        _testConnectionSuccess = true;
      });
    } catch (e) {
      setState(() {
        _isTestingConnection = false;
        _testConnectionResult = 'Connection failed: ${e.toString()}';
        _testConnectionSuccess = false;
      });
    }
  }

  Future<void> _saveConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    // Create or update connection
    final connection = ServerConnection(
      id: widget.connection?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      host: _hostController.text,
      port: int.parse(_portController.text),
      database: _databaseController.text,
      username: _usernameController.text,
      password: _passwordController.text,
      isActive: _isActive,
    );
    
    // Save to connection manager
    if (widget.isEditing) {
      await _connectionManager.updateConnection(connection);
    } else {
      await _connectionManager.addConnection(connection);
    }
    
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Connection' : 'Add Connection'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Save'),
            onPressed: _saveConnection,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Connection Name',
                  hintText: 'e.g., Production Database',
                  icon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a connection name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Connection details section
              Text(
                'Connection Details',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              // Host
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: 'localhost or IP address',
                  icon: Icon(Icons.computer),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a host';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Port
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  icon: Icon(Icons.route),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a port';
                  }
                  final port = int.tryParse(value);
                  if (port == null || port <= 0 || port > 65535) {
                    return 'Port must be between 1 and 65535';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Database
              TextFormField(
                controller: _databaseController,
                decoration: const InputDecoration(
                  labelText: 'Database',
                  hintText: 'e.g., postgres',
                  icon: Icon(Icons.storage),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a database name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              
              // Authentication section
              Text(
                'Authentication',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              // Username
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'e.g., postgres',
                  icon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Password
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  icon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                validator: (value) {
                  // Password can be empty for some PostgreSQL configurations
                  return null;
                },
              ),
              const SizedBox(height: 24),
              
              // Set as active connection
              SwitchListTile(
                title: const Text('Set as Active Connection'),
                subtitle: const Text('Use this connection when the app starts'),
                value: _isActive,
                onChanged: (value) {
                  setState(() {
                    _isActive = value;
                  });
                },
              ),
              const SizedBox(height: 24),
              
              // Test connection button
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Test Connection'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _isTestingConnection ? null : _testConnection,
                ),
              ),
              
              // Test connection result
              if (_isTestingConnection) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                const Center(child: Text('Testing connection...')),
              ],
              
              if (_testConnectionResult != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _testConnectionSuccess 
                        ? AppTheme.secondaryColor.withOpacity(0.1) 
                        : AppTheme.errorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _testConnectionSuccess 
                          ? AppTheme.secondaryColor 
                          : AppTheme.errorColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testConnectionSuccess 
                            ? Icons.check_circle 
                            : Icons.error,
                        color: _testConnectionSuccess 
                            ? AppTheme.secondaryColor 
                            : AppTheme.errorColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _testConnectionResult!,
                          style: TextStyle(
                            color: _testConnectionSuccess 
                                ? AppTheme.secondaryColor 
                                : AppTheme.errorColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              
              // Save button
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: Text(widget.isEditing ? 'Update Connection' : 'Save Connection'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _saveConnection,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}