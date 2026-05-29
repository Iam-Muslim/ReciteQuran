import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileLogger {
  static final FileLogger _instance = FileLogger._internal();
  static FileLogger get instance => _instance;

  FileLogger._internal() {
    _init();
  }

  File? _logFile;
  final List<String> _buffer = [];
  bool _isWriting = false;

  Future<void> _init() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File('${directory.path}/debug_logs.txt');
      // Clear previous logs on startup
      if (await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
    } catch (e) {
      debugPrint('Failed to initialize logger: $e');
    }
  }

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(
      11,
      23,
    ); // time with ms
    final formattedMessage = '[$timestamp] $message\n';
    debugPrint(formattedMessage); // Print to standard console too
    _buffer.add(formattedMessage);
    _flush();
  }

  Future<void> _flush() async {
    if (_isWriting || _logFile == null || _buffer.isEmpty) return;
    _isWriting = true;

    final List<String> toWrite = List.from(_buffer);
    _buffer.clear();

    try {
      await _logFile!.writeAsString(toWrite.join(''), mode: FileMode.append);
    } catch (e) {
      debugPrint('Failed to write logs: $e');
    } finally {
      _isWriting = false;
      if (_buffer.isNotEmpty) {
        _flush();
      }
    }
  }

  Future<String?> getLogFilePath() async {
    return _logFile?.path;
  }
}
