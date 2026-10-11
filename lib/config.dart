import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  static String get serverUrl {
    // If running on Chrome Web
    //if (kIsWeb) return 'http://localhost:5172';
    if (kIsWeb) return 'http://127.0.0.1:5172';
    
    // If running on an Android Emulator
    if (Platform.isAndroid) return 'http://10.0.2.2:5172';
    
    // If running on Windows, Mac, or iOS Simulator
    //return 'http://localhost:5172'; 
    return 'http://127.0.0.1:5172';
  }

  // Helper getters for your specific endpoints
  static String get loginUrl => '$serverUrl/api/auth/login';
  static String get rideHubUrl => '$serverUrl/rideHub';
}