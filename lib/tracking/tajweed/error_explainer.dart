// lib/tracking/tajweed/error_explainer.dart
// ═══════════════════════════════════════════════════════════════════════════════
// ERROR EXPLAINER MODULE (DIRECT V2 SCHEMA ENGINE - ZERO HEURISTICS)
//
// Evaluates reciter phoneme alignment and acoustic holding durations directly:
//   Phase 1: Base Consonant & Deletion/Insertion Verification (`ErrorCategory.normal`).
//   Phase 2: Harakat & Tashkeel Modification Verification (`ErrorCategory.tashkeel`).
//   Phase 3: Direct Tajweed Duration Evaluation (`ErrorCategory.tajweed`):
//     - Madd (1-7): 2, 4, 6 Harakat evaluated against acoustic timestamps.
//     - Mushaddad Ghunnah (10): 2 Harakat evaluated on Mushaddad Noon & Meem.
//     - Shaddah (9): Consonant closure & holding duration (~1.5 Harakat).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:math';

import '../../data/quran_data.dart';
import '../../utils/debug_logger.dart';
import '../word/dictation_matcher.dart';
import 'tajweed_rules.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1: DATA MODELS & ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// Broad classification of reciter errors used by UI color highlighting and statistics.
enum ErrorCategory {
  /// Acoustic duration or Shaddah doubling mismatch (`Yellow highlight`).
  tajweed,

  /// Base letter replacement, total deletion, or insertion (`Red highlight`).
  normal,

  /// Same base consonant but incorrect diacritics/vowels (`Yellow highlight`).
  tashkeel,
}

/// Specific speech modification operation detected during phoneme alignment.
enum SpeechErrorType {
  /// Reciter added an extra phoneme or syllable not present in reference.
  insert,

  /// Reciter skipped or swallowed a required phoneme or syllable.
  delete,

  /// Reciter substituted a phoneme with a different sound or diacritic.
  replace,
}

/// Immutable diagnostic record detailing a detected recitation mismatch.
class ReciterError {
  final ErrorCategory errorType;
  final SpeechErrorType speechErrorType;
  final TajweedDurationStatus? durationStatus;
  final String expectedPh;
  final String predictedPh;
  final TajweedRule? expectedRule;
  final TajweedRule? predictedRule;
  final double? expectedDuration;
  final double? actualDuration;

  ReciterError({
    required this.errorType,
    required this.speechErrorType,
    this.durationStatus,
    required this.expectedPh,
    required this.predictedPh,
    this.expectedRule,
    this.predictedRule,
    this.expectedDuration,
    this.actualDuration,
  });

  /// Formatted Arabic explanation for display in UI dialogs / bottom sheets.
  String get messageAr {
    if (errorType == ErrorCategory.tajweed) {
      final ruleName = expectedRule?.name.ar ?? 'حكم التجويد';
      if (durationStatus == TajweedDurationStatus.underheld) {
        if (actualDuration != null && expectedDuration != null) {
          return 'نقص في $ruleName: قمت بمد الصوت ${actualDuration!.toStringAsFixed(2)}ث، والمطلوب ${expectedDuration!.toStringAsFixed(2)}ث';
        }
        return 'نقص في $ruleName: تم حبس الصوت بأقل من الزمن المطلوب';
      } else if (durationStatus == TajweedDurationStatus.overheld) {
        if (actualDuration != null && expectedDuration != null) {
          return 'زيادة في $ruleName: قمت بمد الصوت ${actualDuration!.toStringAsFixed(2)}ث، المسموح ${expectedDuration!.toStringAsFixed(2)}ث';
        }
        return 'زيادة في $ruleName: تم مد الصوت ';
      }
      return 'خطأ في تطبيق $ruleName';
    } else if (errorType == ErrorCategory.tashkeel) {
      return 'خطأ في التشكيل: المتوقع ($expectedPh) ونُطِق ($predictedPh)';
    } else {
      if (speechErrorType == SpeechErrorType.delete) {
        return 'إسقاط حرف: لم يتم نطق ($expectedPh)';
      }
      return 'خطأ في نطق الحرف: المتوقع ($expectedPh) ونُطِق ($predictedPh)';
    }
  }

  /// Formatted English explanation for display in UI dialogs / bottom sheets.
  String get messageEn {
    if (errorType == ErrorCategory.tajweed) {
      final ruleName = expectedRule?.name.en ?? 'Tajweed Rule';
      if (durationStatus == TajweedDurationStatus.underheld) {
        if (actualDuration != null && expectedDuration != null) {
          return 'Underheld $ruleName: held for ${actualDuration!.toStringAsFixed(2)}s, target is ${expectedDuration!.toStringAsFixed(2)}s';
        }
        return 'Underheld $ruleName: held for less than required duration';
      } else if (durationStatus == TajweedDurationStatus.overheld) {
        if (actualDuration != null && expectedDuration != null) {
          return 'Overheld $ruleName: held for ${actualDuration!.toStringAsFixed(2)}s, exceeding target';
        }
        return 'Overheld $ruleName: held longer ';
      }
      return 'Mistake in $ruleName';
    } else if (errorType == ErrorCategory.tashkeel) {
      return 'Diacritic error: expected "$expectedPh", heard "$predictedPh"';
    } else {
      if (speechErrorType == SpeechErrorType.delete) {
        return 'Omitted letter: missed "$expectedPh"';
      }
      return 'Letter mismatch: expected "$expectedPh", heard "$predictedPh"';
    }
  }

  /// Actionable advice in Arabic.
  String get adviceAr {
    if (errorType == ErrorCategory.tajweed) {
      if (expectedRule is ShaddahRule) {
        return 'اضغط على مخرج الحرف المشدد';
      }
      if (expectedRule is MushaddadGhunnahRule) {
        return 'أعطِ الغنة زمن حركتين كاملتين ';
      }
      if (durationStatus == TajweedDurationStatus.underheld) {
        final beats = expectedRule?.goldenLen ?? 2;
        return 'أطل زمن مد الصوت بمقدار $beats ${beats <= 2 ? 'حركتين' : 'حركات'}';
      }
      return 'لا تبالغ في مد الصوت';
    } else if (errorType == ErrorCategory.tashkeel) {
      return 'احرص على ضبط الحركة الصحيحة (فتحة، ضمة، كسرة)';
    }
    return 'انطق الحرف بوضوح من مخرجه الصحيح';
  }

  /// Actionable advice in English.
  String get adviceEn {
    if (errorType == ErrorCategory.tajweed) {
      if (expectedRule is ShaddahRule) {
        return 'Hold the consonant.';
      }
      if (expectedRule is MushaddadGhunnahRule) {
        return 'Give the Ghunnah a full 2-beat nasal resonance.';
      }
      if (durationStatus == TajweedDurationStatus.underheld) {
        return 'Hold the vowel elongation for the full ${expectedRule?.goldenLen ?? 2} beats.';
      }
      return 'Avoid over-extending the vowel past the allowed length.';
    } else if (errorType == ErrorCategory.tashkeel) {
      return 'Pay attention to the correct vowel mark (Fatha, Damma, Kasra).';
    }
    return 'Articulate the letter clearly';
  }

  @override
  String toString() {
    return 'ReciterError(type: $errorType, action: $speechErrorType, status: $durationStatus, expected: "$expectedPh", predicted: "$predictedPh", expectedRule: ${expectedRule?.name.en}, expDur: $expectedDuration, actDur: $actualDuration)';
  }

  Map<String, dynamic> toMap() {
    return {
      'errorType': errorType.name,
      'errorTypeIndex': errorType.index,
      'speechErrorType': speechErrorType.name,
      'speechErrorTypeIndex': speechErrorType.index,
      'durationStatus': durationStatus?.name,
      'durationStatusIndex': durationStatus?.index,
      'expectedPh': expectedPh,
      'predictedPh': predictedPh,
      'expectedRule': _ruleToMap(expectedRule),
      'predictedRule': _ruleToMap(predictedRule),
      'expectedDuration': expectedDuration,
      'actualDuration': actualDuration,
      'messageAr': messageAr,
      'messageEn': messageEn,
      'adviceAr': adviceAr,
      'adviceEn': adviceEn,
    };
  }

  static ReciterError fromMap(Map<String, dynamic> map) {
    final rawErrorType = map['errorType'] ?? map['errorTypeIndex'];
    final ErrorCategory errorType = (rawErrorType is int)
        ? ErrorCategory.values[rawErrorType]
        : (rawErrorType is String
            ? ErrorCategory.values.firstWhere(
                (e) => e.name == rawErrorType,
                orElse: () => ErrorCategory.normal,
              )
            : ErrorCategory.normal);

    final rawSpeech = map['speechErrorType'] ?? map['speechErrorTypeIndex'];
    final SpeechErrorType speechErrorType = (rawSpeech is int)
        ? SpeechErrorType.values[rawSpeech]
        : (rawSpeech is String
            ? SpeechErrorType.values.firstWhere(
                (e) => e.name == rawSpeech,
                orElse: () => SpeechErrorType.replace,
              )
            : SpeechErrorType.replace);

    final rawStatus = map['durationStatus'] ?? map['durationStatusIndex'];
    final TajweedDurationStatus? durationStatus = (rawStatus is int)
        ? TajweedDurationStatus.values[rawStatus]
        : (rawStatus is String
            ? TajweedDurationStatus.values.firstWhere(
                (e) => e.name == rawStatus,
                orElse: () => TajweedDurationStatus.valid,
              )
            : null);

    return ReciterError(
      errorType: errorType,
      speechErrorType: speechErrorType,
      durationStatus: durationStatus,
      expectedPh: map['expectedPh'] as String? ?? '',
      predictedPh: map['predictedPh'] as String? ?? '',
      expectedRule: _ruleFromMap(map['expectedRule'] as Map<String, dynamic>?),
      predictedRule:
          _ruleFromMap(map['predictedRule'] as Map<String, dynamic>?),
      expectedDuration: (map['expectedDuration'] as num?)?.toDouble(),
      actualDuration: (map['actualDuration'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic>? _ruleToMap(TajweedRule? rule) {
    if (rule == null) return null;
    return {
      'type': rule.runtimeType.toString(),
      'nameAr': rule.name.ar,
      'nameEn': rule.name.en,
      'goldenLen': rule.goldenLen,
    };
  }

  static TajweedRule? _ruleFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final String type = map['type'] as String? ?? '';
    final String nameAr = map['nameAr'] as String? ?? '';
    final String nameEn = map['nameEn'] as String? ?? '';
    final num goldenLen = (map['goldenLen'] as num?) ?? 2;

    if (type == 'LazemMaddRule') return const LazemMaddRule();
    if (type == 'LeenMaddRule') return LeenMaddRule(goldenLen.toInt());
    if (type == 'AaredMaddRule') return AaredMaddRule(goldenLen.toInt());
    if (type == 'MonfaselMaddRule') return MonfaselMaddRule(goldenLen.toInt());
    if (type == 'MottaselMaddRule') return MottaselMaddRule(goldenLen.toInt());
    if (type == 'MottaselMaddPauseRule')
      return MottaselMaddPauseRule(goldenLen.toInt());
    if (type == 'NormalMaddRule') return const NormalMaddRule();
    if (type == 'MushaddadGhunnahRule') {
      return MushaddadGhunnahRule.withNames(nameAr: nameAr, nameEn: nameEn);
    }
    if (type == 'ShaddahRule') return const ShaddahRule();

    return MaddRule(
      name: LangName(ar: nameAr, en: nameEn),
      goldenLen: goldenLen,
    );
  }
}

/// Represents the alignment opcode between a single reference phoneme group and predicted phoneme group.
class PhonemeGroupAlignment {
  final String opType; // 'match', 'replace', 'delete', 'insert'
  final int refIdx;
  final int predIdx;

  PhonemeGroupAlignment({
    required this.opType,
    required this.refIdx,
    required this.predIdx,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2: REFERENCE PHONETIC SPAN MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class _PhoneticSpan {
  final int refStart; // absolute index in fullPhonemes
  final int refEnd; // absolute index in fullPhonemes
  final String refText;
  final String baseChar;
  final bool isMadd;
  final bool isShaddah;
  final bool isGhunnah;
  final WordTajweedRule? matchedWordRule;

  _PhoneticSpan({
    required this.refStart,
    required this.refEnd,
    required this.refText,
    required this.baseChar,
    required this.isMadd,
    required this.isShaddah,
    required this.isGhunnah,
    this.matchedWordRule,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3: ERROR EXPLAINER ENGINE (SPAN-LEVEL TOKEN & DURATION EVALUATION)
// ═══════════════════════════════════════════════════════════════════════════════

class ErrorExplainer {
  /// Evaluates pre-aligned phoneme traces for a specific committed word window.
  static Map<int, List<ReciterError>> evaluatePreAlignedWords({
    required List<PhonemeGroupAlignment> alignments,
    required String fullPhonemes,
    required List<int> wordBoundaries,
    required String currentAsrText,
    required List<double> trackingTimestamps,
    required int bestAsrStartIdx,
    required int targetCharCursor,
    required int startWordId,
    required int nextWordId,
    required int totalAyahWords,
    List<WordTajweedRule> expectedWordRules = const [],
    TrackerConfig config = const TrackerConfig(),
  }) {
    final Map<int, List<ReciterError>> errorsByWord = {};

    for (int w = startWordId; w < nextWordId; w++) {
      if (w < 0 || w >= wordBoundaries.length - 1) continue;

      final int wordRefStart = wordBoundaries[w];
      final int wordRefEnd = (w + 1 < wordBoundaries.length)
          ? wordBoundaries[w + 1]
          : fullPhonemes.length;
      if (wordRefStart >= wordRefEnd) continue;

      final String wordText = fullPhonemes.substring(
        wordRefStart,
        min(wordRefEnd, fullPhonemes.length),
      );

      // 1. Build cohesive phonetic spans for this word
      final List<_PhoneticSpan> spans = _buildWordSpans(
        fullPhonemes: fullPhonemes,
        wordRefStart: wordRefStart,
        wordRefEnd: wordRefEnd,
        expectedWordRules: expectedWordRules,
      );

      final List<ReciterError> wordErrors = [];

      // 2. Evaluate each span with aggregated ASR alignments and durations
      for (final span in spans) {
        // Collect all alignment items belonging to this reference span
        final spanAlignments = alignments.where((a) {
          final absRef = targetCharCursor + a.refIdx;
          return absRef >= span.refStart && absRef < span.refEnd;
        }).toList();

        if (spanAlignments.isEmpty) continue;

        // Collect matched predicted characters and sum actual acoustic duration
        final List<String> predChunks = [];
        final Set<int> usedPredIndices = {};
        double totalSpanDuration = 0.0;
        bool hasDelete = false;

        for (final a in spanAlignments) {
          if (a.opType == 'delete') {
            hasDelete = true;
          }
          final absPred = bestAsrStartIdx + a.predIdx;
          if (absPred >= 0 && absPred < currentAsrText.length) {
            predChunks.add(currentAsrText[absPred]);
            if (!usedPredIndices.contains(absPred)) {
              usedPredIndices.add(absPred);
              if (absPred < trackingTimestamps.length) {
                totalSpanDuration += trackingTimestamps[absPred];
              }
            }
          }
        }

        final String predText = predChunks.join('');

        // Evaluate the span against Madd, Shaddah, Ghunnah, Tashkeel, or Consonants
        final spanErrors = _evaluateSpan(
          span: span,
          predText: predText,
          spanDuration: totalSpanDuration,
          hasDelete: hasDelete,
          wordText: wordText,
          wordRefEnd: wordRefEnd,
          config: config,
        );

        wordErrors.addAll(spanErrors);
      }

      if (wordErrors.isNotEmpty) {
        // Sort errors by UI priority
        wordErrors.sort(
          (a, b) => _getErrorPriority(a).compareTo(_getErrorPriority(b)),
        );

        // Filter out expected ASR noise
        wordErrors.removeWhere((e) {
          if (e.errorType == ErrorCategory.normal) {
            return config.hideExpectedAsrNoise &&
                _isExpectedAsrNoise(e, config);
          }
          return false;
        });

        // Deduplicate identical errors on the same rule/phoneme
        final List<ReciterError> deduplicated = [];
        final Set<String> seenKeys = {};
        for (final e in wordErrors) {
          final key =
              '${e.errorType.name}_${e.expectedRule?.name.en ?? ''}_${e.expectedPh}';
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            deduplicated.add(e);
          }
        }

        if (deduplicated.isNotEmpty) {
          errorsByWord[w] = deduplicated;

          for (var e in deduplicated) {
            String ruleInfo = e.expectedRule != null
                ? ' | Rule: ${e.expectedRule!.name.en} (req: ${e.expectedDuration?.toStringAsFixed(2)}s, got: ${e.actualDuration?.toStringAsFixed(2)}s)'
                : '';
            DebugLogger.log(
              'Error',
              '🚨 [ERROR LOG] Word "$wordText" ($w) | ${e.errorType.name.toUpperCase()} -> ${e.speechErrorType.name.toUpperCase()} (Exp: "${e.expectedPh}" vs Got: "${e.predictedPh}")$ruleInfo',
            );
          }
        }
      }
    }

    return errorsByWord;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3.2 REFERENCE SPAN BUILDER
  // Groups contiguous repeating characters (Madd, Shaddah, Ghunnah) into spans
  // ───────────────────────────────────────────────────────────────────────────
  static List<_PhoneticSpan> _buildWordSpans({
    required String fullPhonemes,
    required int wordRefStart,
    required int wordRefEnd,
    required List<WordTajweedRule> expectedWordRules,
  }) {
    final List<_PhoneticSpan> spans = [];
    int cursor = wordRefStart;

    // Track available Madd rules so multiple Madd spans in the same word
    // (e.g. Lazem + Aared in "الضَّآلِّينَ", or Normal + Aared in "العَٰلَمِينَ")
    // each receive their distinct rule rather than reusing the first rule.
    final List<WordTajweedRule> remainingMaddRules =
        expectedWordRules.where((r) => r.ruleId >= 1 && r.ruleId <= 7).toList();

    while (cursor < wordRefEnd) {
      final String ch = fullPhonemes[cursor];

      // ── 1. Madd Span (Consecutive Madd vowels: ا, ۦ, ۥ) ──
      if ('اۥۦ'.contains(ch)) {
        int end = cursor;
        while (end < wordRefEnd && fullPhonemes[end] == ch) {
          end++;
        }
        final refText = fullPhonemes.substring(cursor, end);

        // Find matching Madd rule from remainingMaddRules:
        // Prioritize exact goldenLen match with phoneme elongation length,
        // then consume in sequential order.
        WordTajweedRule? matchedRule;
        if (remainingMaddRules.isNotEmpty) {
          int matchIdx = remainingMaddRules.indexWhere(
            (r) => r.goldenLen == refText.length,
          );
          if (matchIdx == -1) {
            matchIdx = 0;
          }
          matchedRule = remainingMaddRules.removeAt(matchIdx);
        }

        spans.add(
          _PhoneticSpan(
            refStart: cursor,
            refEnd: end,
            refText: refText,
            baseChar: ch,
            isMadd: true,
            isShaddah: false,
            isGhunnah: false,
            matchedWordRule: matchedRule,
          ),
        );
        cursor = end;
        continue;
      }

      // ── 2. Mushaddad Ghunnah Span (نننن or مممم) ──
      if ('نم'.contains(ch) &&
          cursor + 1 < wordRefEnd &&
          fullPhonemes[cursor + 1] == ch &&
          cursor + 2 < wordRefEnd &&
          fullPhonemes[cursor + 2] == ch) {
        int end = cursor;
        while (end < wordRefEnd && fullPhonemes[end] == ch) {
          end++;
        }
        // Include attached Harakah if present
        if (end < wordRefEnd && 'َُِ'.contains(fullPhonemes[end])) {
          end++;
        }
        final refText = fullPhonemes.substring(cursor, end);

        WordTajweedRule? matchedRule;
        for (final r in expectedWordRules) {
          if (r.ruleId == 10) {
            matchedRule = r;
            break;
          }
        }

        spans.add(
          _PhoneticSpan(
            refStart: cursor,
            refEnd: end,
            refText: refText,
            baseChar: ch,
            isMadd: false,
            isShaddah: false,
            isGhunnah: true,
            matchedWordRule: matchedRule ??
                WordTajweedRule(
                  ruleId: 10,
                  nameAr: ch == 'ن' ? 'النون المشددة' : 'الميم المشددة',
                  nameEn: ch == 'ن' ? 'Mushaddad Noon' : 'Mushaddad Meem',
                  goldenLen: 2,
                ),
          ),
        );
        cursor = end;
        continue;
      }

      // ── 3. Shaddah Span (Doubled consonants: رر, لل, تت, etc.) ──
      if (cursor + 1 < wordRefEnd &&
          fullPhonemes[cursor + 1] == ch &&
          !'اۥۦ'.contains(ch)) {
        int end = cursor;
        while (end < wordRefEnd && fullPhonemes[end] == ch) {
          end++;
        }
        // Include attached Harakah if present
        if (end < wordRefEnd && 'َُِ'.contains(fullPhonemes[end])) {
          end++;
        }
        final refText = fullPhonemes.substring(cursor, end);

        spans.add(
          _PhoneticSpan(
            refStart: cursor,
            refEnd: end,
            refText: refText,
            baseChar: ch,
            isMadd: false,
            isShaddah: true,
            isGhunnah: false,
            matchedWordRule: const WordTajweedRule(
              ruleId: 9,
              nameAr: 'الشدة',
              nameEn: 'Shaddah',
              goldenLen: 1,
            ),
          ),
        );
        cursor = end;
        continue;
      }

      // ── 4. Single Consonant + Harakah / Diacritic Span ──
      int end = cursor + 1;
      while (end < wordRefEnd && 'َُِڇؙ۪ۜـ'.contains(fullPhonemes[end])) {
        end++;
      }
      final refText = fullPhonemes.substring(cursor, end);

      spans.add(
        _PhoneticSpan(
          refStart: cursor,
          refEnd: end,
          refText: refText,
          baseChar: ch,
          isMadd: false,
          isShaddah: false,
          isGhunnah: false,
        ),
      );
      cursor = end;
    }

    return spans;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3.3 SPAN EVALUATION PIPELINE
  // ───────────────────────────────────────────────────────────────────────────
  static List<ReciterError> _evaluateSpan({
    required _PhoneticSpan span,
    required String predText,
    required double spanDuration,
    required bool hasDelete,
    required String wordText,
    required int wordRefEnd,
    TrackerConfig config = const TrackerConfig(),
  }) {
    final List<ReciterError> errors = [];
    final speed = config.recitationSpeed;

    // ── Phase 1: Base Character Verification (Letter Identity & Deletion) ──
    if (span.refText.isNotEmpty) {
      if (predText.isEmpty) {
        if (span.isMadd || span.isShaddah || span.isGhunnah) {
          final rule = span.matchedWordRule != null
              ? _instantiateTajweedRule(span.matchedWordRule!, config)
              : (span.isMadd
                  ? _deriveMaddRuleFromLength(span.refText.length, config)
                  : (span.isShaddah
                      ? const ShaddahRule()
                      : const MushaddadGhunnahRule()));
          errors.add(
            ReciterError(
              errorType: ErrorCategory.tajweed,
              speechErrorType: SpeechErrorType.delete,
              durationStatus: TajweedDurationStatus.underheld,
              expectedPh: span.refText,
              predictedPh: '',
              expectedRule: rule,
              expectedDuration: rule.getRequiredDuration(speed),
              actualDuration: 0.0,
            ),
          );
          return errors;
        }
        errors.add(
          ReciterError(
            errorType: ErrorCategory.normal,
            speechErrorType: SpeechErrorType.delete,
            expectedPh: span.refText,
            predictedPh: '',
          ),
        );
        return errors;
      } else if (span.baseChar != predText[0] &&
          !PhoneticCostEngine.isEquivalentGlyph(
            span.baseChar.codeUnitAt(0),
            predText.codeUnitAt(0),
          )) {
        // Base consonant / Madd vowel substituted (e.g. ي vs ت, ۦ vs ۥ)
        errors.add(
          ReciterError(
            errorType: ErrorCategory.normal,
            speechErrorType: SpeechErrorType.replace,
            expectedPh: span.refText,
            predictedPh: predText,
          ),
        );
        return errors;
      }
    }

    // ── Phase 2: Tajweed Duration Rules (Madd, Ghunnah, Shaddah) ──
    if (span.isMadd) {
      if (spanDuration <= 0.0) return errors;

      final rule = span.matchedWordRule != null
          ? _instantiateTajweedRule(span.matchedWordRule!, config)
          : _deriveMaddRuleFromLength(span.refText.length, config);

      return _evaluateDurationRule(
        rule: rule,
        span: span,
        predText: predText,
        spanDuration: spanDuration,
        speed: speed,
        categoryTag: 'MADD',
      );
    }

    if (span.isGhunnah) {
      if (spanDuration <= 0.0) return errors;

      final rule = span.matchedWordRule != null
          ? _instantiateTajweedRule(span.matchedWordRule!, config)
          : MushaddadGhunnahRule.withNames(
              nameAr: span.baseChar == 'ن' ? 'النون المشددة' : 'الميم المشددة',
              nameEn:
                  span.baseChar == 'ن' ? 'Mushaddad Noon' : 'Mushaddad Meem',
            );

      return _evaluateDurationRule(
        rule: rule,
        span: span,
        predText: predText,
        spanDuration: spanDuration,
        speed: speed,
        categoryTag: 'GHUNNAH',
      );
    }

    if (span.isShaddah) {
      if (spanDuration <= 0.0) return errors;

      return _evaluateDurationRule(
        rule: const ShaddahRule(),
        span: span,
        predText: predText,
        spanDuration: spanDuration,
        speed: speed,
        categoryTag: 'SHADDAH',
      );
    }

    // ── Phase 3: Tashkeel / Harakat Evaluation on Matching Base Consonants ──
    final String refVowels = _extractVowels(span.refText);
    final String predVowels = _extractVowels(predText);

    if (refVowels.isNotEmpty || predVowels.isNotEmpty) {
      // Stopping on Sukoon (no vowel) on the terminal letter of the word is valid Waqf, not a Tashkeel error
      final bool isTerminalWaqf =
          span.refEnd == wordRefEnd && predVowels.isEmpty;
      if (!isTerminalWaqf && refVowels != predVowels) {
        errors.add(
          ReciterError(
            errorType: ErrorCategory.tashkeel,
            speechErrorType: SpeechErrorType.replace,
            expectedPh: span.refText,
            predictedPh: predText,
          ),
        );
      }
    }

    return errors;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3.4 HELPER METHODS
  // ───────────────────────────────────────────────────────────────────────────

  static List<ReciterError> _evaluateDurationRule({
    required TajweedRule rule,
    required _PhoneticSpan span,
    required String predText,
    required double spanDuration,
    required RecitationSpeed speed,
    required String categoryTag,
  }) {
    final List<ReciterError> errors = [];
    final double req = rule.getRequiredDuration(speed);
    final double minReq = rule.getMinAllowedDuration(speed);
    final TajweedDurationStatus durStatus =
        rule.checkDurationStatus(spanDuration, speed);

    DebugLogger.log(
      'Tajweed',
      '🎯 [GRADING $categoryTag] Span: "${span.refText}" (${rule.name.en}) | ASR: "$predText" | Measured: ${spanDuration.toStringAsFixed(3)}s | Target: ${req.toStringAsFixed(3)}s (min: ${minReq.toStringAsFixed(3)}s) | Status: ${durStatus.name.toUpperCase()}',
    );

    if (durStatus == TajweedDurationStatus.underheld ||
        durStatus == TajweedDurationStatus.overheld) {
      errors.add(
        ReciterError(
          errorType: ErrorCategory.tajweed,
          speechErrorType: SpeechErrorType.replace,
          durationStatus: durStatus,
          expectedPh: span.refText,
          predictedPh: predText,
          expectedRule: rule,
          expectedDuration: req,
          actualDuration: spanDuration,
        ),
      );
    }
    return errors;
  }

  static TajweedRule _deriveMaddRuleFromLength(
    int len, [
    TrackerConfig config = const TrackerConfig(),
  ]) {
    if (len >= 6) return const LazemMaddRule();
    if (len >= 4) return AaredMaddRule(config.recitationSpeed.aaredMaddHarakat);
    return const NormalMaddRule();
  }

  static String _extractVowels(String text) {
    final sb = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if ('َُِ'.contains(text[i])) {
        sb.write(text[i]);
      }
    }
    return sb.toString();
  }

  static TajweedRule _instantiateTajweedRule(
    WordTajweedRule wRule, [
    TrackerConfig config = const TrackerConfig(),
  ]) {
    final speed = config.recitationSpeed;
    switch (wRule.ruleId) {
      case 1:
        return const NormalMaddRule();
      case 2:
        return MonfaselMaddRule(speed.monfaselMaddHarakat);
      case 3:
        return MottaselMaddRule(speed.mottaselMaddHarakat);
      case 4:
        return MottaselMaddPauseRule(speed.mottaselMaddPauseHarakat);
      case 5:
        return AaredMaddRule(speed.aaredMaddHarakat);
      case 6:
        return const LazemMaddRule();
      case 7:
        return LeenMaddRule(speed.leenMaddHarakat);
      case 9:
        return const ShaddahRule();
      case 10:
        return MushaddadGhunnahRule.withNames(
          nameAr: wRule.nameAr,
          nameEn: wRule.nameEn,
        );
      default:
        return MaddRule(
          name: LangName(ar: wRule.nameAr, en: wRule.nameEn),
          goldenLen: wRule.goldenLen,
        );
    }
  }

  static bool _isExpectedAsrNoise(ReciterError e,
      [TrackerConfig config = const TrackerConfig()]) {
    final int refCode =
        e.expectedPh.isNotEmpty ? e.expectedPh.codeUnitAt(0) : 0;
    final int asrCode =
        e.predictedPh.isNotEmpty ? e.predictedPh.codeUnitAt(0) : 0;

    switch (e.speechErrorType) {
      case SpeechErrorType.replace:
        return refCode > 0 &&
            asrCode > 0 &&
            PhoneticCostEngine.getSubstitutionCost(
                    asrCode, refCode, config.acousticConfusionCost) <=
                config.acousticConfusionCost;
      case SpeechErrorType.delete:
        // Common ASR drops (ا, ء, ل, ٱ) and Madd vowels (و, ي, ۥ, ۦ)
        return refCode == 0x0627 ||
            refCode == 0x0621 ||
            refCode == 0x0644 ||
            refCode == 0x0671 ||
            refCode == 0x0648 ||
            refCode == 0x064A ||
            refCode == 0x06E5 ||
            refCode == 0x06E6;
      case SpeechErrorType.insert:
        return asrCode > 0 &&
            (PhoneticCostEngine.isTashkeel(asrCode) ||
                PhoneticCostEngine.getInsertionCost(
                        e.predictedPh,
                        0,
                        config.standardInsertionCost,
                        config.acousticConfusionCost) <=
                    config.acousticConfusionCost);
    }
  }

  static int _getErrorPriority(ReciterError e) {
    if (e.errorType == ErrorCategory.normal) return 0;
    if (e.errorType == ErrorCategory.tashkeel) return 1;
    if (e.expectedRule is MaddRule) return 2;
    if (e.expectedRule is MushaddadGhunnahRule) return 3;
    if (e.expectedRule is ShaddahRule) return 4;
    return 5;
  }
}
