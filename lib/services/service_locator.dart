import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'database_service.dart';
import 'api_service.dart';

/// ServiceLocator that provides the correct service implementation based on platform
class ServiceLocator {
  // Singleton pattern
  static final ServiceLocator _instance = ServiceLocator._internal();

  factory ServiceLocator() {
    return _instance;
  }

  ServiceLocator._internal();

  /// Returns the appropriate database service implementation based on the platform
  /// - Uses DatabaseService for desktop platforms (Windows, macOS, Linux)
  /// - Uses ApiService for web and mobile platforms
  dynamic getDatabaseService() {
    // Use direct database connection for desktop platforms
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      print('ServiceLocator: Using direct DatabaseService for desktop');
      return DatabaseService();
    } 
    
    // Use API service for web and mobile platforms
    print('ServiceLocator: Using ApiService for web/mobile');
    return ApiService();
  }
}