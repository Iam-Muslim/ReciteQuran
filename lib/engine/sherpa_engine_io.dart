// lib/engine/sherpa_engine_io.dart
// Cache-aware streaming CTC engine for Quran-Lab/quran_phoneme_zipformer (Quran-Lab/zipformer_p-arabic)
//
// Model specs:
//   Architecture     = Zipformer2 causal streaming CTC (~65.5M parameters)
//   Tokens/Units     = 250 phoneme units (consonant+ḥaraka units) + blank_id
//   Front end        = 80-bin kaldi fbank (povey window, 25ms / 10ms shift, 16 kHz)
//   decode_chunk_len = 24 encoder frames / step (1000ms streaming profile -> 5.83 WER / 11.63% PER)
//   left_context     = 256 encoder frames cache
//   subsampling      = 8
//   hop_length       = 160 samples (10ms)
//   → 1 encoder frame = 80ms of audio

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

import '../utils/debug_logger.dart';
import 'models/sherpa_protocol.dart';

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

class SherpaEngine {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;

  final StreamController<TranscriptionResult> _outputController =
      StreamController<TranscriptionResult>.broadcast();

  bool _isInitialized = false;
  Future<void>? _initFuture;
  final List<SherpaCommand> _pendingChunks = [];
  int _currentStreamEpoch = 0;

  bool get isInitialized => _isInitialized;
  int get currentStreamEpoch => _currentStreamEpoch;
  Stream<TranscriptionResult> get transcriptionStream =>
      _outputController.stream;

  Future<String> _extractAsset(String assetPath) async {
    final Directory docDir = await getApplicationSupportDirectory();
    final String prefix = 'v2_zipformer_';
    final File file = File(
      '${docDir.path}/$prefix${assetPath.split('/').last}',
    );

    if (await file.exists()) {
      // Validate the existing file isn't from a crashed partial write.
      // If the file is suspiciously small (< 1KB), nuke it and re-extract.
      final int existingLen = await file.length();
      if (existingLen > 1024) {
        return file.path;
      }
      // Corrupt/truncated file from a previous OOM crash. Delete and re-extract.
      await file.delete();
    }

    // Load asset on the main thread where ServicesBinding is initialized
    ByteData data;
    try {
      data = await rootBundle.load('packages/recite_quran/$assetPath');
    } catch (_) {
      data = await rootBundle.load(assetPath);
    }
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    // ATOMIC WRITE: Write to a .tmp file first, then rename.
    // If the app is OOM-killed during writeAsBytes, the .tmp file is left
    // as garbage but the real file path doesn't exist yet, so the next
    // launch will correctly re-extract instead of loading a corrupt file.
    final File tmpFile = File('${file.path}.tmp');
    await tmpFile.writeAsBytes(bytes, flush: true);

    // Validate the write completed fully
    final int writtenLen = await tmpFile.length();
    if (writtenLen != bytes.length) {
      await tmpFile.delete();
      throw Exception(
        'CRITICAL: $assetPath partial write — expected ${bytes.length} bytes, got $writtenLen.',
      );
    }

    // Atomic rename: this is an inode operation, not a data copy.
    // It either succeeds completely or fails — no partial state.
    await tmpFile.rename(file.path);

    return file.path;
  }

  /// Pre-extract model assets from bundle to app documents directory.
  Future<void> preExtractAssets() async {
    await _extractAsset('assets/model/zipformer_p_arabic_v3.int8.onnx');
    await _extractAsset('assets/model/tokens.txt');
  }

  Future<void> initialize() {
    if (_isInitialized) return Future.value();
    if (_initFuture != null) return _initFuture!;
    _initFuture = _doInitialize();
    return _initFuture!;
  }

  Future<void> _doInitialize() async {
    _currentStreamEpoch = 0;
    if (_isolate != null) {
      if (_sendPort != null) {
        _sendPort!.send(const SherpaDestroyCommand());
        await Future.delayed(const Duration(milliseconds: 100));
      }
      _isolate?.kill(priority: Isolate.immediate);
    }
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;

    final String modelPath = await _extractAsset(
      'assets/model/zipformer_p_arabic_v3.int8.onnx',
    );
    final String tokensPath = await _extractAsset('assets/model/tokens.txt');

    final completer = Completer<void>();
    _receivePort = ReceivePort();

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _sendPort!.send(
          SherpaInitCommand(modelPath: modelPath, tokensPath: tokensPath),
        );
      } else if (message is SherpaInitSuccessEvent) {
        _isInitialized = true;
        _initFuture = null;
        completer.complete();
        for (final pending in _pendingChunks) {
          _sendPort?.send(pending);
        }
        _pendingChunks.clear();
      } else if (message is SherpaInitErrorEvent) {
        _initFuture = null;
        completer.completeError(Exception(message.error));
      } else if (message is SherpaTranscriptionEvent) {
        final int latency =
            DateTime.now().millisecondsSinceEpoch - message.startTime;

        if (kDebugMode) {
          DebugLogger.updateAsrBuffer(message.text);

          if (message.isFinal) {
            DebugLogger.log('ASR', '⚡ Endpoint detected (${latency}ms)');
          }
        }

        _outputController.add(
          TranscriptionResult(
            text: message.text,
            isFinal: message.isFinal,
            startTime: message.startTime,
            tokens: message.tokens,
            timestamps: message.timestamps,
            streamEpoch: message.streamEpoch,
          ),
        );
      }
    });

    _isolate = await Isolate.spawn(_isolateEntry, _receivePort!.sendPort);
    await completer.future;
  }

  /// Feed a normalized float chunk [-1.0, 1.0] (16 kHz mono) into the recognizer.
  bool transcribe(Float32List audioChunk, {bool isFinal = false}) {
    final transferable = TransferableTypedData.fromList([audioChunk]);
    final cmd = SherpaRecognizeCommand(
      chunk: transferable,
      isFinal: isFinal,
      startTime: DateTime.now().millisecondsSinceEpoch,
    );

    if (!_isInitialized) {
      if (_initFuture != null) {
        _pendingChunks.add(cmd);
      }
      return true;
    }

    _sendPort?.send(cmd);
    return true;
  }

  /// Hard reset: wipes the Sherpa stream and primes with silence.
  void resetBuffer() {
    _currentStreamEpoch++;
    _pendingChunks.clear();
    final cmd = const SherpaResetCommand();
    if (!_isInitialized && _initFuture != null) {
      _pendingChunks.add(cmd);
    } else {
      _sendPort?.send(cmd);
    }
  }

  /// Flush-then-Reset: crosses an Ayah boundary cleanly without loss of speech.
  void flushThenReset() {
    _currentStreamEpoch++;
    _pendingChunks.clear();
    final cmd = const SherpaFlushCommand();
    if (!_isInitialized && _initFuture != null) {
      _pendingChunks.add(cmd);
    } else {
      _sendPort?.send(cmd);
    }
  }

  void destroy() {
    if (!_isInitialized && _isolate == null) return;
    _isInitialized = false;
    _initFuture = null;
    _pendingChunks.clear();
    _sendPort?.send(const SherpaDestroyCommand());
    Future.delayed(const Duration(milliseconds: 200), () {
      _isolate?.kill(priority: Isolate.immediate);
      _receivePort?.close();
      _isolate = null;
      _sendPort = null;
      _receivePort = null;
    });
  }

  // ─── Isolate Worker ────────────────────────────────────────────────────────
  static void _isolateEntry(SendPort mainSendPort) {
    initBindings();

    final ReceivePort port = ReceivePort();
    mainSendPort.send(port.sendPort);

    OnlineRecognizer? recognizer;
    OnlineStream? stream;
    final Float32List primingBuffer = Float32List(
      7680,
    ); // 480ms (exact 1 ONNX chunk stride = 48 frames) pre-roll silence
    int isolateStreamEpoch = 0;

    port.listen((msg) {
      if (msg is! SherpaCommand) return;

      switch (msg) {
        case SherpaInitCommand(:final modelPath, :final tokensPath):
          try {
            if (!File(modelPath).existsSync() ||
                !File(tokensPath).existsSync()) {
              throw Exception('CRITICAL: ONNX model files missing on disk.');
            }

            OnlineRecognizer? tryCreateRecognizer(String provider) {
              return OnlineRecognizer(
                OnlineRecognizerConfig(
                  feat: FeatureConfig(sampleRate: 16000, featureDim: 80),
                  model: OnlineModelConfig(
                    zipformer2Ctc: OnlineZipformer2CtcModelConfig(
                      model: modelPath,
                    ),
                    tokens: tokensPath,
                    numThreads: 2,
                    modelType: 'zipformer2_ctc',
                    provider: provider,
                    debug: kDebugMode,
                  ),
                  enableEndpoint: true,
                  rule1MinTrailingSilence: 10.0,
                  rule2MinTrailingSilence:
                      4.0, // Increased to 4s for Voice Search
                  rule3MinUtteranceLength:
                      9999.0, // Effectively disabled max utterance length
                ),
              );
            }

            // Hardware acceleration back end, one per platform:
            //   Android → XNNPACK  (optimized CPU kernels)
            //   iOS     → CoreML   (Apple Neural Engine / GPU)
            //   other   → plain CPU
            String accelName = '';
            if (Platform.isAndroid) {
              accelName = 'xnnpack';
            } else if (Platform.isIOS) {
              accelName = 'coreml';
            }

            // Poison-pill lock, one file per back end so a device that trips
            // over XNNPACK doesn't also disqualify CoreML (and vice versa).
            final File lockFile = File(
              '${File(modelPath).parent.path}/${accelName}_lock',
            );
            String provider = 'cpu';

            if (accelName.isNotEmpty) {
              if (lockFile.existsSync()) {
                // A crash loop was detected! The app natively aborted (SIGILL/SIGSEGV)
                // during the previous accelerator initialization. We must fallback to 'cpu'.
                provider = 'cpu';
              } else {
                // First attempt. Create the poison pill lock file.
                // If the accelerator natively aborts, this file will remain on
                // disk, protecting the next startup.
                lockFile.createSync();
                provider = accelName;
              }
            }

            try {
              recognizer = tryCreateRecognizer(provider);
              // DO NOT delete lockfile here!
              // XNNPACK lazily initializes its compute kernels — it probes
              // /proc/cpuinfo during the FIRST `decode()` call, not during
              // model loading. On LineageOS, the SIGILL fires at decode(),
              // not at OnlineRecognizer(). CoreML defers work the same way: the
              // ANE/GPU subgraph is compiled and first dispatched on decode(),
              // so an unsupported-op abort surfaces there too. If we delete the
              // lock here, the crash won't be detected and we get an infinite
              // crash loop.
            } catch (e) {
              // Graceful Dart exception during model loading (not a native abort).
              if (lockFile.existsSync()) {
                lockFile.deleteSync();
              }
              if (provider != 'cpu') {
                // Fallback to CPU on standard initialization errors.
                recognizer = tryCreateRecognizer('cpu');
              } else {
                rethrow;
              }
            }

            stream = recognizer!.createStream();
            stream!.acceptWaveform(sampleRate: 16000, samples: primingBuffer);
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }

            // ═══ SAFE TO DELETE LOCKFILE NOW ═══
            // If we reach this line, XNNPACK successfully executed its first
            // inference pass (which is when it lazily probes the CPU and selects
            // optimized kernels). The lockfile can now safely be removed.
            if (lockFile.existsSync()) {
              lockFile.deleteSync();
            }

            DebugLogger.logSimple('Engine', 'ASR provider in use: $provider');

            mainSendPort.send(const SherpaInitSuccessEvent());
          } catch (e) {
            mainSendPort.send(SherpaInitErrorEvent(e.toString()));
          }

        case SherpaRecognizeCommand(
            :final chunk,
            :final isFinal,
            :final startTime,
          ):
          if (recognizer == null || stream == null) return;

          final rawBytesTemp = chunk.materialize().asUint8List();
          final rawBytes = rawBytesTemp.offsetInBytes % 4 != 0
              ? Uint8List.fromList(rawBytesTemp)
              : rawBytesTemp;

          if (rawBytes.isNotEmpty) {
            final floats = rawBytes.buffer.asFloat32List(
              rawBytes.offsetInBytes,
              rawBytes.lengthInBytes ~/ 4,
            );
            stream!.acceptWaveform(sampleRate: 16000, samples: floats);
          }

          while (recognizer!.isReady(stream!)) {
            recognizer!.decode(stream!);
          }

          final partial = recognizer!.getResult(stream!);
          final bool endpointDetected = recognizer!.isEndpoint(stream!);

          if (!endpointDetected && !isFinal) {
            mainSendPort.send(
              SherpaTranscriptionEvent(
                text: partial.text,
                tokens: List<String>.from(partial.tokens),
                timestamps: List<double>.from(partial.timestamps),
                isFinal: false,
                startTime: startTime,
                streamEpoch: isolateStreamEpoch,
              ),
            );
          }

          if (isFinal || endpointDetected) {
            // `partial` above was read from an already fully drained stream, so
            // it IS the complete hypothesis for this utterance. Only the
            // inputFinished() path can add anything to it, so only that path
            // pays for a second drain + getResult().
            OnlineRecognizerResult finalResult = partial;
            if (isFinal) {
              stream!.inputFinished();
              while (recognizer!.isReady(stream!)) {
                recognizer!.decode(stream!);
              }
              finalResult = recognizer!.getResult(stream!);
            }

            mainSendPort.send(
              SherpaTranscriptionEvent(
                text: finalResult.text,
                tokens: List<String>.from(finalResult.tokens),
                timestamps: List<double>.from(finalResult.timestamps),
                isFinal: true,
                startTime: startTime,
                streamEpoch: isolateStreamEpoch,
              ),
            );

            // Close the utterance off. sherpa-onnx requires this: its own C API
            // documents the contract as
            //   if (IsEndpoint(recognizer, stream)) { Reset(recognizer, stream); }
            // and Reset is the only thing that clears the decoder's accumulated
            // hypothesis and its trailing-silence counter.
            //
            // Without it the stream never starts a new utterance: IsEndpoint stays
            // true for every subsequent chunk, so partial results are suppressed
            // for the whole of each silence, and getResult() keeps returning one
            // ever-growing transcript of everything heard since the session began.
            //
            // The consumer side is handled in the same change: AsrTokenProcessor
            // already resets itself when a result's token prefix diverges, and
            // HighlightingController now arms _expectingNewSegment on isFinal so
            // the sequencer drops asrCharAnchor with the restarted hypothesis.
            // Both halves are required -- resetting here alone would leave the
            // anchor pointing past the end of the new, shorter hypothesis.
            //
            // The stream epoch is deliberately NOT bumped. This is a new utterance
            // on the same stream, not a caller-initiated reset, and bumping it here
            // would desynchronise the isolate from the main isolate's counter and
            // make every later result look stale.
            //
            // Skipped when isFinal, because inputFinished() has permanently closed
            // the stream to further input and the session is ending regardless.
            //
            // Reset only -- deliberately WITHOUT the 480ms silence pre-roll that
            // SherpaResetCommand performs. That pre-roll belongs to a hard reset
            // at a session or ayah boundary; injecting it after every endpoint
            // was measured to stop word matching entirely, because each utterance
            // then opens with silence the sequencer has to anchor past. sherpa's
            // own documented contract for this site is a bare Reset().
            if (endpointDetected && !isFinal) {
              recognizer!.reset(stream!);
            }
          }

        case SherpaFlushCommand():
          break;

        case SherpaResetCommand():
          isolateStreamEpoch++;
          if (recognizer != null && stream != null) {
            recognizer!.reset(stream!);
            stream!.acceptWaveform(sampleRate: 16000, samples: primingBuffer);
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }
          }

        case SherpaDestroyCommand():
          stream?.free();
          recognizer?.free();
          stream = null;
          recognizer = null;
      }
    });
  }
}
