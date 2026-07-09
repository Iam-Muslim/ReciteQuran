import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';

@JS('startOfficialSherpa')
external void _startOfficialSherpa();

@JS('stopOfficialSherpa')
external void _stopOfficialSherpa();

@JS('resetOfficialSherpaBuffer')
external void _resetOfficialSherpaBuffer();

class AudioProcessor {
  bool _isRecording = false;

  Future<void> start({
    required void Function(Uint8List chunk, bool isFinal) onChunk,
    bool Function()? isAtAyahBoundary,
  }) async {
    try {
      await stopAndGetAudio();
      _isRecording = true;
      _startOfficialSherpa();
    } catch (e, stack) {
      print("AudioProcessor start error: $e\n$stack");
    }
  }

  void clearBuffer() {
    _resetOfficialSherpaBuffer();
  }

  Future<void> stopAndGetAudio() async {
    try {
      if (_isRecording) {
        _isRecording = false;
        _stopOfficialSherpa();
      }
    } catch (e) {
      print("AudioProcessor stop error: $e");
    }
  }
}
