import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Environment mode for the RapidRide Flutter application.
enum Environment {
  development,
  production,
}

/// Centralized connection and environment configuration for RapidRide App.
/// 
/// Supported Modes:
/// 1. Local Machine Development (Default):
///    - Android Emulator: http://10.0.2.2:5172
///    - Web / Desktop / iOS Simulator: http://127.0.0.1:5172
/// 2. Production:
///    - Secure HTTPS/WSS: https://api.rapidride.com
/// 
/// How to Switch:
/// - In Code: Set `AppConfig.environment = Environment.production;`
/// - In Command Line / Build: Run with `--dart-define=ENV=prod`
/// - Custom IP (e.g. Wi-Fi Physical Device): Run with `--dart-define=API_URL=http://192.168.1.X:5172`
class AppConfig {
  // Read compile-time environment flag. Defaults to 'dev' (Development).
  static const String _envFromDefine = String.fromEnvironment('ENV', defaultValue: 'dev');

  // Custom API URL override (useful when testing on a physical phone via Wi-Fi).
  static const String _customApiUrl = String.fromEnvironment('API_URL', defaultValue: '');

  // Production Server Base URL (configured with production HTTPS domain).
  static const String _productionBaseUrl = String.fromEnvironment(
    'PROD_API_URL',
    defaultValue: 'https://api.rapidride.com',
  );

  // Active environment (defaults to compile-time ENV flag, or development).
  // Can also be toggled programmatically: AppConfig.environment = Environment.production;
  static Environment environment = _envFromDefine.toLowerCase() == 'prod' ||
          _envFromDefine.toLowerCase() == 'production'
      ? Environment.production
      : Environment.development;

  /// True if running in local development mode
  static bool get isDevelopment => environment == Environment.development;

  /// True if running in production mode
  static bool get isProduction => environment == Environment.production;

  /// Human-readable environment name
  static String get environmentName => isDevelopment ? 'Development' : 'Production';

  /// Resolves the active backend server URL according to current environment and device platform.
  static String get serverUrl {
    // 1. Explicit override via --dart-define=API_URL=...
    if (_customApiUrl.isNotEmpty) {
      return _customApiUrl;
    }

    // 2. Production Environment
    if (isProduction) {
      return _productionBaseUrl;
    }

    // 3. Local Machine Development Environment
    if (kIsWeb) {
      return 'http://127.0.0.1:5172';
    }

    if (Platform.isAndroid) {
      // 10.0.2.2 points to local machine host from Android emulator
      return 'http://10.0.2.2:5172';
    }

    // Windows Desktop, macOS, Linux, iOS Simulator
    return 'http://127.0.0.1:5172';
  }

  /// REST Authentication API endpoint
  static String get loginUrl => '$serverUrl/api/auth/login';

  /// Real-time SignalR Hub endpoint
  static String get rideHubUrl => '$serverUrl/rideHub';

  /// Comprehensive diagnostic summary for logging
  static String get summary =>
      '[$environmentName] BaseUrl: $serverUrl | Login: $loginUrl | Hub: $rideHubUrl';
}