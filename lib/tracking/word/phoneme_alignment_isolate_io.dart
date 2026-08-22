// lib/tracking/word/phoneme_alignment_isolate_io.dart
import 'dart:async';
import 'dart:isolate';

import '../../data/quran_data.dart';
import '../../utils/debug_logger.dart';
import 'dictation_sequencer.dart';
import 'phoneme_alignment_isolate_protocol.dart';

export 'phoneme_alignment_isolate_protocol.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// BACKGROUND ISOLATE WORKER ENTRYPOINT
// ═══════════════════════════════════════════════════════════════════════════════

void alignmentWorkerEntrypoint(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  final sequencer = DictationSequencer(mainSendPort.send);

  commandPort.listen((rawMessage) {
    if (rawMessage is! Map) return;

    final IsolateCommand command;
    try {
      command = IsolateCommand.fromMap(rawMessage);
    } catch (_) {
      return;
    }

    try {
      switch (command) {
        case SetSurahReferenceCommand():
          sequencer.setSurahReference(command);

        case SyncStreamCommand():
          sequencer.syncStream(command);

        case JumpToWordCommand():
          sequencer.jumpToWord(command);

        case SetTajweedModeCommand(:final isTajweed):
          sequencer.isTajweed = isTajweed;

        case UpdateTrackerConfigCommand(:final config):
          sequencer.updateConfig(config);

        case StopIsolateCommand():
          Isolate.current.kill();
      }
    } catch (e, stack) {
      mainSendPort.send(
        DebugLogEvent(
          message: '⚠️ [ISOLATE ERROR] Handled exception: $e\n$stack',
          asrBuffer: sequencer.currentSegmentAsrText,
        ).toMap(),
      );
    }
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// UI-SIDE ISOLATE MANAGER (Native / IO)
// ═══════════════════════════════════════════════════════════════════════════════

/// Main UI thread manager for the background alignment isolate.
class PhonemeAlignmentIsolate {
  SendPort? _sendPort;
  Isolate? _isolate;

  final StreamController<WordMatchedEvent> _wordStreamController =
      StreamController<WordMatchedEvent>.broadcast();

  Stream<WordMatchedEvent> get wordStream => _wordStreamController.stream;

  Future<void> start() async {
    final receivePort = ReceivePort();
    final completer = Completer<void>();

    _isolate = await Isolate.spawn(
      alignmentWorkerEntrypoint,
      receivePort.sendPort,
    );

    receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!completer.isCompleted) completer.complete();
      } else if (message is Map) {
        try {
          final event = IsolateEvent.fromMap(message);
          switch (event) {
            case WordMatchedEvent():
              _wordStreamController.add(event);
            case DebugLogEvent(:final message, :final asrBuffer):
              DebugLogger.updateAsrBuffer(asrBuffer);
              DebugLogger.log('DP', message);
          }
        } catch (_) {
          // Ignore malformed event
        }
      }
    });

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        DebugLogger.log(
          'PhonemeAlignmentIsolate',
          '⚠️ Alignment isolate failed to handshake within 10s — isolate likely OOM-killed. Proceeding without alignment.',
        );
      },
    );
  }

  void send(IsolateCommand command) {
    _sendPort?.send(command.toMap());
  }

  void setSurahReference(
    String expectedPhonemes,
    List<int> wordBoundaries, {
    bool isTajweed = false,
    bool forceClear = false,
    int startGlobalWord = 0,
    int surahNumber = 0,
    List<List<WordTajweedRule>>? wordRules,
  }) {
    send(
      SetSurahReferenceCommand(
        fullPhonemes: expectedPhonemes,
        boundaries: wordBoundaries,
        surahNumber: surahNumber,
        isTajweed: isTajweed,
        forceClear: forceClear,
        startGlobalWord: startGlobalWord,
        wordRules: wordRules,
      ),
    );
  }

  void jumpToWord(int globalWordIndex) {
    send(JumpToWordCommand(globalWordIndex: globalWordIndex));
  }

  void syncStream(
    String segmentText,
    List<double>? segmentTimestamps, [
    bool isNewSegment = false,
    int? ayahNumber,
  ]) {
    send(
      SyncStreamCommand(
        asrText: segmentText,
        timestamps: segmentTimestamps ?? const [],
        isNewSegment: isNewSegment,
        ayahNumber: ayahNumber ?? 0,
      ),
    );
  }

  void setTajweedMode(bool isTajweed) {
    send(SetTajweedModeCommand(isTajweed: isTajweed));
  }

  void updateConfig(TrackerConfig config) {
    send(UpdateTrackerConfigCommand(config: config));
  }

  void stop() {
    send(const StopIsolateCommand());
    _wordStreamController.close();
    _isolate?.kill();
    _isolate = null;
    _sendPort = null;
  }
}
