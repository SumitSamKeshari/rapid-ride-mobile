import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { info, warning, error }

class AppLogger {
  static File? _logFile;
  static final List<String> _inMemoryLogs = [];

  AppLogger._();

  static Future<void> initialize() async {
    try {
      if (!kIsWeb) {
        final directory = await getApplicationDocumentsDirectory();
        final logDir = Directory('${directory.path}/logs');
        if (!await logDir.exists()) {
          await logDir.create(recursive: true);
        }
        _logFile = File('${logDir.path}/rapidride_app.log');

        // Rotate if log exceeds 5MB
        if (await _logFile!.exists()) {
          final length = await _logFile!.length();
          if (length > 5 * 1024 * 1024) {
            final backup = File('${logDir.path}/rapidride_app_old.log');
            if (await backup.exists()) await backup.delete();
            await _logFile!.rename(backup.path);
            _logFile = File('${logDir.path}/rapidride_app.log');
          }
        }
      }
      info('Logger', 'Logger initialized successfully.');
    } catch (e) {
      debugPrint('Failed to initialize logger file: $e');
    }
  }

  static void info(String tag, String message) => _write(LogLevel.info, tag, message);
  static void warn(String tag, String message) => _write(LogLevel.warning, tag, message);
  static void error(String tag, String message, [Object? error, StackTrace? stack]) {
    final fullMessage = error != null ? '$message | Error: $error\n$stack' : message;
    _write(LogLevel.error, tag, fullMessage);
  }

  static void _write(LogLevel level, String tag, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] [${level.name.toUpperCase()}] [$tag] $message\n';

    if (kDebugMode) {
      debugPrint(logLine.trim());
    }

    _inMemoryLogs.add(logLine);
    if (_inMemoryLogs.length > 250) {
      _inMemoryLogs.removeAt(0);
    }

    if (!kIsWeb && _logFile != null) {
      _logFile!.writeAsString(logLine, mode: FileMode.append, flush: false).catchError((err) {
        debugPrint('File log write error: $err');
        return _logFile!;
      });
    }
  }

  static Future<String> readLogs() async {
    if (!kIsWeb && _logFile != null && await _logFile!.exists()) {
      return await _logFile!.readAsString();
    }
    return _inMemoryLogs.join();
  }
}
