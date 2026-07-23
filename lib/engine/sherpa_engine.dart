// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';


class TranscriptionResult {
  final String text;
  final bool isFinal;
  final int startTime;
  final List<String> tokens;
  final List<double> timestamps;
  final List<double> ysProbs;

  TranscriptionResult({
    required this.text,
    this.isFinal = false,
    this.startTime = 0,
    this.tokens = const [],
    this.timestamps = const [],
    this.ysProbs = const [],
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

  bool get isInitialized => _isInitialized;
  
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
        _outputController.add(TranscriptionResult(
          text: data['text'] ?? '',
          isFinal: isFinal.toDart,
          startTime: DateTime.now().millisecondsSinceEpoch,
          tokens: List<String>.from(data['tokens'] ?? []),
          timestamps: List<double>.from((data['timestamps'] ?? []).map((e) => (e as num).toDouble())),
          ysProbs: List<double>.from((data['ys_probs'] ?? []).map((e) => (e as num).toDouble())),
        ));
      } catch (e) {
        print("[SherpaDart] Error parsing JSON result: $e");
      }
    }.toJS;
    
    globalContext.setProperty('dartSherpaOnResult'.toJS, jsOnResult);

    print("[SherpaDart] Waiting for Sherpa WebAssembly memory to load...");

    // Wait for the WASM engine to start
    while (!_isWasmModuleLoaded().toDart) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    print("[SherpaDart] WASM Memory loaded. Loading models from Flutter assets...");

    try {
        JSUint8Array modelBytes;
        final host = Uri.base.host;
        if (host != 'localhost' && host != '127.0.0.1' && host.isNotEmpty) {
            print("[SherpaDart] Production detected on $host. Fetching ONNX model from GitHub Releases...");
            final url = '/download-model'.toJS;
            modelBytes = await _fetchSherpaModel(url).toDart as JSUint8Array;
        } else {
            print("[SherpaDart] Local environment detected. Loading ONNX model directly via Javascript fetch to bypass Chrome cache limits...");
            // Use absolute path based on base-href to fetch the asset directly
            final url = '/recite/assets/assets/model/quran_phoneme_zipformer.int8.onnx'.toJS;
            modelBytes = await _fetchSherpaModel(url).toDart as JSUint8Array;
        }
        
        _writeSherpaAssetToVFS('quran_phoneme_zipformer.int8.onnx'.toJS, modelBytes);
        print("[SherpaDart] Model written to VFS.");

        ByteData tokensData = await rootBundle.load('assets/model/tokens.txt');
        _writeSherpaAssetToVFS('quran_tokens.txt'.toJS, tokensData.buffer.asUint8List().toJS);
        print("[SherpaDart] Tokens written to VFS.");

        print("[SherpaDart] Initializing Sherpa Recognizer...");
        bool success = _initSherpaRecognizer().toDart;
        
        if (success) {
            print("[SherpaDart] Sherpa WebAssembly initialized successfully!");
            _isInitialized = true;
        } else {
            print("[SherpaDart] FATAL JS ERROR: Failed to create recognizer engine!");
        }
    } catch (e) {
        print("[SherpaDart] FATAL ERROR loading models: $e");
    }
  }

  bool transcribe(Uint8List audioChunk, {bool isFinal = false}) {
    // Obsolete: Audio capture and transcription is now handled entirely within Javascript.
    return true; 
  }

  void resetBuffer() {
    // Handled natively by Javascript AudioProcessor hook
  }

  void destroy() {
    // Cannot fully destroy the WASM module easily in this architecture, 
    globalContext.setProperty('dartSherpaOnResult'.toJS, null);
  }
}
