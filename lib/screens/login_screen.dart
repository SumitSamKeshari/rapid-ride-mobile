import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../services/logger_service.dart';
import 'map_screen.dart';
import 'rider_map_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final email = _emailController.text.trim();
      AppLogger.info('LoginScreen', 'Attempting authentication for $email');

      final url = Uri.parse(AppConfig.loginUrl);
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'Email': email,
          'Password': _passwordController.text.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = (data['token'] ?? data['Token'])?.toString() ?? '';
        final userRole = (data['role'] ?? data['Role'])?.toString() ?? '';
        final userId = int.tryParse((data['userId'] ?? data['UserId'])?.toString() ?? '0') ?? 0;

        AppLogger.info('LoginScreen', 'Authentication success: UserId $userId, Role $userRole');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);
        await prefs.setString('user_role', userRole);
        await prefs.setInt('user_id', userId);

        if (!mounted) return;

        if (userRole == "Driver") {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MapScreen()));
        } else if (userRole == "Rider") {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RiderMapScreen()));
        } else {
          setState(() {
            _errorMessage = 'Unrecognized user role: $userRole';
          });
        }
      } else if (response.statusCode == 401) {
        AppLogger.warn('LoginScreen', 'Invalid credentials entered for $email');
        if (mounted) {
          setState(() {
            _errorMessage = 'Invalid email or password.';
          });
        }
      } else {
        AppLogger.warn('LoginScreen', 'Server returned error status: ${response.statusCode}');
        if (mounted) {
          setState(() {
            _errorMessage = 'Server error: ${response.statusCode}';
          });
        }
      }
    } catch (e, stack) {
      AppLogger.error('LoginScreen', 'Network or connection error during login', e, stack);
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error. Please verify backend is running.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rapid Ride Login')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_taxi, size: 90, color: Colors.blue),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _loginUser,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : const Text('Sign In', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}