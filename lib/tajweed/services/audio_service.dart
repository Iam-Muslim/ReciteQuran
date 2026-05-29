import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _recordingPath;

  Future<void> startRecording() async {
    try {
      await initAudioSession(); // Configure routing to loudspeaker for playback

      if (await _audioRecorder.hasPermission()) {
        final Directory tempDir = await getTemporaryDirectory();
        final String filePath = '${tempDir.path}/recitation.wav';

        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          debugPrint(
            '🗑️ [AudioService] Deleted previous recording: $filePath',
          );
        }

        _recordingPath = filePath;

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            bitRate: 128000,
            sampleRate: 16000, // Strictly required by Wav2Vec2
            numChannels: 1, // Strictly required mono
            autoGain: true,
            echoCancel: false,
            noiseSuppress: true,
          ),
          path: filePath,
        );
        debugPrint('🎙️ [AudioService] Started recording to $filePath');
      } else {
        debugPrint('❌ [AudioService] Permission to record audio denied');
      }
    } catch (e) {
      debugPrint('❌ [AudioService] Error starting recording: $e');
    }
  }

  Future<String?> stopRecording() async {
    try {
      final String? path = await _audioRecorder.stop();
      debugPrint('⏹️ [AudioService] Stopped recording. Path: $path');
      return path ?? _recordingPath;
    } catch (e) {
      debugPrint('❌ [AudioService] Error stopping recording: $e');
      return null;
    }
  }

  /// Configures the iOS audio session routing to force playback through the main loudspeaker.
  /// Matches AVAudioSessionCategoryOptions.defaultToSpeaker from Swift AudioRecorder.
  Future<void> initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
      debugPrint(
        '🔊 [AudioService] Audio session configured for loudspeaker playback',
      );
    } catch (e) {
      debugPrint('❌ [AudioService] Error configuring audio session: $e');
    }
  }

  Future<void> dispose() async {
    await _audioRecorder.dispose();
  }
}
