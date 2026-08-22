// lib/tracking/word/phoneme_alignment_isolate_protocol.dart
import '../../data/quran_data.dart';
import '../tracker_config.dart';

export '../tracker_config.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ISOLATE PROTOCOL (Commands: Main UI ➔ Isolate | Events: Isolate ➔ Main UI)
// ═══════════════════════════════════════════════════════════════════════════════

/// Sealed base class for all commands sent from Main UI Thread ➔ Alignment Worker.
sealed class IsolateCommand {
  const IsolateCommand();

  Map<String, dynamic> toMap();

  static IsolateCommand fromMap(Map map) {
    final command = map['command'] as String?;
    switch (command) {
      case 'set_surah_reference':
        final rawRules = map['wordRules'] as List?;
        final List<List<WordTajweedRule>>? wordRules = rawRules?.map((l) {
          return (l as List)
              .map((r) => WordTajweedRule.fromMap(r as Map))
              .toList();
        }).toList();

        return SetSurahReferenceCommand(
          fullPhonemes: map['phonemes'] as String,
          boundaries: (map['boundaries'] as List).cast<int>(),
          surahNumber: map['surahNumber'] as int? ?? 0,
          isTajweed: map['isTajweed'] as bool? ?? false,
          forceClear: map['forceClear'] as bool? ?? false,
          startGlobalWord: map['startGlobalWord'] as int? ?? 0,
          wordRules: wordRules,
        );

      case 'sync_stream':
        return SyncStreamCommand(
          asrText:
              map['text'] as String? ??
              (map['tokens'] as List?)?.join('') ??
              '',
          timestamps: (map['timestamps'] as List?)?.cast<double>() ?? const [],
          isNewSegment: map['is_new_segment'] as bool? ?? false,
          ayahNumber: map['ayah_number'] as int? ?? 0,
        );

      case 'jump_to_word':
        return JumpToWordCommand(
          globalWordIndex: map['global_word_index'] as int? ?? 0,
        );

      case 'set_tajweed_mode':
        return SetTajweedModeCommand(
          isTajweed: map['is_tajweed'] as bool? ?? false,
        );

      case 'update_config':
        return UpdateTrackerConfigCommand(
          config: TrackerConfig(
            defaultMaxPathCost: (map['defaultMaxPathCost'] as num?)?.toDouble() ?? 0.30,
            shortWordPathCost: (map['shortWordPathCost'] as num?)?.toDouble() ?? 0.25,
            mediumWordPathCost: (map['mediumWordPathCost'] as num?)?.toDouble() ?? 0.28,
            maxSkipWords: map['maxSkipWords'] as int? ?? 2,
            acousticConfusionCost: (map['acousticConfusionCost'] as num?)?.toDouble() ?? 0.25,
            standardInsertionCost: (map['standardInsertionCost'] as num?)?.toDouble() ?? 0.75,
            standardDeletionCost: (map['standardDeletionCost'] as num?)?.toDouble() ?? 1.0,
            harakatDurationSeconds: (map['harakatDurationSeconds'] as num?)?.toDouble() ?? 0.250,
            maxTokenDurationAllowed: (map['maxTokenDurationAllowed'] as num?)?.toDouble() ?? 2.5,
            lookaheadDelay: (map['lookaheadDelay'] as num?)?.toDouble() ?? 0.320,
            hideExpectedAsrNoise: map['hideExpectedAsrNoise'] as bool? ?? true,
          ),
        );

      case 'stop':
        return const StopIsolateCommand();

      default:
        throw ArgumentError('Unknown IsolateCommand: $command');
    }
  }
}

class SetSurahReferenceCommand extends IsolateCommand {
  final String fullPhonemes;
  final List<int> boundaries;
  final int surahNumber;
  final bool isTajweed;
  final bool forceClear;
  final int startGlobalWord;
  final List<List<WordTajweedRule>>? wordRules;

  const SetSurahReferenceCommand({
    required this.fullPhonemes,
    required this.boundaries,
    required this.surahNumber,
    this.isTajweed = false,
    this.forceClear = false,
    this.startGlobalWord = 0,
    this.wordRules,
  });

  @override
  Map<String, dynamic> toMap() => {
    'command': 'set_surah_reference',
    'phonemes': fullPhonemes,
    'boundaries': boundaries,
    'surahNumber': surahNumber,
    'isTajweed': isTajweed,
    'forceClear': forceClear,
    'startGlobalWord': startGlobalWord,
    'wordRules': wordRules
        ?.map((list) => list.map((r) => r.toMap()).toList())
        .toList(),
  };
}

class SyncStreamCommand extends IsolateCommand {
  final String asrText;
  final List<double> timestamps;
  final bool isNewSegment;
  final int ayahNumber;

  const SyncStreamCommand({
    required this.asrText,
    required this.timestamps,
    this.isNewSegment = false,
    this.ayahNumber = 0,
  });

  @override
  Map<String, dynamic> toMap() => {
    'command': 'sync_stream',
    'text': asrText,
    'timestamps': timestamps,
    'is_new_segment': isNewSegment,
    'ayah_number': ayahNumber,
  };
}

class JumpToWordCommand extends IsolateCommand {
  final int globalWordIndex;
  const JumpToWordCommand({required this.globalWordIndex});

  @override
  Map<String, dynamic> toMap() => {
    'command': 'jump_to_word',
    'global_word_index': globalWordIndex,
  };
}

class SetTajweedModeCommand extends IsolateCommand {
  final bool isTajweed;
  const SetTajweedModeCommand({required this.isTajweed});

  @override
  Map<String, dynamic> toMap() => {
    'command': 'set_tajweed_mode',
    'is_tajweed': isTajweed,
  };
}

class UpdateTrackerConfigCommand extends IsolateCommand {
  final TrackerConfig config;
  const UpdateTrackerConfigCommand({required this.config});

  @override
  Map<String, dynamic> toMap() => {
    'command': 'update_config',
    'defaultMaxPathCost': config.defaultMaxPathCost,
    'shortWordPathCost': config.shortWordPathCost,
    'mediumWordPathCost': config.mediumWordPathCost,
    'maxSkipWords': config.maxSkipWords,
    'acousticConfusionCost': config.acousticConfusionCost,
    'standardInsertionCost': config.standardInsertionCost,
    'standardDeletionCost': config.standardDeletionCost,
    'harakatDurationSeconds': config.harakatDurationSeconds,
    'maxTokenDurationAllowed': config.maxTokenDurationAllowed,
    'lookaheadDelay': config.lookaheadDelay,
    'hideExpectedAsrNoise': config.hideExpectedAsrNoise,
  };
}

class StopIsolateCommand extends IsolateCommand {
  const StopIsolateCommand();

  @override
  Map<String, dynamic> toMap() => {'command': 'stop'};
}

/// Sealed base class for all events emitted from Alignment Worker ➔ Main UI Thread.
sealed class IsolateEvent {
  const IsolateEvent();

  Map<String, dynamic> toMap();

  static IsolateEvent fromMap(Map map) {
    final event = map['event'] as String?;
    switch (event) {
      case 'highlight':
        return WordMatchedEvent(
          wordId: map['word_id'] as int,
          score: (map['score'] as num?)?.toDouble() ?? 0.0,
          cleanAsr: map['clean_asr'] as String? ?? '',
          tajweedErrors: (map['tajweed_errors'] as List?)
              ?.map((e) => (e as Map).cast<String, dynamic>())
              .toList(),
          isRed: map['is_red'] as bool? ?? false,
          isNeutral: map['is_neutral'] as bool? ?? false,
        );

      case 'debug':
        return DebugLogEvent(
          message: map['message'] as String? ?? '',
          asrBuffer: map['asr_buffer'] as String? ?? '',
        );

      default:
        throw ArgumentError('Unknown IsolateEvent: $event');
    }
  }
}

class WordMatchedEvent extends IsolateEvent {
  final int wordId;
  final double score;
  final String cleanAsr;
  final List<Map<String, dynamic>>? tajweedErrors;
  final bool isRed;
  final bool isNeutral;

  const WordMatchedEvent({
    required this.wordId,
    this.score = 0.0,
    required this.cleanAsr,
    this.tajweedErrors,
    this.isRed = false,
    this.isNeutral = false,
  });

  @override
  Map<String, dynamic> toMap() => {
    'event': 'highlight',
    'word_id': wordId,
    'score': score,
    'clean_asr': cleanAsr,
    'tajweed_errors': tajweedErrors,
    'is_red': isRed,
    'is_neutral': isNeutral,
  };
}

class DebugLogEvent extends IsolateEvent {
  final String message;
  final String asrBuffer;

  const DebugLogEvent({required this.message, required this.asrBuffer});

  @override
  Map<String, dynamic> toMap() => {
    'event': 'debug',
    'message': message,
    'asr_buffer': asrBuffer,
  };
}
