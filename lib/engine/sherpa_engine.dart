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
  final List<double> ysProbs;
  final int streamEpoch;

  TranscriptionResult({
    required this.text,
    this.isFinal = false,
    this.startTime = 0,
    this.tokens = const [],
    this.timestamps = const [],
    this.ysProbs = const [],
    this.streamEpoch = 0,
  });
}

@JS('isWasmModuleLoaded')
external JSBoolean _isWasmModuleLoaded();

@JS('writeSherpaAssetToVFS')
external JSBoolean _writeSherpaAssetToVFS(JSString filename, JSUint8Array bytes);

@JS('initSherpaRecognizer')
external JSBoolean _initSherpaRecognizer();

@JS('fetchSherpaModel')
external JSPromise _fetchSherpaModel(JSString url);

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
        final probsList = List<double>.from((data['ys_probs'] ?? []).map((e) => (e as num).toDouble()));
        
        if (probsList.isNotEmpty) {
           DebugLogger.logSimple('SherpaDart', '🎯 Tokens: $tokensList | Confidence (ysProbs): $probsList');
        }

        _outputController.add(TranscriptionResult(
          text: data['text'] ?? '',
          isFinal: isFinal.toDart,
          startTime: DateTime.now().millisecondsSinceEpoch,
          tokens: tokensList,
          timestamps: List<double>.from((data['timestamps'] ?? []).map((e) => (e as num).toDouble())),
          ysProbs: probsList,
          streamEpoch: _currentStreamEpoch,
        ));
      } catch (e) {
        DebugLogger.logSimple('SherpaDart', 'Error parsing JSON result: $e');
      }
    }.toJS;
    
    globalContext.setProperty('dartSherpaOnResult'.toJS, jsOnResult);

    DebugLogger.logSimple('SherpaDart', 'Waiting for Sherpa WebAssembly memory to load...');

    // Wait for the WASM engine to start
    while (!_isWasmModuleLoaded().toDart) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    DebugLogger.logSimple('SherpaDart', 'WASM Memory loaded. Loading models from Flutter assets...');

    try {
        const String modelFileName = 'zipformer_p_arabic_v2.int8.onnx';
        JSUint8Array modelBytes;
        final host = Uri.base.host;
        final String modelUrl;
        if (host != 'localhost' && host != '127.0.0.1' && host.isNotEmpty) {
            DebugLogger.logSimple('SherpaDart', 'Production detected on $host. Fetching ONNX model...');
            modelUrl = '/download-model?model=$modelFileName';
        } else {
            DebugLogger.logSimple('SherpaDart', 'Local environment detected. Fetching ONNX model...');
            modelUrl = 'https://github.com/Iam-Muslim/ReciteQuran/releases/download/v1.1.0/$modelFileName';
        }
        modelBytes = await _fetchSherpaModel(modelUrl.toJS).toDart as JSUint8Array;
        
        _writeSherpaAssetToVFS(modelFileName.toJS, modelBytes);
        DebugLogger.logSimple('SherpaDart', 'Model written to VFS.');

        ByteData tokensData = await rootBundle.load('assets/model/tokens.txt');
        _writeSherpaAssetToVFS('quran_tokens.txt'.toJS, tokensData.buffer.asUint8List().toJS);
        DebugLogger.logSimple('SherpaDart', 'Tokens written to VFS.');

        DebugLogger.logSimple('SherpaDart', 'Initializing Sherpa Recognizer...');
        bool success = _initSherpaRecognizer().toDart;
        
        if (success) {
            DebugLogger.logSimple('SherpaDart', 'Sherpa WebAssembly initialized successfully!');
            _isInitialized = true;
        } else {
            DebugLogger.logSimple('SherpaDart', 'FATAL JS ERROR: Failed to create recognizer engine!');
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
  }

  void destroy() {
    globalContext.setProperty('dartSherpaOnResult'.toJS, null);
  }
}
