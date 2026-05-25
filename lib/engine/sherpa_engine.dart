/// Sherpa-ONNX ASR engine running in a dedicated Isolate.
library engine.sherpa_engine;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

// ---------------------------------------------------------------------------
// Public result type
// ---------------------------------------------------------------------------

class TranscriptionResult {
  final String text;
  final List<double> timestamps;
  final bool isFinal;

  TranscriptionResult({
    required this.text,
    required this.timestamps,
    this.isFinal = false,
  });
}

// ---------------------------------------------------------------------------
// Internal IPC types
// ---------------------------------------------------------------------------

enum _EngineCommand { init, recognize, destroy }

class _IsolateMessage {
  final _EngineCommand command;
  final dynamic payload;
  _IsolateMessage(this.command, [this.payload]);
}

// ---------------------------------------------------------------------------
// Engine host
// ---------------------------------------------------------------------------

class SherpaEngine {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;

  final StreamController<TranscriptionResult> _outputController =
      StreamController<TranscriptionResult>.broadcast();

  bool _isInitialized = false;
  bool _isBusy = false;
  _IsolateMessage? _pendingMessage; // Holds dropped audio to prevent lag

  bool get isInitialized => _isInitialized;

  Stream<TranscriptionResult> get transcriptionStream =>
      _outputController.stream;

  Future<String> _extractAsset(String assetPath) async {
    final Directory docDir = await getApplicationDocumentsDirectory();
    final File file = File('${docDir.path}/${assetPath.split('/').last}');

    if (await file.exists()) {
      return file.path;
    }

    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await file.writeAsBytes(bytes, flush: true);

    if (await file.length() == 0) {
      throw Exception(
        'CRITICAL: $assetPath copied as 0 bytes — check pubspec.yaml.',
      );
    }
    return file.path;
  }

  Future<void> preExtractAssets() async {
    await _extractAsset('assets/model/fastconformer_ar_ctc_q8.onnx');
    await _extractAsset('assets/model/tokens.txt');
  }

  Future<void>? _initFuture;

  Future<void> initialize() {
    if (_isInitialized) return Future.value();
    if (_initFuture != null) return _initFuture!;

    _initFuture = _doInitialize();
    return _initFuture!;
  }

  Future<void> _doInitialize() async {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;

    final String modelPath = await _extractAsset(
      'assets/model/fastconformer_ar_ctc_q8.onnx',
    );
    final String tokensPath = await _extractAsset('assets/model/tokens.txt');

    final completer = Completer<void>();
    _receivePort = ReceivePort();

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _sendPort!.send(
          _IsolateMessage(_EngineCommand.init, {
            'modelPath': modelPath,
            'tokensPath': tokensPath,
          }),
        );
      } else if (message == 'INIT_DONE') {
        _isInitialized = true;
        _initFuture = null;
        completer.complete();
      } else if (message is Map) {
        _isBusy = false;

        _outputController.add(
          TranscriptionResult(
            text: message['text'] as String,
            timestamps: (message['timestamps'] as List)
                .map((e) => (e as num).toDouble())
                .toList(),
            isFinal: message['isFinal'] as bool,
          ),
        );

        // Process queued chunk immediately so the UI stays snappy
        if (_pendingMessage != null) {
          final nextMsg = _pendingMessage!;
          _pendingMessage = null;
          _sendToIsolate(nextMsg);
        }
      }
    });

    _isolate = await Isolate.spawn(_isolateEntry, _receivePort!.sendPort);
    await completer.future;
  }

  void transcribe(Uint8List audioChunk, {bool isFinal = false}) {
    if (!_isInitialized) return;

    final transferable = TransferableTypedData.fromList([audioChunk]);
    final msg = _IsolateMessage(_EngineCommand.recognize, {
      'chunk': transferable,
      'isFinal': isFinal,
    });

    if (_isBusy) {
      // Queue the LATEST chunk (replaces any previous pending).
      // When inference finishes, the engine processes this queued chunk
      // immediately, ensuring it always works on the freshest audio.
      // Only one chunk is ever queued, so at most 2 consecutive inferences
      // run before the engine waits for the next emission — the CPU still
      // gets breathing room between cycles.
      _pendingMessage = msg;
      return;
    }

    _sendToIsolate(msg);
  }

  void _sendToIsolate(_IsolateMessage msg) {
    _isBusy = true;
    _sendPort?.send(msg);
  }

  void resetBuffer() {
    _isBusy = false;
    _pendingMessage = null;
  }

  void destroy() {
    if (!_isInitialized) return;
    _isInitialized = false;
    _isBusy = false;
    _pendingMessage = null;

    _sendPort?.send(_IsolateMessage(_EngineCommand.destroy));

    // Give isolate a moment to call recognizer.free() then nuke it
    Future.delayed(const Duration(milliseconds: 100), () {
      _isolate?.kill(priority: Isolate.immediate);
      _receivePort?.close();
      _isolate = null;
      _sendPort = null;
      _receivePort = null;
    });
  }

  static void _isolateEntry(SendPort mainSendPort) {
    initBindings();

    final ReceivePort isolateReceivePort = ReceivePort();
    mainSendPort.send(isolateReceivePort.sendPort);

    OfflineRecognizer? recognizer;

    isolateReceivePort.listen((message) {
      if (message is! _IsolateMessage) return;

      switch (message.command) {
        case _EngineCommand.init:
          final paths = message.payload as Map<String, String>;

          recognizer = OfflineRecognizer(
            OfflineRecognizerConfig(
              feat: FeatureConfig(sampleRate: 16000, featureDim: 80),
              model: OfflineModelConfig(
                nemoCtc: OfflineNemoEncDecCtcModelConfig(
                  model: paths['modelPath']!,
                ),
                tokens: paths['tokensPath']!,
                numThreads: 2,
                modelType: 'nemo_ctc',
                provider: Platform.isAndroid ? 'xnnpack' : 'coreml',
              ),
            ),
          );
          mainSendPort.send('INIT_DONE');

        case _EngineCommand.recognize:
          if (recognizer == null) return;

          final Map<String, dynamic> payload =
              message.payload as Map<String, dynamic>;
          final TransferableTypedData transferable =
              payload['chunk'] as TransferableTypedData;
          final Uint8List rawBytes = transferable.materialize().asUint8List();
          final bool isFinal = payload['isFinal'] as bool;

          final ByteData byteData = rawBytes.buffer.asByteData();
          final Float32List audio = Float32List(rawBytes.length ~/ 2);

          const double softwareGain = 1.5; // Boost volume by 50%

          for (int i = 0; i < audio.length; i++) {
            double sample = byteData.getInt16(i * 2, Endian.little) / 32768.0;
            audio[i] = (sample * softwareGain).clamp(-1.0, 1.0);
          }

          // INCREASED to  quarter second to prevent dropping trailing words
          final int padding = isFinal ? 4000 : 0;
          final Float32List padded = Float32List(audio.length + padding);
          padded.setAll(0, audio);

          final stream = recognizer!.createStream();

          try {
            stream.acceptWaveform(sampleRate: 16000, samples: padded);
            recognizer!.decode(stream);
            final result = recognizer!.getResult(stream);

            mainSendPort.send({
              'text': result.text,
              'timestamps': result.timestamps,
              'isFinal': isFinal,
            });
          } finally {
            stream.free();
          }

        case _EngineCommand.destroy:
          recognizer?.free();
          recognizer = null;
      }
    });
  }
}
