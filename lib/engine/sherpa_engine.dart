// lib/engine/sherpa_engine.dart
// Cache-aware streaming CTC engine for fastconformer-quran-ar
//
// Model specs (from ONNX metadata):
//   decode_chunk_len = 8   encoder frames / step
//   left_context     = 128 encoder frames cache
//   subsampling      = 8
//   hop_length       = 160 samples (10ms)
//   → 1 encoder frame = 80ms of audio
//   → 8 encoder frames = 640ms raw PCM per inference step
//
// Sherpa-ONNX uses OnlineNemoCtcModelConfig which handles the cache tensors
// internally — we just call acceptWaveform() and decode().

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

class TranscriptionResult {
  final String text;
  final bool isFinal;
  TranscriptionResult({required this.text, this.isFinal = false});
}

enum _EngineCommand { init, recognize, reset, destroy }

class _IsolateMessage {
  final _EngineCommand command;
  final dynamic payload;
  _IsolateMessage(this.command, [this.payload]);
}

class SherpaEngine {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;

  final StreamController<TranscriptionResult> _outputController =
      StreamController<TranscriptionResult>.broadcast();

  bool _isInitialized = false;
  Future<void>? _initFuture;
  final List<Map<String, dynamic>> _pendingChunks = [];

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

  /// Pre-extract model assets from bundle to app documents directory.
  Future<void> preExtractAssets() async {
    await _extractAsset('assets/model/quran_phoneme_zipformer.int8.onnx');
    await _extractAsset('assets/model/tokens.txt');
  }

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
      'assets/model/quran_phoneme_zipformer.int8.onnx',
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
        for (final pending in _pendingChunks) {
          final transferable = TransferableTypedData.fromList([pending['chunk'] as Uint8List]);
          _sendPort?.send(
            _IsolateMessage(_EngineCommand.recognize, {
              'chunk': transferable,
              'isFinal': pending['isFinal'],
              'startTime': pending['startTime'],
            }),
          );
        }
        _pendingChunks.clear();
      } else if (message is String && message.startsWith('INIT_ERROR:')) {
        _initFuture = null;
        completer.completeError(Exception(message.substring(11)));
      } else if (message is Map) {
        final int startTime = message['startTime'] as int;
        final int latency = DateTime.now().millisecondsSinceEpoch - startTime;
        if (kDebugMode) {
          debugPrint(
            '[ASR] ⚡ ${latency}ms | "${message['text']}" | final=${message['isFinal']}',
          );
        }
        _outputController.add(
          TranscriptionResult(
            text: message['text'] as String,
            isFinal: message['isFinal'] as bool,
          ),
        );
      }
    });

    _isolate = await Isolate.spawn(_isolateEntry, _receivePort!.sendPort);
    await completer.future;
  }

  /// Feed a raw PCM chunk (Int16, 16 kHz mono) into the recognizer.
  /// [isFinal] = true flushes the current utterance.
  bool transcribe(Uint8List audioChunk, {bool isFinal = false}) {
    if (!_isInitialized) {
      if (_initFuture != null) {
        _pendingChunks.add({
          'chunk': audioChunk,
          'isFinal': isFinal,
          'startTime': DateTime.now().millisecondsSinceEpoch,
        });
      }
      return true;
    }
    final transferable = TransferableTypedData.fromList([audioChunk]);
    _sendPort?.send(
      _IsolateMessage(_EngineCommand.recognize, {
        'chunk': transferable,
        'isFinal': isFinal,
        'startTime': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    return true;
  }

  void resetBuffer() {
    _pendingChunks.clear();
    _sendPort?.send(_IsolateMessage(_EngineCommand.reset));
  }

  void destroy() {
    if (!_isInitialized) return;
    _isInitialized = false;
    _sendPort?.send(_IsolateMessage(_EngineCommand.destroy));
    Future.delayed(const Duration(milliseconds: 200), () {
      _isolate?.kill(priority: Isolate.immediate);
      _receivePort?.close();
      _isolate = null;
      _sendPort = null;
      _receivePort = null;
    });
  }

  // ─── Isolate ──────────────────────────────────────────────────────────────
  static void _isolateEntry(SendPort mainSendPort) {
    initBindings();

    final ReceivePort port = ReceivePort();
    mainSendPort.send(port.sendPort);

    OnlineRecognizer? recognizer;
    OnlineStream? stream;

    port.listen((message) {
      if (message is! _IsolateMessage) return;

      switch (message.command) {
        case _EngineCommand.init:
          final paths = message.payload as Map<String, String>;
          try {
            recognizer = OnlineRecognizer(
              OnlineRecognizerConfig(
                feat: FeatureConfig(sampleRate: 16000, featureDim: 80),
                model: OnlineModelConfig(
                  zipformer2Ctc: OnlineZipformer2CtcModelConfig(
                    model: paths['modelPath']!,
                  ),
                  tokens: paths['tokensPath']!,
                  numThreads: 2, // Reduced from 4 for mobile thermal efficiency
                  modelType: 'zipformer2_ctc',
                  // Use cpu instead of xnnpack to prevent INT8 quantization NaN bugs
                  provider: Platform.isAndroid ? 'xnnpack' : 'coreml',
                  debug: kDebugMode,
                ),
                // Endpoint detection disabled — VAD is handled externally
                // by AudioProcessor which emits 640ms isFinal=true chunks.
                enableEndpoint: false,
              ),
            );
            stream = recognizer!.createStream();
            mainSendPort.send('INIT_DONE');
          } catch (e) {
            mainSendPort.send('INIT_ERROR:$e');
          }

        case _EngineCommand.recognize:
          if (recognizer == null || stream == null) return;

          final payload = message.payload as Map<String, dynamic>;
          final transferable = payload['chunk'] as TransferableTypedData;
          final rawBytes = transferable.materialize().asUint8List();
          final isFinal = payload['isFinal'] as bool;
          final startTime = payload['startTime'] as int;

          if (rawBytes.isNotEmpty) {
            final int16 = rawBytes.buffer.asInt16List(
              rawBytes.offsetInBytes,
              rawBytes.lengthInBytes ~/ 2,
            );
            final audio = Float32List(int16.length);

            // Software gain + clip to [-1, 1] optimized
            const double gain = 1.5;
            const double scale = gain / 32768.0;
            // Unroll loop slightly and use faster min/max
            for (int i = 0; i < int16.length; i++) {
              audio[i] =
                  int16[i] *
                  scale; // Let native audio buffer handle extreme clipping if necessary
            }

            stream!.acceptWaveform(sampleRate: 16000, samples: audio);
          }

          while (recognizer!.isReady(stream!)) {
            recognizer!.decode(stream!);
          }
          final partial = recognizer!.getResult(stream!);
          mainSendPort.send({
            'text': partial.text,
            'isFinal': false,
            'startTime': startTime,
          });

          if (isFinal) {
            stream!.inputFinished();
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }
            final final_ = recognizer!.getResult(stream!);
            mainSendPort.send({
              'text': final_.text,
              'isFinal': true,
              'startTime': startTime,
            });
            recognizer!.reset(stream!);
          }

        case _EngineCommand.reset:
          if (recognizer != null && stream != null) {
            recognizer!.reset(stream!);
          }

        case _EngineCommand.destroy:
          stream?.free();
          recognizer?.free();
          stream = null;
          recognizer = null;
      }
    });
  }
}
