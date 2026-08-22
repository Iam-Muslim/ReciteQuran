// lib/audio/audio_processor_io.dart
// لا اله الا الله

import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:audio_session/audio_session.dart';

class AudioProcessor {
  // ── Audio format constants ─────────────────────────────────────────────────
  /// The sample rate that the ASR model and VAD expect.

  static const int recordSampleRate = 16000;
  static const int numChannels = 1;
  static const int bytesPerSample = 2; // 16-bit PCM

  static const int chunkMs = 480;

  static const int recordChunkBytes =
      (recordSampleRate * numChannels * bytesPerSample * chunkMs) ~/ 1000;

  Uint8List _frameBuffer = Uint8List(0);

  // ── No VAD ─────────────────────────────────────────────────────────────
  // We stream all audio directly to Sherpa ONNX. This completely eliminates
  // the problem of dropped phonemes and calibration issues between different
  // devices' microphone sensitivities.

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;

  Future<void> start({
    required void Function(Float32List chunk, bool isFinal) onChunk,
  }) async {
    await stop();

    // ── Configure Audio Session for Raw Microphone Feed ──
    // This tells the OS (especially iOS/Mac) to minimize aggressive background noise
    // cancellation which might otherwise destroy breathy Arabic phonemes like "هـ".
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.measurement,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication, // Used for audio focus
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: true,
      ),
    );

    _recorder = AudioRecorder();

    final recordStream = await _recorder!.startStream(
      // We explicitly disable ALL hardware processing to ensure the "ه"
      // breathy sound isn't filtered out as background noise by Android.
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: recordSampleRate, // 16000
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
      // Process in exact 480ms blocks
      while (allBytes.length - offset >= recordChunkBytes) {
        final byteView = Uint8List.view(
          allBytes.buffer,
          allBytes.offsetInBytes + offset,
          recordChunkBytes,
        );
        offset += recordChunkBytes;

        final int16samples = Int16List.view(
          byteView.buffer,
          byteView.offsetInBytes,
          recordChunkBytes ~/ bytesPerSample,
        );

        final float32Samples = Float32List(int16samples.length);

        // ── Direct Linear Conversion ──
        // Exactly matches the Python training pipeline: `wav.astype(np.float32) / 32768.0`
        for (int i = 0; i < int16samples.length; i++) {
          float32Samples[i] = int16samples[i] / 32768.0;
        }

        // Stream all audio directly to Sherpa ASR!
        onChunk(float32Samples, false);
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
    // Left for compatibility with Orchestrator
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;

    await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;

    _frameBuffer = Uint8List(0);
  }
}
