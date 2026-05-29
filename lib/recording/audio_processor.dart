// Real-time audio capture and Voice Activity Detection (VAD).
//
// Captures 16kHz mono 16-bit PCM audio from the microphone, detects
// speech vs silence using RMS-based VAD, and emits audio chunks for
// ASR inference.
//
// Audio pipeline flow:
//   Microphone → Raw PCM bytes → 30ms frame slicing → VAD check →
//   Speech buffer accumulation → Sliding window emission → ASR engine
//
// Key parameters (tuned for Arabic recitation):
// - [expandStepBytes]: 400ms — how often audio is sent to ASR (latency knob)
// - [maxBufferBytes]: 3.5s — maximum speech buffer before trimming
// - [maxSilenceMs]: 800ms — silence duration to finalize a phrase
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:record/record.dart';
import '../utils/file_logger.dart';
import '../core/types.dart';

// Configuration for the sliding audio window.
class AudioWindowConfig {
  final int expandStepBytes;
  final int maxBufferBytes;

  const AudioWindowConfig({
    required this.expandStepBytes,
    required this.maxBufferBytes,
  });

  /// Configures the audio sliding window based on the device's hardware tier.
  factory AudioWindowConfig.fromTier(HardwareTier tier) {
    const int bytesPerSec = AudioProcessor.bytesPerSec;
    switch (tier) {
      case HardwareTier.flagship:
        return const AudioWindowConfig(
          expandStepBytes: (bytesPerSec * 300) ~/ 1000,
          maxBufferBytes: (bytesPerSec * 3500) ~/ 1000,
        );
      case HardwareTier.standard:
        return const AudioWindowConfig(
          expandStepBytes: (bytesPerSec * 600) ~/ 1000,
          maxBufferBytes: (bytesPerSec * 3000) ~/ 1000,
        );
      case HardwareTier.budget:
        return const AudioWindowConfig(
          expandStepBytes: (bytesPerSec * 1000) ~/ 1000,
          maxBufferBytes: (bytesPerSec * 2500) ~/ 1000,
        );
    }
  }
}

class AudioProcessor {
  // ── Audio format constants ─────────────────────────────────────────────────
  static const int sampleRate = 16000;
  static const int bytesPerSample = 2; // 16-bit PCM = 2 bytes per sample
  static const int bytesPerSec =
      sampleRate * bytesPerSample; // 32,000 bytes/sec

  // ── VAD (Voice Activity Detection) parameters ─────────────────────────────
  /// Frame duration for RMS analysis — 30ms strikes a balance between
  /// responsiveness and computational cost.
  static const int frameMs = 30;

  /// Bytes in a single analysis frame.
  static const int frameBytes = (sampleRate * bytesPerSample * frameMs) ~/ 1000;

  /// Minimum RMS volume threshold to classify a frame as speech.
  /// Auto-calibrated from the first 10 frames of ambient noise.
  double _vadThresholdRms = 100.0;

  /// Calibration state — measures ambient noise to set dynamic threshold.
  bool _isCalibrated = false;
  int _calibrationFramesCount = 0;
  double _calibrationSumRms = 0.0;

  /// Maximum silence before finalizing a speech segment.
  /// Increased to 1500ms to better support slow Murattal recitation.
  /// This prevents the VAD from aggressively chopping phrases into single words.
  static const int maxSilenceMs = 1500;
  static const int maxSilenceFrames = maxSilenceMs ~/ frameMs;

  // ── Dynamic Window Configuration ──────────────────────────────────────────
  late AudioWindowConfig _config = AudioWindowConfig.fromTier(
    HardwareTier.flagship,
  );

  void setConfig(AudioWindowConfig config) {
    _config = config;
    FileLogger.instance.log(
      '[AUDIO] Configuration updated: expandStep=${config.expandStepBytes}, maxBuffer=${config.maxBufferBytes}',
    );
  }

  // ── Internal state ────────────────────────────────────────────────────────
  Uint8List _frameBuffer = Uint8List(0);
  final List<Uint8List> _speechChunks = [];
  int _speechLength = 0;
  int _silenceFramesCount = 0;
  bool _isSpeaking = false;
  int _lastEmitBytes = 0;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;

  /// Starts the microphone stream and begins processing audio.
  ///
  /// [onChunk] is called with audio data when either:
  /// 1. Enough new speech data has accumulated (non-final)
  /// 2. A silence timeout finalizes the current phrase (final)
  Future<void> start({
    required void Function(Uint8List chunk, bool isFinal) onChunk,
  }) async {
    await stopAndGetAudio();

    _recorder = AudioRecorder();

    if (!await _recorder!.hasPermission()) {
      throw Exception("Microphone recording permission denied");
    }

    // Raw 16kHz mono PCM with hardware noise suppression and auto-gain
    final recordStream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: false,
        noiseSuppress: true,
      ),
    );

    _subscription = recordStream.listen((Uint8List rawData) {
      // Concatenate leftover bytes from previous callback
      Uint8List allBytes;
      if (_frameBuffer.isEmpty) {
        allBytes = rawData;
      } else {
        allBytes = Uint8List(_frameBuffer.length + rawData.length);
        allBytes.setAll(0, _frameBuffer);
        allBytes.setAll(_frameBuffer.length, rawData);
      }

      int offset = 0;

      // Process complete 30ms frames
      while (allBytes.length - offset >= frameBytes) {
        final frame = Uint8List.view(
          allBytes.buffer,
          allBytes.offsetInBytes + offset,
          frameBytes,
        );
        offset += frameBytes;

        double rms = _calculateRms(frame);

        // Dynamic calibration: average the first 10 frames of ambient noise
        if (!_isCalibrated) {
          _calibrationSumRms += rms;
          _calibrationFramesCount++;
          if (_calibrationFramesCount >= 10) {
            double averageNoise = _calibrationSumRms / 10.0;
            _vadThresholdRms = averageNoise.clamp(10.0, 200.0) + 50.0;
            _isCalibrated = true;
          }
          continue;
        }

        bool isSpeechFrame = rms > _vadThresholdRms;

        if (isSpeechFrame) {
          if (!_isSpeaking) {
            FileLogger.instance.log('[AUDIO] 🎤 VAD ON');
          }
          _isSpeaking = true;
          _silenceFramesCount = 0;
        } else {
          _silenceFramesCount++;
        }

        if (_isSpeaking) {
          _speechChunks.add(Uint8List.fromList(frame));
          _speechLength += frame.length;

          // Trim oldest audio if buffer exceeds max size
          while (_speechLength > _config.maxBufferBytes) {
            //  FileLogger.instance.log('[AUDIO] ⚠️ BUFFER OVERFLOW - Dropping ${(_speechChunks.first.length / bytesPerSec * 1000).toInt()}ms audio');
            final firstChunk = _speechChunks.first;
            _speechChunks.removeAt(0);
            _speechLength -= firstChunk.length;
            _lastEmitBytes = math.max(0, _lastEmitBytes - firstChunk.length);
          }

          // Emit full accumulated buffer when enough new data has accumulated.
          // By passing the entire buffer (up to _config.maxBufferBytes), we ensure
          // no audio is skipped even if the engine drops intermediate chunks
          // due to being busy (e.g. thermal throttling).
          if (_speechLength - _lastEmitBytes >= _config.expandStepBytes) {
            if (_speechLength > 0) {
              Uint8List window = Uint8List(_speechLength);
              int innerOffset = 0;
              for (final chunk in _speechChunks) {
                window.setAll(innerOffset, chunk);
                innerOffset += chunk.length;
              }
              onChunk(window, false);
            }
            _lastEmitBytes = _speechLength;
          }

          // Finalize phrase after silence timeout
          bool silenceTimeout = _silenceFramesCount >= maxSilenceFrames;

          if (silenceTimeout) {
            FileLogger.instance.log('[AUDIO] 🔇 VAD OFF');
            if (_speechLength > 0) {
              Uint8List all = Uint8List(_speechLength);
              int innerOffset = 0;
              for (final chunk in _speechChunks) {
                all.setAll(innerOffset, chunk);
                innerOffset += chunk.length;
              }
              onChunk(all, true);
            }
            _speechChunks.clear();
            _speechLength = 0;
            _isSpeaking = false;
            _silenceFramesCount = 0;
            _lastEmitBytes = 0;
          }
        }
      }

      // Save remaining bytes that don't form a complete frame
      if (offset < allBytes.length) {
        _frameBuffer = Uint8List.fromList(
          Uint8List.view(allBytes.buffer, allBytes.offsetInBytes + offset),
        );
      } else {
        _frameBuffer = Uint8List(0);
      }
    });
  }

  /// Calculates Root Mean Square (RMS) of a PCM audio frame.
  /// Used for voice activity detection — higher RMS = louder audio.
  double _calculateRms(Uint8List frame) {
    double sum = 0;
    final byteData = frame.buffer.asByteData(
      frame.offsetInBytes,
      frame.lengthInBytes,
    );
    int sampleCount = frame.lengthInBytes ~/ 2;
    for (int i = 0; i < frame.lengthInBytes; i += 2) {
      int sample = byteData.getInt16(i, Endian.little);
      sum += sample * sample;
    }
    return math.sqrt(sum / sampleCount);
  }

  /// Stops recording and returns any remaining buffered audio.
  /// Resets all internal state for the next session.
  Future<Uint8List> stopAndGetAudio() async {
    await _subscription?.cancel();
    _subscription = null;

    await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;

    Uint8List result = Uint8List(0);
    if (_speechLength > 0) {
      result = Uint8List(_speechLength);
      int offset = 0;
      for (final chunk in _speechChunks) {
        result.setAll(offset, chunk);
        offset += chunk.length;
      }
    }

    _frameBuffer = Uint8List(0);
    _speechChunks.clear();
    _speechLength = 0;
    _isSpeaking = false;
    _silenceFramesCount = 0;
    _lastEmitBytes = 0;

    _isCalibrated = false;
    _calibrationFramesCount = 0;
    _calibrationSumRms = 0.0;
    _vadThresholdRms = 100.0;

    return result;
  }

  /// Clears the speech buffer without stopping the microphone.
  /// Called on ayah transitions to flush stale audio.
  void clearBuffer() {
    _speechChunks.clear();
    _speechLength = 0;
    _lastEmitBytes = 0;
  }

  /// Releases all resources.
  void dispose() {
    stopAndGetAudio();
  }
}
