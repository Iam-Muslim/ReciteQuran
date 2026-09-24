// test/surah_highlight_store_test.dart
//
// SurahHighlightStore is HighlightingController's per-surah, per-ayah word
// highlight bookkeeping, extracted so the boundary-crossing behavior —
// retargeting the tracked surah without erasing the one just left behind —
// is verifiable without a SherpaEngine instance.

import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/recite_quran.dart';

void main() {
  group('SurahHighlightStore', () {
    test('marking a word green/red/yellow/neutral is queryable back', () {
      final store = SurahHighlightStore();
      store.markGreen(114, 1, 0);
      store.markRed(114, 1, 1);
      store.markNeutral(114, 1, 2);

      expect(store.isGreen(114, 1, 0), isTrue);
      expect(store.isRed(114, 1, 1), isTrue);
      expect(store.isNeutral(114, 1, 2), isTrue);
      expect(store.isUnspoken(114, 1, 3), isTrue);
    });

    test('marking a word overwrites any prior status for that word', () {
      final store = SurahHighlightStore();
      store.markGreen(114, 1, 0);
      store.markRed(114, 1, 0);

      expect(store.isGreen(114, 1, 0), isFalse);
      expect(store.isRed(114, 1, 0), isTrue);
    });

    test('markGreenWordAsYellow only downgrades a word that is currently green', () {
      final store = SurahHighlightStore();
      store.markRed(114, 1, 0);
      store.markGreenWordAsYellow(114, 1, 0, const []);
      expect(store.isRed(114, 1, 0), isTrue,
          reason: 'a red word must not be downgraded to yellow');

      store.markGreen(114, 1, 1);
      store.markGreenWordAsYellow(114, 1, 1, const []);
      expect(store.isGreen(114, 1, 1), isFalse);
      expect(store.isYellow(114, 1, 1), isTrue);
    });

    test('clearForRetarget without preserveOtherSurahs wipes every surah', () {
      final store = SurahHighlightStore();
      store.markGreen(113, 5, 0);
      store.markAyahCompleted(113, 5);

      store.clearForRetarget(114);

      expect(store.isGreen(113, 5, 0), isFalse);
      expect(store.completedAyahsFor(113), isEmpty);
    });

    test(
        'clearForRetarget with preserveOtherSurahs keeps the surah being left, '
        'resets only the surah being (re)loaded', () {
      final store = SurahHighlightStore();
      // Surah 113 fully recited and committed.
      store.markGreen(113, 5, 0);
      store.markAyahCompleted(113, 5);
      // Surah 114 had a stale red mark from an earlier pass through it.
      store.markRed(114, 1, 0);

      store.clearForRetarget(114, preserveOtherSurahs: true);

      // 113's highlights, still on screen, survive.
      expect(store.isGreen(113, 5, 0), isTrue);
      expect(store.completedAyahsFor(113), {5});
      // 114, the surah being (re)loaded, starts fresh.
      expect(store.isRed(114, 1, 0), isFalse);
      expect(store.isUnspoken(114, 1, 0), isTrue);
    });

    test('clearSurahFromAyah only wipes that surah, at/after startAyah', () {
      final store = SurahHighlightStore();
      store.markGreen(114, 1, 0);
      store.markGreen(114, 2, 0);
      store.markAyahCompleted(114, 1);
      store.markAyahCompleted(114, 2);
      store.markGreen(113, 2, 0); // unrelated surah, untouched by scoping

      store.clearSurahFromAyah(114, 2);

      expect(store.isGreen(114, 1, 0), isTrue,
          reason: 'ayah before startAyah is kept');
      expect(store.isGreen(114, 2, 0), isFalse,
          reason: 'ayah at/after startAyah is cleared');
      expect(store.completedAyahsFor(114), {1});
      expect(store.isGreen(113, 2, 0), isTrue,
          reason: 'a different surah must never be touched');
    });

    test('errorsFor returns the Tajweed errors attached by markGreenWordAsYellow', () {
      final store = SurahHighlightStore();
      final errors = [
        ReciterError(
          errorType: ErrorCategory.tajweed,
          speechErrorType: SpeechErrorType.replace,
          expectedPh: 'a',
          predictedPh: 'b',
          expectedRule: const NormalMaddRule(),
          durationStatus: TajweedDurationStatus.defect,
          expectedDuration: 0.4,
          actualDuration: 0.1,
        ),
      ];
      store.markGreen(114, 1, 0);
      store.markGreenWordAsYellow(114, 1, 0, errors);

      expect(store.errorsFor(114, 1, 0), errors);
      expect(store.errorsFor(114, 1, 1), isNull);
    });
  });
}
