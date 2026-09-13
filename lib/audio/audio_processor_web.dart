// lib/audio/audio_processor_web.dart
import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:record/record.dart';

class AudioProcessor {
  static const int recordSampleRate = 16000;
  static const int numChannels = 1;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  bool _isRecording = false;

  /// Always optimistic on web.
  ///
  /// record_web's hasPermission() queries the Permissions API for
  /// 'microphone' first and only falls back to requesting getUserMedia
  /// directly if that query says "not yet granted". Safari/WebKit doesn't
  /// reliably support querying microphone permission that way — the query
  /// itself can throw — which meant this returned false and start() below
  /// bailed before ever prompting the user at all. startStream() below
  /// calls getUserMedia on its own regardless of what this method says, so
  /// the real prompt-or-deny decision happens there, uniformly across
  /// browsers, instead of behind this unreliable pre-check.
  Future<bool> hasPermission() async => true;

  Future<void> start({
    required void Function(Float32List chunk, bool isFinal) onChunk,
  }) async {
    await stop();
    _isRecording = true;
    _recorder = AudioRecorder();

    try {
      final stream = await _recorder!.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: recordSampleRate,
          numChannels: numChannels,
        ),
      );

      _subscription = stream.listen((Uint8List chunk) {
        if (!_isRecording) return;
        final float32 = _pcm16ToFloat32(chunk);
        onChunk(float32, false);
      });
    } catch (e, stack) {
      _isRecording = false;
      log('AudioProcessor start error: $e\n$stack');
    }
  }

  static Float32List _pcm16ToFloat32(Uint8List pcm16) {
    final sampleCount = pcm16.length ~/ 2;
    final out = Float32List(sampleCount);
    final byteData = ByteData.sublistView(pcm16);
    for (int i = 0; i < sampleCount; i++) {
      final sample16 = byteData.getInt16(i * 2, Endian.little);
      out[i] = sample16 / 32768.0;
    }
    return out;
  }

  void clearBuffer() {
    // Left for compatibility with Orchestrator (matches audio_processor_io.dart)
  }

  Future<void> stop() async {
    _isRecording = false;
    await _subscription?.cancel();
    _subscription = null;
    try {
      if (_recorder != null && await _recorder!.isRecording()) {
        await _recorder!.stop();
      }
    } catch (_) {}
    await _recorder?.dispose();
    _recorder = null;
  }
}
