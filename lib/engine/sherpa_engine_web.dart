// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import '../utils/debug_logger.dart';

class TranscriptionResult {
  final String text;
  final bool isFinal;
  final int startTime;
  final List<String> tokens;
  final List<double> timestamps;
  final int streamEpoch;

  TranscriptionResult({
    required this.text,
    this.isFinal = false,
    this.startTime = 0,
    this.tokens = const [],
    this.timestamps = const [],
    this.streamEpoch = 0,
  });
}

@JS('isWasmModuleLoaded')
external JSBoolean _isWasmModuleLoaded();

@JS('writeSherpaAssetToVFS')
external JSBoolean _writeSherpaAssetToVFS(
  JSString filename,
  JSUint8Array bytes,
);

@JS('initSherpaRecognizer')
external JSBoolean _initSherpaRecognizer();

@JS('fetchSherpaModel')
external JSPromise _fetchSherpaModel(JSString url);

@JS('resetOfficialSherpaBuffer')
external void _resetOfficialSherpaBuffer();

/// Web-specific implementation of SherpaEngine using Official Sherpa WebAssembly JS.
class SherpaEngine {
  final StreamController<TranscriptionResult> _outputController =
      StreamController<TranscriptionResult>.broadcast();

  bool _isInitialized = false;
  int _currentStreamEpoch = 0;

  bool get isInitialized => _isInitialized;
  int get currentStreamEpoch => _currentStreamEpoch;

  Stream<TranscriptionResult> get transcriptionStream =>
      _outputController.stream;

  Future<void> preExtractAssets() async {
    // Handled in initialize for Web
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    final JSFunction jsOnResult = (JSString jsonStr, JSBoolean isFinal) {
      try {
        final Map<String, dynamic> data = jsonDecode(jsonStr.toDart);
        final tokensList = List<String>.from(data['tokens'] ?? []);
        final text = data['text'] ?? '';
        final isFinalDart = isFinal.toDart;

        DebugLogger.logSimple(
          'SherpaWeb',
          '📥 ASR Event: text="$text", tokens=${tokensList.length}, isFinal=$isFinalDart, epoch=$_currentStreamEpoch',
        );

        _outputController.add(
          TranscriptionResult(
            text: text,
            isFinal: isFinalDart,
            startTime: DateTime.now().millisecondsSinceEpoch,
            tokens: tokensList,
            timestamps: List<double>.from(
              (data['timestamps'] ?? []).map((e) => (e as num).toDouble()),
            ),
            streamEpoch: _currentStreamEpoch,
          ),
        );
      } catch (e) {
        DebugLogger.logSimple('SherpaDart', 'Error parsing JSON result: $e');
      }
    }.toJS;

    globalContext.setProperty('dartSherpaOnResult'.toJS, jsOnResult);

    try {
      const String modelFileName = 'zipformer_p_arabic_v3.int8.onnx';
      const String modelUrl = '/download-model?model=$modelFileName';
      DebugLogger.logSimple(
        'SherpaDart',
        'Fetching ONNX model from $modelUrl (in parallel with WASM load)...',
      );

      // Start fetching the model in parallel with WASM memory compilation
      final modelFuture = _fetchSherpaModel(modelUrl.toJS).toDart;

      // Concurrently wait for the WASM engine to start (with a 120s timeout for mobile devices)
      int waitCount = 0;
      while (!_isWasmModuleLoaded().toDart) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
        if (waitCount > 1200) {
          DebugLogger.logSimple('SherpaDart', 'TIMEOUT waiting for WASM module!');
          return;
        }
      }

      DebugLogger.logSimple(
        'SherpaDart',
        'WASM Memory loaded. Awaiting model bytes...',
      );

      final modelRaw = await modelFuture;
      if (modelRaw == null) {
        DebugLogger.logSimple('SherpaDart', 'Model bytes returned null! Cannot initialize.');
        return;
      }
      final JSUint8Array modelBytes = modelRaw as JSUint8Array;

      _writeSherpaAssetToVFS(modelFileName.toJS, modelBytes);
      DebugLogger.logSimple('SherpaDart', 'Model written to VFS.');

      ByteData tokensData = await rootBundle.load('assets/model/tokens.txt');
      _writeSherpaAssetToVFS(
        'quran_tokens.txt'.toJS,
        tokensData.buffer.asUint8List().toJS,
      );
      DebugLogger.logSimple('SherpaDart', 'Tokens written to VFS.');

      DebugLogger.logSimple('SherpaDart', 'Initializing Sherpa Recognizer...');
      bool success = _initSherpaRecognizer().toDart;

      if (success) {
        DebugLogger.logSimple(
          'SherpaDart',
          'Sherpa WebAssembly initialized successfully!',
        );
        _isInitialized = true;
      } else {
        DebugLogger.logSimple(
          'SherpaDart',
          'FATAL JS ERROR: Failed to create recognizer engine!',
        );
      }
    } catch (e) {
      DebugLogger.logSimple('SherpaDart', 'FATAL ERROR loading models: $e');
    }
  }

  bool transcribe(Float32List audioChunk, {bool isFinal = false}) {
    // Handled in Web through JS AudioProcessor hook
    return true;
  }

  void resetBuffer() {
    _currentStreamEpoch++;
    try {
      _resetOfficialSherpaBuffer();
    } catch (_) {}
    DebugLogger.logSimple(
      'SherpaWeb',
      '🔄 resetBuffer() executed (epoch: $_currentStreamEpoch)',
    );
  }

  void flushThenReset() {
    _currentStreamEpoch++;
    try {
      _resetOfficialSherpaBuffer();
    } catch (_) {}
    DebugLogger.logSimple(
      'SherpaWeb',
      '🔄 flushThenReset() executed (epoch: $_currentStreamEpoch)',
    );
  }

  void destroy() {
    globalContext.setProperty('dartSherpaOnResult'.toJS, null);
  }
}
