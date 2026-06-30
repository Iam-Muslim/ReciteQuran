import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

class AudioProcessor {
  // ── Audio format constants ─────────────────────────────────────────────────
  static const int sampleRate = 16000;
  static const int numChannels = 1;
  static const int bytesPerSample = 2; // 16-bit PCM
  static const int bytesPerSec = sampleRate * numChannels * bytesPerSample;

  static const int chunkMs = 160;
  static const int chunkBytes = (bytesPerSec * chunkMs) ~/ 1000;

  Uint8List _frameBuffer = Uint8List(0);

  // ── VAD State ──────────────────────────────────────────────────────────
  VoiceActivityDetector? _vad;
  bool _vadWasDetected = false;

  // Pre-roll keeps audio BEFORE the VAD becomes confident, ensuring consonant attacks aren't lost
  final List<Uint8List> _preRollBufferList = [];
  static const int maxPreRollFrames = 4; // 640ms pre-roll

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;

  Future<String> _extractAsset(String assetPath) async {
    final Directory docDir = await getApplicationSupportDirectory();
    final String prefix = 'v2_silero_';
    final File file = File(
      '${docDir.path}/$prefix${assetPath.split('/').last}',
    );

    if (await file.exists()) {
      return file.path;
    }

    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _initVad() async {
    if (_vad != null) return;
    initBindings(); // from sherpa_onnx

    final String modelPath = await _extractAsset(
      'assets/model/silero_vad.onnx',
    );

    if (!File(modelPath).existsSync()) {
      throw Exception('CRITICAL: Silero VAD model missing on disk.');
    }

    final config = VadModelConfig(
      sileroVad: SileroVadModelConfig(
        model: modelPath,
        threshold:
            0.1, // Lowered from default 0.5 to keep long vowels (يييي) classified as speech
        minSilenceDuration: 2.5, // 2.5s hold: fix for long Quranic Madds
        minSpeechDuration: 0.15,
        maxSpeechDuration: 20.0,
      ),
      sampleRate: sampleRate,
      numThreads: 1,
    );

    _vad = VoiceActivityDetector(config: config, bufferSizeInSeconds: 10.0);
  }

  /// Start recording and streaming raw PCM continuously.
  Future<void> start({
    required void Function(Uint8List chunk, bool isFinal) onChunk,
  }) async {
    await stopAndGetAudio();
    await _initVad();

    _vad?.reset();
    _vadWasDetected = false;
    _preRollBufferList.clear();

    _recorder = AudioRecorder();

    final recordStream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    _subscription = recordStream.listen((Uint8List rawData) {
      // Ensure 16-bit alignment for downstream operations
      if (rawData.offsetInBytes % 2 != 0) {
        rawData = Uint8List.fromList(rawData);
      }

      Uint8List allBytes;
      if (_frameBuffer.isEmpty) {
        allBytes = rawData;
      } else {
        allBytes = Uint8List(_frameBuffer.length + rawData.length);
        allBytes.setAll(0, _frameBuffer);
        allBytes.setAll(_frameBuffer.length, rawData);
      }

      int offset = 0;
      // We process strictly in chunkBytes (160ms) blocks
      while (allBytes.length - offset >= chunkBytes) {
        final chunk = Uint8List.view(
          allBytes.buffer,
          allBytes.offsetInBytes + offset,
          chunkBytes,
        );
        offset += chunkBytes;

        final chunkCopy = Uint8List.fromList(chunk);

        // Feed chunk to VAD
        final int16 = chunkCopy.buffer.asInt16List(
          chunkCopy.offsetInBytes,
          chunkCopy.lengthInBytes ~/ 2,
        );
        final samples = Float32List(int16.length);
        for (int i = 0; i < int16.length; i++) {
          samples[i] = int16[i] / 32768.0;
        }

        _vad!.acceptWaveform(samples);
        bool isDetected = _vad!.isDetected();

        if (isDetected) {
          if (!_vadWasDetected) {
            _vadWasDetected = true;
            // Flush pre-roll
            for (var pr in _preRollBufferList) {
              onChunk(pr, false);
            }
            _preRollBufferList.clear();
          }
          onChunk(chunkCopy, false);
        } else {
          if (_vadWasDetected) {
            // Silence duration exceeded the 2.5s threshold
            onChunk(Uint8List(0), true);
            _vadWasDetected = false;
          }
          // Not detected: maintain pre-roll to catch the onset when speech starts
          _preRollBufferList.add(chunkCopy);
          if (_preRollBufferList.length > maxPreRollFrames) {
            _preRollBufferList.removeAt(0);
          }
        }
      }

      // Keep the remainder for the next stream event
      if (offset < allBytes.length) {
        _frameBuffer = Uint8List.fromList(
          Uint8List.view(allBytes.buffer, allBytes.offsetInBytes + offset),
        );
      } else {
        _frameBuffer = Uint8List(0);
      }
    });
  }

  void clearBuffer() {
    // Left for compatibility with Orhcestrator
  }

  Future<void> stopAndGetAudio() async {
    await _subscription?.cancel();
    _subscription = null;

    await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;

    _frameBuffer = Uint8List(0);
    _vadWasDetected = false;
    _preRollBufferList.clear();
    _vad?.reset();
  }
}
