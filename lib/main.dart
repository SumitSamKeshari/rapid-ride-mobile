import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/rider_map_screen.dart';
import 'services/logger_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize persistent file logger
  await AppLogger.initialize();
  AppLogger.info('AppMain', 'Rapid Ride mobile client starting up');

  // 2. Global Flutter framework error boundary
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.error('FlutterError', details.exceptionAsString(), details.exception, details.stack);
  };

  // 3. Global uncaught asynchronous error boundary
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('AsyncPlatformError', error.toString(), error, stack);
    return true; // marked as handled
  };

  runApp(const RepidRideApp());
}

class RepidRideApp extends StatelessWidget {
  const RepidRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Repid Ride',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final role = prefs.getString('user_role');

      if (!mounted) return;

      if (token != null && token.isNotEmpty) {
        AppLogger.info('AuthGate', 'Found active session for role: $role');
        if (role == 'Driver') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MapScreen()));
          return;
        } else if (role == 'Rider') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RiderMapScreen()));
          return;
        }
      }
    } catch (e, stack) {
      AppLogger.error('AuthGate', 'Error inspecting session', e, stack);
    }

    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}