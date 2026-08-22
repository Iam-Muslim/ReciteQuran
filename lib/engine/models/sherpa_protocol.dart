import 'dart:isolate';

/// Sealed Dart 3 command protocol sent from the main UI thread to the Sherpa ASR isolate.
sealed class SherpaCommand {
  const SherpaCommand();
}

/// Initializes the ONNX Zipformer CTC streaming engine with model and token asset paths.
final class SherpaInitCommand extends SherpaCommand {
  final String modelPath;
  final String tokensPath;

  const SherpaInitCommand({
    required this.modelPath,
    required this.tokensPath,
  });
}

/// Transcribes a raw 16kHz float32 audio chunk.
final class SherpaRecognizeCommand extends SherpaCommand {
  final TransferableTypedData chunk;
  final bool isFinal;
  final int startTime;

  const SherpaRecognizeCommand({
    required this.chunk,
    required this.isFinal,
    required this.startTime,
  });
}

/// Hard resets the streaming buffer and primes attention cache with 300ms pre-roll silence.
final class SherpaResetCommand extends SherpaCommand {
  const SherpaResetCommand();
}

/// Flushes the current utterance across an Ayah boundary without destroying in-flight speech.
final class SherpaFlushCommand extends SherpaCommand {
  const SherpaFlushCommand();
}

/// Destroys the recognizer and frees native C++ memory.
final class SherpaDestroyCommand extends SherpaCommand {
  const SherpaDestroyCommand();
}

// ─────────────────────────────────────────────────────────────────────────────
// Sealed Events (Isolate ➔ Main UI Thread)
// ─────────────────────────────────────────────────────────────────────────────

/// Sealed Dart 3 event protocol emitted by the Sherpa ASR isolate back to the main thread.
sealed class SherpaEvent {
  const SherpaEvent();
}

/// Emitted when the ONNX neural network and cache tensors are successfully initialized.
final class SherpaInitSuccessEvent extends SherpaEvent {
  const SherpaInitSuccessEvent();
}

/// Emitted if asset extraction or ONNX runtime initialization fails.
final class SherpaInitErrorEvent extends SherpaEvent {
  final String error;
  const SherpaInitErrorEvent(this.error);
}

/// Streaming transcription result containing decoded text, tokens, and timestamps.
final class SherpaTranscriptionEvent extends SherpaEvent {
  final String text;
  final List<String> tokens;
  final List<double> timestamps;
  final bool isFinal;
  final int startTime;
  final int streamEpoch;

  const SherpaTranscriptionEvent({
    required this.text,
    required this.tokens,
    required this.timestamps,
    required this.isFinal,
    required this.startTime,
    required this.streamEpoch,
  });
}
