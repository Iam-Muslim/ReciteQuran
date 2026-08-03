import 'package:flutter/foundation.dart';

class DebugLogger {
  static String _currentAsrBuffer = '';

  /// Updates the cached ASR buffer that will be appended to detailed logs.
  static void updateAsrBuffer(String buffer) {
    _currentAsrBuffer = buffer;
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  /// Central logging method with structured AI-readable layout.
  static void log(String tag, String message) {
    String logLine = '[${_timestamp()}] [$tag] $message';
    if (_currentAsrBuffer.isNotEmpty) {
      logLine += ' | ASR: $_currentAsrBuffer';
    }
    debugPrint(logLine);
  }

  /// Simple log for things that don't need the ASR buffer context attached.
  static void logSimple(String tag, String message) {
    debugPrint('[${_timestamp()}] [$tag] $message');
  }
}
