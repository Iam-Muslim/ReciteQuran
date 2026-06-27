import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class AudioProcessor {
  // ── Audio format constants ─────────────────────────────────────────────────
  static const int sampleRate = 16000;
  static const int numChannels = 1;
  static const int bytesPerSample = 2; // 16-bit PCM
  static const int bytesPerSec = sampleRate * numChannels * bytesPerSample;

  /// The VAD processes audio in exactly 20ms frames.
  static const int frameMs = 20;
  static const int frameBytes = (bytesPerSec * frameMs) ~/ 1000;

  // ── Pre-roll Configuration ───────────────────────────────────────────────
  static const int preRollMs = 600;
  static const int maxPreRollFrames = preRollMs ~/ frameMs;

  // ── Silence / End of phrase ──────────────────────────────────────────────
  static const int maxSilenceMs = 800;
  static const int maxSilenceFrames = maxSilenceMs ~/ frameMs;

  // ── Streaming Chunk Configuration ────────────────────────────────────────
  /// For streaming models, we emit fixed non-overlapping chunks.
  /// 160ms chunks dramatically reduce latency vs 640ms.
  static const int chunkMs = 160;
  static const int chunkBytes = (bytesPerSec * chunkMs) ~/ 1000;

  // ── Internal state ────────────────────────────────────────────────────────
  Uint8List _frameBuffer = Uint8List(0);
  final List<Uint8List> _preRollBuffer = [];

  // Used to buffer incoming frames until they reach chunkBytes
  final List<Uint8List> _speechChunks = [];
  int _speechLength = 0;

  int _silenceFramesCount = 0;
  bool _isSpeaking = false;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;

  // ── VAD State ─────────────────────────────────────────────────────────────
  double _noiseFloor = 50.0;
  double _vadThresholdRms = 200.0;
  static const double kAlpha = 0.05;
  static const double kSnrThreshold = 2.0;

  /// Start recording and trigger VAD/chunking pipeline.
  Future<void> start({
    required void Function(Uint8List chunk, bool isFinal) onChunk,
    void Function()? onVadOff,
  }) async {
    await stopAndGetAudio();

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
      Uint8List allBytes;
      if (_frameBuffer.isEmpty) {
        allBytes = Uint8List.fromList(rawData);
      } else {
        allBytes = Uint8List(_frameBuffer.length + rawData.length);
        allBytes.setAll(0, _frameBuffer);
        allBytes.setAll(_frameBuffer.length, rawData);
      }

      int offset = 0;
      while (allBytes.length - offset >= frameBytes) {
        final frame = Uint8List.view(
          allBytes.buffer,
          allBytes.offsetInBytes + offset,
          frameBytes,
        );
        offset += frameBytes;

        _processFrame(frame, onChunk, onVadOff);
      }

      if (offset < allBytes.length) {
        _frameBuffer = Uint8List.fromList(
          Uint8List.view(allBytes.buffer, allBytes.offsetInBytes + offset),
        );
      } else {
        _frameBuffer = Uint8List(0);
      }
    });
  }

  void _processFrame(
    Uint8List frame,
    void Function(Uint8List chunk, bool isFinal) onChunk,
    void Function()? onVadOff,
  ) {
    bool hasSpeech = _isVoiceActive(frame);

    if (!_isSpeaking) {
      if (hasSpeech) {
        _isSpeaking = true;
        _silenceFramesCount = 0;

        if (kDebugMode) {
          debugPrint(
            '[AUDIO] 🎤 VAD ON (Recovered ${_preRollBuffer.length} pre-roll frames)',
          );
        }

        for (final p in _preRollBuffer) {
          _speechChunks.add(p);
          _speechLength += p.length;
        }
        _preRollBuffer.clear();

        _speechChunks.add(Uint8List.fromList(frame));
        _speechLength += frame.length;
      } else {
        _preRollBuffer.add(Uint8List.fromList(frame));
        if (_preRollBuffer.length > maxPreRollFrames) {
          _preRollBuffer.removeAt(0);
        }
      }
    } else {
      if (hasSpeech) {
        _silenceFramesCount = 0;
      } else {
        _silenceFramesCount++;
      }

      _speechChunks.add(Uint8List.fromList(frame));
      _speechLength += frame.length;

      // Emit chunk if it reaches the 240ms size
      if (_speechLength >= chunkBytes) {
        _emitChunk(onChunk, isFinal: false);
      }

      bool silenceTimeout = _silenceFramesCount >= maxSilenceFrames;
      if (silenceTimeout) {
        if (kDebugMode) {
          debugPrint('[AUDIO] 🔇 VAD OFF');
        }

        if (_speechLength > 0) {
          _emitChunk(onChunk, isFinal: false);
        }

        _speechChunks.clear();
        _speechLength = 0;
        _isSpeaking = false;
        _silenceFramesCount = 0;
        
        if (onVadOff != null) {
          onVadOff();
        }
      }
    }
  }

  void _emitChunk(
    void Function(Uint8List chunk, bool isFinal) onChunk, {
    required bool isFinal,
  }) {
    if (_speechLength == 0) return;

    Uint8List window = Uint8List(_speechLength);
    int innerOffset = 0;
    for (final chunk in _speechChunks) {
      window.setAll(innerOffset, chunk);
      innerOffset += chunk.length;
    }

    onChunk(window, isFinal);

    _speechChunks.clear();
    _speechLength = 0;
  }

  bool _isVoiceActive(Uint8List frame) {
    Int16List pcm = frame.buffer.asInt16List(
      frame.offsetInBytes,
      frame.lengthInBytes ~/ 2,
    );
    double sumSquares = 0;
    // Stride of 4 reduces CPU loop iterations by 75% with negligible accuracy loss
    int count = 0;
    for (int i = 0; i < pcm.length; i += 4) {
      double s = pcm[i].toDouble();
      sumSquares += s * s;
      count++;
    }
    double rms = math.sqrt(sumSquares / count);
    rms = math.max(rms, 1.0);

    if (!_isSpeaking) {
      _noiseFloor = (1.0 - kAlpha) * _noiseFloor + kAlpha * rms;
    }
    _vadThresholdRms = _noiseFloor * kSnrThreshold;
    return rms > _vadThresholdRms;
  }

  void clearBuffer() {
    _speechChunks.clear();
    _preRollBuffer.clear();
    _speechLength = 0;
  }

  Future<void> stopAndGetAudio() async {
    await _subscription?.cancel();
    _subscription = null;

    await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;

    _frameBuffer = Uint8List(0);
    _preRollBuffer.clear();
    _speechChunks.clear();
    _speechLength = 0;
    _isSpeaking = false;
    _silenceFramesCount = 0;

    _noiseFloor = 50.0;
    _vadThresholdRms = 200.0;
  }
}
