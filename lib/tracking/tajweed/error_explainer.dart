// lib/tracking/tajweed/error_explainer.dart
// ═══════════════════════════════════════════════════════════════════════════════
// ERROR EXPLAINER MODULE (ADVANCED ORGANIZED & FULLY DOCUMENTED ARCHITECTURE)
//
// Highlights & categorizes reciter errors using a multi-phase evaluation pipeline:
//   Phase 1: Phonetic Alignment Engine (`Wagner-Fischer Levenshtein DP Matrix`).
//   Phase 2: Base Consonant & Deletion/Insertion Verification (`ErrorCategory.normal`).
//   Phase 3: Harakat & Tashkeel Modification Verification (`ErrorCategory.tashkeel`).
//   Phase 4: Acoustic Duration & Doubling Verification (`ErrorCategory.tajweed`).
//
// ───────────────────────────────────────────────────────────────────────────────
// THE "LENGTH PROTOCOL" DICTIONARY (Python Generator ➝ Dart Evaluator)
//
// This app avoids expensive JSON parsing in the hot loop by encoding Tajweed
// rules directly into the string lengths of `ordered_quran_phonemes.json`.
// `QuranNormalizer.chunkPhonemes()` isolates repeating characters. This file
// then routes the chunk to the correct rule based on its length and identity:
//
// 1. QALQALAH (Bounce):
//    - Identity: Contains the `ڇ` marker (e.g., `بڇ`).
//    - Action: `QalqalahRule` verifies the reciter did NOT hold the letter.
//
// 2. MADD (Vowel Prolongation):
//    - Identity: Base character is `ا`, `ۥ`, or `ۦ`.
//    - Length 2-3 : `NormalMaddRule` (2 beats).
//    - Length 4-5 : `Monfasel`/`Mottasel`/`Aared` Madd (4 beats).
//    - Length 6+  : `LazemMaddRule` (6 beats).
//    - Exception  : `LeenMaddRule` targets `ي` or `و` at verse ends (Length >= 4).
//
// 3. GHUNNAH (Nasal Resonance):
//    - Identity: Nasal consonant (`ن`, `م`, `ں`, `۾`) or Idgham (`ي`, `و`).
//    - Length: ALWAYS >= 3 (e.g., `ںںں` or `مممم` or `ييي`).
//    - Action: `Ghonnah` rule expects ~0.80s (2 beats) of nasal duration.
//
// 4. PURE SHADDAH (Consonant Doubling & Idgham without Ghunnah):
//    - Identity: Any doubled consonant that is NOT a Ghunnah or Leen.
//    - Length: EXACTLY 2 (e.g., `رر`, `بب`, `يي`).
//    - Action: `ShaddahRule` expects ~0.40s (1 beat) of firm closure.
//
// 5. NORMAL:
//    - Identity: Single consonant (Length 1). No duration checking required.
// ═══════════════════════════════════════════════════════════════════════════════
import 'tajweed_rules.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1: DATA MODELS & ENUMS
// ═══════════════════════════════════════════════════════════════════════════════
/// Broad classification of reciter errors used by UI color highlighting and statistics.
enum ErrorCategory {
  /// Acoustic duration or Shaddah doubling mismatch (`Yellow/Red highlight`).
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
  /// High-level classification (`tajweed`, `normal`, `tashkeel`).
  final ErrorCategory errorType;

  /// Specific alignment operation (`insert`, `delete`, `replace`).
  final SpeechErrorType speechErrorType;

  /// Specific duration diagnosis (`valid`, `defect`, `surplus`), if applicable.
  final TajweedDurationStatus? durationStatus;

  /// Expected reference phoneme string or chunk from `ordered_quran_phonemes.json`.
  final String expectedPh;

  /// Actual predicted phoneme string or chunk output by the ASR model.
  final String predictedPh;

  /// The expected Tajweed rule (if applicable) triggered by `expectedPh`.
  final TajweedRule? expectedRule;

  /// The predicted/evaluated Tajweed rule (if applicable) corresponding to `predictedPh`.
  final TajweedRule? predictedRule;

  /// Required minimum duration in seconds (from `expectedRule.getRequiredDuration()`).
  final double? expectedDuration;

  /// Actual acoustic duration in seconds held by the reciter (sum of character timestamps).
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
  @override
  String toString() {
    return 'ReciterError(type: $errorType, action: $speechErrorType, status: $durationStatus, expected: "$expectedPh", predicted: "$predictedPh", expectedRule: ${expectedRule?.name.en}, predictedRule: ${predictedRule?.name.en}, expDur: $expectedDuration, actDur: $actualDuration)';
  }

  Map<String, dynamic> toMap() {
    return {
      'errorType': errorType.index,
      'speechErrorType': speechErrorType.index,
      'durationStatus': durationStatus?.index,
      'expectedPh': expectedPh,
      'predictedPh': predictedPh,
      'expectedRule': _ruleToMap(expectedRule),
      'predictedRule': _ruleToMap(predictedRule),
      'expectedDuration': expectedDuration,
      'actualDuration': actualDuration,
    };
  }

  static ReciterError fromMap(Map<String, dynamic> map) {
    return ReciterError(
      errorType: ErrorCategory.values[map['errorType']],
      speechErrorType: SpeechErrorType.values[map['speechErrorType']],
      durationStatus: map['durationStatus'] != null
          ? TajweedDurationStatus.values[map['durationStatus']]
          : null,
      expectedPh: map['expectedPh'],
      predictedPh: map['predictedPh'],
      expectedRule: _ruleFromMap(map['expectedRule']),
      predictedRule: _ruleFromMap(map['predictedRule']),
      expectedDuration: map['expectedDuration'],
      actualDuration: map['actualDuration'],
    );
  }

  static Map<String, dynamic>? _ruleToMap(TajweedRule? rule) {
    if (rule == null) return null;
    return {
      'type': rule.runtimeType.toString(),
      'nameAr': rule.name.ar,
      'nameEn': rule.name.en,
      'goldenLen': rule.goldenLen,
      'tag': rule.tag,
    };
  }

  static TajweedRule? _ruleFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    String type = map['type'];
    LangName name = LangName(ar: map['nameAr'], en: map['nameEn']);
    int goldenLen = map['goldenLen'];
    String? tag = map['tag'];
    if (type == 'LazemMaddRule') return LazemMaddRule();
    if (type == 'LeenMaddRule') return LeenMaddRule();
    if (type == 'AaredMaddRule') return AaredMaddRule();
    if (type == 'MonfaselMaddRule') return MonfaselMaddRule();
    if (type == 'MottaselMaddRule') return MottaselMaddRule();
    if (type == 'NormalMaddRule') return NormalMaddRule();
    if (type == 'MaddRule')
      return MaddRule(name: name, goldenLen: goldenLen, tag: tag);
    if (type == 'Ghonnah')
      return Ghonnah(name: name, goldenLen: goldenLen, tag: tag);
    if (type == 'ShaddahRule') return ShaddahRule(tag: tag);
    if (type == 'QalqalahRule') return QalqalahRule();
    // Fallback if needed but we should cover all active types
    return _GenericTajweedRule(name: name, goldenLen: goldenLen, tag: tag);
  }
}

class _GenericTajweedRule extends TajweedRule {
  _GenericTajweedRule({
    required super.name,
    required super.goldenLen,
    super.tag,
  });
  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return _GenericTajweedRule(
      name: name ?? this.name,
      goldenLen: goldenLen,
      tag: tag ?? this.tag,
    );
  }
}

/// Represents the alignment opcode between a single reference phoneme group and predicted phoneme group.
class PhonemeGroupAlignment {
  /// The edit operation (`'insert'`, `'delete'`, `'replace'`, or `'equal'`).
  final String opType;

  /// 0-indexed position within the reference phoneme group list (`refGroups`).
  final int refIdx;

  /// 0-indexed position within the predicted phoneme group list (`predGroups`).
  final int predIdx;
  PhonemeGroupAlignment({
    required this.opType,
    required this.refIdx,
    required this.predIdx,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2: ERROR EXPLAINER ENGINE & PIPELINE
// ═══════════════════════════════════════════════════════════════════════════════
class ErrorExplainer {
  // ───────────────────────────────────────────────────────────────────────────
  // 2.1 ORCHESTRATOR: explainAyahError
  // Iterates over words in the target window, computes boundaries & alignments,
  // and routes chunks through our multi-phase evaluation pipeline.
  // ───────────────────────────────────────────────────────────────────────────
  static Map<int, List<ReciterError>> evaluatePreAlignedWords({
    required List<PhonemeGroupAlignment> alignments,
    required List<String> globalRefChunks,
    required List<int> refChunkToWordMap,
    required List<String> currentAsrChunks,
    required List<double> trackingTimestamps,
    required int bestAsrStartIdx,
    required int targetChunkCursor,
    required int startWordId,
    required int nextWordId,
    required int totalAyahWords,
    double? matchScore,
    String? previousWordTail,
    String trackingStrictness = 'normal',
  }) {
    final Map<int, List<ReciterError>> errorsByWord = {};
    final Map<int, List<String>> wordErrorDescMap = {};
    final Map<int, List<String>> timingChecksDescMap = {};
    for (var align in alignments) {
      if (align.refIdx < 0 && align.predIdx < 0) continue;
      int absRefIdx = targetChunkCursor + align.refIdx;
      int wIdx = -1;
      // If it's an insertion, we assign it to the previous word or current word context.
      if (absRefIdx >= 0 && absRefIdx < refChunkToWordMap.length) {
        wIdx = refChunkToWordMap[absRefIdx];
      } else if (align.refIdx == -1 &&
          targetChunkCursor < refChunkToWordMap.length) {
        wIdx = refChunkToWordMap[targetChunkCursor];
      }
      if (wIdx < startWordId || wIdx >= nextWordId)
        continue; // Out of bounds of the committed match
      String refChunk = '';
      if (absRefIdx >= 0 && absRefIdx < globalRefChunks.length) {
        refChunk = globalRefChunks[absRefIdx];
      }
      String nextRefChunk = '';
      bool isNextChunkInNextWord = false;
      if (absRefIdx >= 0 && absRefIdx + 1 < globalRefChunks.length) {
        nextRefChunk = globalRefChunks[absRefIdx + 1];
        if (refChunkToWordMap[absRefIdx] != refChunkToWordMap[absRefIdx + 1]) {
          isNextChunkInNextWord = true;
        }
      }
      int absPredIdx = bestAsrStartIdx + align.predIdx;
      String predChunk = '';
      if (absPredIdx >= 0 && absPredIdx < currentAsrChunks.length) {
        predChunk = currentAsrChunks[absPredIdx];
      }
      // Calculate durations
      double chunkDuration = 0.0;
      List<double> chunkCharDurations = [];
      if (absPredIdx >= 0) {
        int charStart = 0;
        for (int k = 0; k < absPredIdx; k++)
          charStart += currentAsrChunks[k].length;
        for (int c = 0; c < predChunk.length; c++) {
          if (charStart + c < trackingTimestamps.length) {
            double ts = trackingTimestamps[charStart + c];
            chunkCharDurations.add(ts);
            chunkDuration += ts;
          }
        }
        if (chunkDuration <= 0.0) chunkDuration = 0.15;
      }
      wordErrorDescMap.putIfAbsent(wIdx, () => []);
      timingChecksDescMap.putIfAbsent(wIdx, () => []);
      List<ReciterError> chunkErrors = _evaluateChunkAlignment(
        align: align,
        refChunk: refChunk,
        predChunk: predChunk,
        chunkDuration: chunkDuration,
        chunkCharDurations: chunkCharDurations,
        isLastWord: wIdx == totalAyahWords - 1,
        wordIdx: wIdx,
        wordErrorDesc: wordErrorDescMap[wIdx]!,
        timingChecksDesc: timingChecksDescMap[wIdx]!,
        nextRefChunk: nextRefChunk,
        isNextChunkInNextWord: isNextChunkInNextWord,
        globalRefChunks: globalRefChunks,
        refChunkToWordMap: refChunkToWordMap,
      );
      if (chunkErrors.isNotEmpty) {
        errorsByWord.putIfAbsent(wIdx, () => []).addAll(chunkErrors);
      }
    }
    // Sort every word's error list according to UI display priority.
    errorsByWord.forEach(
      (_, list) => list.sort(
        (a, b) => _getErrorPriority(a).compareTo(_getErrorPriority(b)),
      ),
    );
    // Note: The Confidence-Gate (which used to clear errors if matchScore > 0.15)
    // has been removed. We want Tajweed errors (yellow) and Normal errors (red)
    // to always be passed to the UI for accurate highlighting, regardless of score.
    // ── STRICTNESS FILTERING (Easy / Normal / Strict) ──
    // EASY: Exclude Normal errors and Surplus duration errors.
    // NORMAL & STRICT: Show all errors (Only Dictation Threshold is affected).
    errorsByWord.forEach((wIdx, list) {
      list.removeWhere((e) {
        if (trackingStrictness == 'easy') {
          return e.errorType == ErrorCategory.normal ||
              e.durationStatus == TajweedDurationStatus.surplus;
        }
        return false;
      });
    });
    errorsByWord.forEach((wIdx, list) {
      String wordStr = '';
      for (int i = 0; i < globalRefChunks.length; i++) {
        if (refChunkToWordMap[i] == wIdx) wordStr += globalRefChunks[i];
      }
      for (var e in list) {
        String ruleInfo = e.expectedRule != null
            ? ' | Rule: ${e.expectedRule!.name.en}'
            : '';
        print(
          '🚨 [ERROR LOG] Word "$wordStr" ($wIdx) | ${e.errorType.name.toUpperCase()} -> ${e.speechErrorType.name.toUpperCase()} (Exp: "${e.expectedPh}" vs Got: "${e.predictedPh}")$ruleInfo',
        );
      }
    });
    // Clean up empty lists after filtering
    errorsByWord.removeWhere((wIdx, list) => list.isEmpty);
    return errorsByWord;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2.2 CHUNK EVALUATION PIPELINE
  // Evaluates a single chunk alignment through distinct, prioritized phases:
  //   1. Insertion / Deletion / Base Letter Replacement (`Normal` errors)
  //   2. Tashkeel & Harakat Mismatches (`Tashkeel` errors)
  //   3. Acoustic Duration & Doubling Verification (`Tajweed` rules)
  // ───────────────────────────────────────────────────────────────────────────
  static List<ReciterError> _evaluateChunkAlignment({
    required PhonemeGroupAlignment align,
    required String refChunk,
    required String predChunk,
    required double chunkDuration,
    required List<double> chunkCharDurations,
    required bool isLastWord,
    required int wordIdx,
    required List<String> wordErrorDesc,
    required List<String> timingChecksDesc,
    required String nextRefChunk,
    required bool isNextChunkInNextWord,
    required List<String> globalRefChunks,
    required List<int> refChunkToWordMap,
  }) {
    // ── Phase 1A: Complete Insertion Error ──
    // The DP Matrix found an ASR phoneme with NO matching reference phoneme.
    // Meaning the reciter hallucinated an entire syllable or word.
    if (align.opType == 'insert') {
      return [
        ReciterError(
          errorType: ErrorCategory.normal,
          speechErrorType: SpeechErrorType.insert,
          expectedPh: '',
          predictedPh: predChunk,
        ),
      ];
    }
    // ── Phase 1B: Complete Deletion Error ──
    // The reciter completely skipped a mandatory expected phoneme.
    // Example: Expected "بِ" but the reciter jumped straight to "سْ".
    if (align.opType == 'delete') {
      wordErrorDesc.add('Delete(ref:$refChunk)');
      return [
        ReciterError(
          errorType: ErrorCategory.normal,
          speechErrorType: SpeechErrorType.delete,
          expectedPh: refChunk,
          predictedPh: '',
        ),
      ];
    }
    List<ReciterError> chunkErrors = [];
    // ── Phase 1C: Base Consonant Replacement Error ──
    // The reciter pronounced a completely different letter (e.g. expected 'س', heard 'م').
    // We check `_getSubCost` to see if they are phonetically disparate.
    if (refChunk.isNotEmpty &&
        predChunk.isNotEmpty &&
        refChunk[0] != predChunk[0]) {
      // If the two consonants belong to disparate groups (cost > 6), return early as a Normal error.
      // This immediately stops Phase 3 (Tajweed) from running. We don't care about the
      // duration of a Madd if they said the completely wrong letter!
      if (_getSubCost(refChunk[0], predChunk[0]) > 6) {
        wordErrorDesc.add('Replace(ref:$refChunk got:$predChunk)');
        return [
          ReciterError(
            errorType: ErrorCategory.normal,
            speechErrorType: SpeechErrorType.replace,
            expectedPh: refChunk,
            predictedPh: predChunk,
          ),
        ];
      } else {
        // If they are phonetically similar (cost <= 6, like س vs ص or د vs ض), record the letter replacement
        // AND allow the chunk to continue to Phase 3 so any Madd/Ghunna/Shaddah error on this chunk is ALSO recorded!
        wordErrorDesc.add('Replace(ref:$refChunk got:$predChunk)');
        chunkErrors.add(
          ReciterError(
            errorType: ErrorCategory.normal,
            speechErrorType: SpeechErrorType.replace,
            expectedPh: refChunk,
            predictedPh: predChunk,
          ),
        );
      }
    }
    // ── Phase 2: Tashkeel & Harakat Verification ──
    // The base consonants match (e.g. 'س' vs 'س'), but the diacritics differ (e.g. 'سَ' vs 'سُ').
    // We mathematically strip the base letter from both strings and compare the remaining diacritics.
    if (refChunk.isNotEmpty &&
        predChunk.isNotEmpty &&
        refChunk[0] == predChunk[0] &&
        refChunk.replaceAll(refChunk[0], '') !=
            predChunk.replaceAll(predChunk[0], '')) {
      wordErrorDesc.add('Tashkeel(ref:$refChunk got:$predChunk)');
      chunkErrors.add(
        ReciterError(
          errorType: ErrorCategory.tashkeel,
          speechErrorType: SpeechErrorType.replace,
          expectedPh: refChunk,
          predictedPh: predChunk,
        ),
      );
    }
    // ── Phase 3: Acoustic Duration & Doubling Verification (Tajweed Rules) ──
    // This is the core Tajweed evaluator. We extract all rules that map to this specific phoneme.
    // If the rule expects duration (useDurationOnly), we sum the ASR timestamps for this chunk
    // and compare it to the required threshold.
    final allRules = _buildRuleList(
      refChunk: refChunk,
      isLastWord: isLastWord,
      nextRefChunk: nextRefChunk,
      isNextChunkInNextWord: isNextChunkInNextWord,
    );
    bool isValidTajweedVariation = false;
    for (var rule in allRules) {
      if (!rule.isPhStrIn(refChunk)) continue;
      var specificRule = rule.getRelevantRule(refChunk);
      if (specificRule == null) continue;
      // Qalqalah Counting Check
      if (specificRule is QalqalahRule) {
        bool refHasQalqalah = refChunk.contains('ڇ');
        bool predHasQalqalah = predChunk.contains('ڇ');
        if (refHasQalqalah && !predHasQalqalah) {
          wordErrorDesc.add(
            '${specificRule.name.en}(ref:$refChunk got:$predChunk)',
          );
          chunkErrors.add(
            ReciterError(
              errorType: ErrorCategory.tajweed,
              speechErrorType: align.opType == 'delete'
                  ? SpeechErrorType.delete
                  : SpeechErrorType.replace,
              expectedPh: refChunk,
              predictedPh: predChunk,
              expectedRule: specificRule,
            ),
          );
          continue;
        }
      }
      if (!specificRule.useDurationOnly) continue;
      // Shaddah Consonant Closure Check
      if (specificRule is ShaddahRule) {
        bool refDoubled = refChunk.length >= 2 && refChunk[1] == refChunk[0];
        bool predDoubled =
            predChunk.length >= 2 && predChunk[1] == predChunk[0];
        if (refDoubled && !predDoubled) {
          wordErrorDesc.add(
            '${specificRule.name.en}(ref:$refChunk got:$predChunk)',
          );
          chunkErrors.add(
            ReciterError(
              errorType: ErrorCategory.tajweed,
              speechErrorType: align.opType == 'delete'
                  ? SpeechErrorType.delete
                  : SpeechErrorType.replace,
              expectedPh: refChunk,
              predictedPh: predChunk,
              expectedRule: specificRule,
              expectedDuration: specificRule.getRequiredDuration(),
              actualDuration: chunkDuration,
            ),
          );
          continue;
        }
      }
      // Duration Threshold Evaluation (`checkDurationStatus` for lower & upper bounds)
      TajweedDurationStatus durStatus = specificRule.checkDurationStatus(
        chunkDuration,
      );
      bool hasValidDuration = (durStatus == TajweedDurationStatus.valid);
      double reqDur = specificRule.getRequiredDuration();
      String charBreakdown = chunkCharDurations
          .map((e) => "${(e * 1000).toStringAsFixed(0)}ms")
          .join("+");
      String statusStr = hasValidDuration
          ? "PASS ✓"
          : (durStatus == TajweedDurationStatus.defect
                ? "FAIL (defect نقص) ✗"
                : "FAIL (Surplus زيادة) ✗");
      String timingLog =
          '${specificRule.name.en}Timing(chunk:"$refChunk" chars:$charBreakdown = ${(chunkDuration * 1000).toStringAsFixed(0)}ms | need: ~${(reqDur * 1000).toStringAsFixed(0)}ms -> $statusStr)';
      String wordStr = '';
      for (int i = 0; i < globalRefChunks.length; i++) {
        if (refChunkToWordMap[i] == wordIdx) wordStr += globalRefChunks[i];
      }
      print('⏱️ [TAJWEED] Word "$wordStr" ($wordIdx) | $timingLog');
      timingChecksDesc.add(timingLog);
      if (!hasValidDuration) {
        String durDesc = durStatus == TajweedDurationStatus.defect
            ? '${specificRule.name.en}defect(ref:$refChunk got:${chunkDuration.toStringAsFixed(2)}s need:>=${reqDur.toStringAsFixed(2)}s)'
            : '${specificRule.name.en}Surplus(ref:$refChunk got:${chunkDuration.toStringAsFixed(2)}s need:~${reqDur.toStringAsFixed(2)}s)';
        wordErrorDesc.add(durDesc);
        chunkErrors.add(
          ReciterError(
            errorType: ErrorCategory.tajweed,
            speechErrorType: align.opType == 'delete'
                ? SpeechErrorType.delete
                : SpeechErrorType.replace,
            durationStatus: durStatus,
            expectedPh: refChunk,
            predictedPh: predChunk,
            expectedRule: specificRule,
            expectedDuration: reqDur,
            actualDuration: chunkDuration,
          ),
        );
      } else {
        isValidTajweedVariation = true;
      }
    }
    // ── Phase 4: Fallback Quality Checks ──
    if (chunkErrors.isEmpty && !isValidTajweedVariation) {
      if (align.opType == 'delete') {
        chunkErrors.add(
          ReciterError(
            errorType: ErrorCategory.normal,
            speechErrorType: SpeechErrorType.delete,
            expectedPh: refChunk,
            predictedPh: '',
          ),
        );
      } else if (align.opType == 'replace') {
        chunkErrors.add(
          ReciterError(
            errorType: ErrorCategory.normal,
            speechErrorType: SpeechErrorType.replace,
            expectedPh: refChunk,
            predictedPh: predChunk,
          ),
        );
      } else if (align.opType != 'equal' || refChunk != predChunk) {
        chunkErrors.add(
          ReciterError(
            errorType: ErrorCategory.tashkeel,
            speechErrorType: refChunk.length > predChunk.length
                ? SpeechErrorType.delete
                : (refChunk.length < predChunk.length
                      ? SpeechErrorType.insert
                      : SpeechErrorType.replace),
            expectedPh: refChunk,
            predictedPh: predChunk,
          ),
        );
      }
    }
    return chunkErrors;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2.3 TAJWEED RULE BUILDER
  // Evaluates repeating base characters to assign the appropriate Tajweed rule.
  // ───────────────────────────────────────────────────────────────────────────
  static List<TajweedRule> _buildRuleList({
    required String refChunk,
    required bool isLastWord,
    String nextRefChunk = '',
    bool isNextChunkInNextWord = false,
  }) {
    // Count true repeating base characters (`_countRepeatingBase`) to get Harakat count (`goldenLen`).
    final int baseCount = _countRepeatingBase(refChunk);
    final bool isPureMaddChar =
        refChunk.isNotEmpty &&
        (refChunk[0] == PhoneticConstants.alif ||
            refChunk[0] == PhoneticConstants.wawMadd ||
            refChunk[0] == PhoneticConstants.yaaMadd);
    final bool isLeenOrRepeatedWawYaa =
        refChunk.isNotEmpty &&
        (refChunk[0] == PhoneticConstants.waw ||
            refChunk[0] == PhoneticConstants.yaa) &&
        baseCount >= 2;
    final bool isMaddCandidate = isPureMaddChar || isLeenOrRepeatedWawYaa;
    // Check if the chunk is a doubled Yaa or Waw
    final bool isYaaOrWaw =
        refChunk.isNotEmpty &&
        (refChunk[0] == PhoneticConstants.yaa ||
            refChunk[0] == PhoneticConstants.waw);
    // ── THE CRITICAL FIX: Length-Based Identification ──
    // The previous logic `nextRefChunk[0] == refChunk[0]` was ALWAYS FALSE
    // because `chunkPhonemes` automatically merges identical characters into one chunk!
    // Instead, we use the pure length-based approach:
    // A regular Shaddah on Yaa/Waw (e.g., إِيَّاكَ) is exactly length 2.
    // An Idgham bi-Ghunnah on Yaa/Waw is ALWAYS exactly length 3 (because the Python generator sets `idgham_yaa_waw_len = 2` + 1).
    // A Leen Madd on Yaa/Waw is length 4.
    final bool isIdghamYaaWaw = isYaaOrWaw && baseCount == 3;
    return [
      // ── 1. Madd Rules (Vowel Elongation) ──
      // Evaluates specific duration requirements based on Harakat count (`baseCount`).
      if (isMaddCandidate) ...[
        if (baseCount >= 6)
          LazemMaddRule()
        else if (isLastWord && isLeenOrRepeatedWawYaa && baseCount >= 4)
          LeenMaddRule()
        else if (isLastWord && baseCount >= 4)
          AaredMaddRule()
        else if (baseCount == 4 || baseCount == 5)
          (isNextChunkInNextWord &&
                  nextRefChunk.isNotEmpty &&
                  (nextRefChunk[0] == 'ء' ||
                      nextRefChunk[0] == 'أ' ||
                      nextRefChunk[0] == 'إ' ||
                      nextRefChunk[0] == 'ؤ' ||
                      nextRefChunk[0] == 'ئ' ||
                      nextRefChunk[0] == 'آ'))
              ? MonfaselMaddRule()
              : MottaselMaddRule()
        else if (baseCount <= 3)
          NormalMaddRule()
        else
          MaddRule(
            name: const LangName(ar: "مد", en: "Madd"),
            goldenLen: baseCount,
          ),
      ],
      // ── 2. Ghunnah Rules (Nasal Resonance) ──
      // Exclude normal internal Shaddahs on Yaa/Waw from being evaluated as Ghunnah (Idgham).
      // They will gracefully fall through to ShaddahRule below.
      if (!isYaaOrWaw || isIdghamYaaWaw)
        Ghonnah(
          name: const LangName(ar: "غنة", en: "Ghonnah"),
          goldenLen: baseCount,
        ),
      // ── 3. Shaddah Rules (Consonant Doubling) ──
      // Exclude Shaddah evaluation if this is already confirmed as an Idgham bi-Ghunnah.
      // Also exclude it if it's a Leen Madd (baseCount >= 4 on Yaa/Waw) to prevent overlap.
      if (!isIdghamYaaWaw && !(isLeenOrRepeatedWawYaa && baseCount >= 4))
        ShaddahRule(),
      // ── 4. Qalqalah (Bounce) ──
      // Triggers if the chunk contains the Qalqalah marker (U+0686 ڇ)
      if (refChunk.contains('ڇ')) QalqalahRule(),
    ];
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2.4 HELPER & ALIGNMENT METHODS
  // ───────────────────────────────────────────────────────────────────────────
  /// Determines display priority for UI sorting: 1- Tashkeel, 2- Madd, 3- Ghunna, 4- Shaddah/Other.
  static int _getErrorPriority(ReciterError e) {
    if (e.errorType == ErrorCategory.tashkeel) return 1;
    if (e.expectedRule is MaddRule) return 2;
    if (e.expectedRule is Ghonnah) return 3;
    if (e.expectedRule is ShaddahRule) return 4;
    if (e.expectedRule is QalqalahRule) return 5;
    return 6;
  }

  /// Counts true repeating base characters in `chunk` (ignoring diacritics/tashkeel).
  /// Example: "ااا" -> 3, "للَ" -> 2, "ننننَ" -> 4.
  static int _countRepeatingBase(String chunk) {
    if (chunk.isEmpty) return 0;
    String base = chunk[0];
    int count = 0;
    for (int i = 0; i < chunk.length; i++) {
      if (chunk[i] == base) count++;
    }
    return count;
  }

  /// Computes graduated substitution cost between two base characters (`c1` vs `c2`).
  /// Assigns lower cost (`6`) for phonetically similar sounds (e.g., 'ذ' vs 'ز')
  /// and standard cost (`12`) for disparate sounds.
  static int _getSubCost(String c1, String c2) {
    if (c1 == c2) return 0;
    if (c1.isEmpty || c2.isEmpty) return 10;
    const groups = [
      "ذدضتط", // Dental/Alveolar stops & emphatics
      "ظزذصسث", // Sibilants & Interdentals
      "جزش", // Palatal/Alveolar fricatives & affricates
      "ءأإآاهعحغخ", // Throat letters & Alifs
      "ةهت", // Ta Marbuta, Ha, and Ta
      "ۦي", // Ya variants
      "ۥو", // Waw variants
      "ںن۾م", // Nasal variations
      "قكغ", // Velar/Uvular
      "فبم", // Labials
    ];
    for (final g in groups) {
      if (g.contains(c1) && g.contains(c2))
        return 6; // Graduated phonetic distance
    }
    return 12;
  }
}
