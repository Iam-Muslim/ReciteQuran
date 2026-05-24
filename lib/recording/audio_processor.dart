import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:record/record.dart';

class AudioProcessor {
  static const int sampleRate = 16000;
  static const int bytesPerSample = 2; // 16-bit PCM
  static const int bytesPerSec =
      sampleRate * bytesPerSample; // 32,000 bytes/sec

  // ── VAD Parameters ────────────────────────────────────────────────────────
  static const int frameMs = 30; // Analyze audio in tiny 30ms slices
  static const int frameBytes =
      (sampleRate * bytesPerSample * frameMs) ~/ 1000; // 960 bytes

  // Minimum RMS volume threshold to be considered "active speech"
  double _vadThresholdRms = 100.0;

  // Dynamic Calibration state
  bool _isCalibrated = false;
  int _calibrationFramesCount = 0;
  double _calibrationSumRms = 0.0;

  static const int maxSilenceMs = 800;
  static const int maxSilenceFrames = maxSilenceMs ~/ frameMs; // ~26 frames

  // Emit a dynamic snapshot of the phrase every 250ms for responsive real-time UI
  // (was 200ms — reduced to cut inference frequency by 20%, lowering CPU heat)
  static const int expandStepBytes = (bytesPerSec * 250) ~/ 1000;

  static final int maxBufferBytes = (bytesPerSec * 2.5).toInt();
  // Non-final chunks use a sliding window to prevent CTC hallucination
  static const int slidingWindowBytes = bytesPerSec * 3 ~/ 2; // 1.5 seconds

  final List<int> _frameBuffer = [];
  final List<int> _speechBuffer = [];

  int _silenceFramesCount = 0;
  bool _isSpeaking = false;
  int _lastEmitBytes = 0;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;

  Future<void> start({
    required void Function(Uint8List chunk, bool isFinal) onChunk,
  }) async {
    await stopAndGetAudio();

    _recorder = AudioRecorder();

    if (!await _recorder!.hasPermission()) {
      throw Exception("Microphone recording permission denied");
    }

    // Configure for raw 16kHz Mono 16-bit PCM with built-in hardware filters
    final recordStream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: true, // Fixes low volume
        echoCancel: true, // Removes speaker bleed
        noiseSuppress: true, // Cleans background hiss
      ),
    );

    _subscription = recordStream.listen((Uint8List rawData) {
      _frameBuffer.addAll(rawData);

      while (_frameBuffer.length >= frameBytes) {
        final frame = Uint8List.fromList(_frameBuffer.sublist(0, frameBytes));
        _frameBuffer.removeRange(0, frameBytes);

        double rms = _calculateRms(frame);

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
          _isSpeaking = true;
          _silenceFramesCount = 0;
        } else {
          _silenceFramesCount++;
        }

        if (_isSpeaking) {
          _speechBuffer.addAll(frame);

          if (_speechBuffer.length > maxBufferBytes) {
            int overflow = _speechBuffer.length - maxBufferBytes;
            _speechBuffer.removeRange(0, overflow);
            _lastEmitBytes = math.max(0, _lastEmitBytes - overflow);
          }

          if (_speechBuffer.length - _lastEmitBytes >= expandStepBytes) {
            // Send only recent audio (sliding window) instead of the
            // entire growing buffer. This caps inference time and prevents
            // the CTC decoder from hallucinating words from trailing silence.
            int windowStart = math.max(
              0,
              _speechBuffer.length - slidingWindowBytes,
            );
            onChunk(
              Uint8List.fromList(_speechBuffer.sublist(windowStart)),
              false,
            );
            _lastEmitBytes = _speechBuffer.length;
          }

          bool silenceTimeout = _silenceFramesCount >= maxSilenceFrames;

          if (silenceTimeout) {
            if (_speechBuffer.isNotEmpty) {
              onChunk(Uint8List.fromList(_speechBuffer), true);
            }
            _speechBuffer.clear();
            _isSpeaking = false;
            _silenceFramesCount = 0;
            _lastEmitBytes = 0;
          }
        }
      }
    });
  }

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

  Future<Uint8List> stopAndGetAudio() async {
    await _subscription?.cancel();
    _subscription = null;

    await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;

    Uint8List result = Uint8List(0);
    if (_speechBuffer.isNotEmpty) {
      result = Uint8List.fromList(_speechBuffer);
    }

    _frameBuffer.clear();
    _speechBuffer.clear();
    _isSpeaking = false;
    _silenceFramesCount = 0;
    _lastEmitBytes = 0;

    _isCalibrated = false;
    _calibrationFramesCount = 0;
    _calibrationSumRms = 0.0;
    _vadThresholdRms = 100.0;

    return result;
  }

  void clearBuffer() {
    _speechBuffer.clear();
    _lastEmitBytes = 0;
  }

  void dispose() {
    stopAndGetAudio();
  }
}
