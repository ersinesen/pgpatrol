import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/dashboard_screen.dart';
import 'theme/app_theme.dart';
import 'services/api_database_service.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Create and initialize the theme provider
  final themeProvider = ThemeProvider();
  await themeProvider.initializeTheme();
  
  // Create the database service
  final databaseService = ApiDatabaseService();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => themeProvider),
        Provider<ApiDatabaseService>.value(value: databaseService),
      ],
      child: const PostgreSQLMonitorApp(),
    ),
  );
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
  const PostgreSQLMonitorApp({Key? key}) : super(key: key);

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
          home: const DashboardScreen(),
        );
      },
    );
  }
}