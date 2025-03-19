import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/dashboard_screen.dart';
import 'theme/app_theme.dart';
import 'services/api_database_service.dart';
import 'services/database_service.dart';

import 'services/connection_manager.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Get the platform
  final bool useDirectConnection = !kIsWeb && Platform.isWindows;
  print('Main: useDirectConnection = $useDirectConnection');

  // Create and initialize the theme provider
  final themeProvider = ThemeProvider();
  await themeProvider.initializeTheme();
  
  // Initialize the ConnectionManager singleton
  await ConnectionManager().initialize();
  print('Main: ConnectionManager initialized');
  
  // Create the app with the appropriate database service
  if (useDirectConnection) {
    print('Using direct database connection for Windows');
    final databaseService = DatabaseService();
    
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => themeProvider),
          Provider<DatabaseService>.value(value: databaseService),
          Provider<ConnectionManager>.value(value: ConnectionManager()),
        ],
        child: const PostgreSQLMonitorApp(isDirectConnection: true),
      ),
    );
  } else {
    print('Using API database service for ${kIsWeb ? 'web' : Platform.operatingSystem}');
    final databaseService = ApiDatabaseService();
    
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => themeProvider),
          Provider<ApiDatabaseService>.value(value: databaseService),
          Provider<ConnectionManager>.value(value: ConnectionManager()),
        ],
        child: const PostgreSQLMonitorApp(isDirectConnection: false),
      ),
    );
  }

}

// Create a class to manage theme state with persistence
class ThemeProvider extends ChangeNotifier {
  static const String _themePreferenceKey = 'theme_preference';
  
  // Default to system theme initially
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  // Initialize theme from shared preferences
  Future<void> initializeTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString(_themePreferenceKey);
      
      if (savedTheme != null) {
        if (savedTheme == 'light') {
          _themeMode = ThemeMode.light;
        } else if (savedTheme == 'dark') {
          _themeMode = ThemeMode.dark;
        }
      }
    } catch (e) {
      // If there's an error, we'll just use the system theme as default
      _themeMode = ThemeMode.system;
    }
  }

  // Toggle theme and save preference
  void toggleTheme() async {
    if (_themeMode == ThemeMode.light) {
      _themeMode = ThemeMode.dark;
      _saveThemePreference('dark');
    } else {
      _themeMode = ThemeMode.light;
      _saveThemePreference('light');
    }
    notifyListeners();
  }
  
  // Save theme preference to shared preferences
  Future<void> _saveThemePreference(String theme) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themePreferenceKey, theme);
    } catch (e) {
      // If there's an error saving, we'll just continue without saving
      // This ensures the app doesn't crash if storage isn't available
    }
  }
  
  // Determine if we're in dark mode
  bool isDarkMode(BuildContext context) {
    if (_themeMode == ThemeMode.system) {
      return MediaQuery.of(context).platformBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }
}

class PostgreSQLMonitorApp extends StatelessWidget {
  final bool isDirectConnection;
  
  const PostgreSQLMonitorApp({Key? key, required this.isDirectConnection}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use Consumer to listen for theme changes
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          title: 'PostgreSQL Monitor',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          debugShowCheckedModeBanner: false,
          home: DashboardScreen(isDirectConnection: isDirectConnection),
        );
      },
    );
  }
}