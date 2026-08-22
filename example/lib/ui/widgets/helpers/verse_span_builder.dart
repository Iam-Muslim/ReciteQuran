import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../../state/app_state.dart';

/// Pure helper for generating high-performance, styled [InlineSpan] lists for Quranic verses.
/// Handles zero-GPU blur hiding, color status resolution, and word gesture binding.
class VerseSpanBuilder {
  /// Resolves the foreground color for word at index [wordIndex].
  static Color resolveWordColor({
    required int ayah,
    required int wordIndex,
    required HighlightingController controller,
    required ThemeColors colors,
  }) {
    if (wordIndex < 0) return colors.text;
    if (controller.isWordGreen(ayah, wordIndex)) return colors.green;
    if (controller.isWordRed(ayah, wordIndex)) return colors.red;
    if (controller.isWordYellow(ayah, wordIndex)) return colors.currentWord;
    return colors.text;
  }

  /// Builds the complete list of [InlineSpan]s representing an Ayah's text.
  static List<InlineSpan> buildSpans({
    required List<String> words,
    required int ayah,
    required bool isActive,
    required bool isAutoScrolling,
    required HighlightingController controller,
    required AppState app,
    required ThemeColors colors,
    required List<TapGestureRecognizer> recognizersSink,
    required VoidCallback? onVerseTap,
    required void Function(int ayah, int wordIndex, String word) onWordErrorTap,
  }) {
    final List<InlineSpan> spans = [];

    for (int i = 0; i < words.length; i++) {
      final isRead =
          controller.isWordGreen(ayah, i) ||
          controller.isWordRed(ayah, i) ||
          controller.isWordYellow(ayah, i) ||
          controller.isWordNeutral(ayah, i);

      // Zero-GPU blur: unrecited words match background (transparent)
      final isHidden = app.isBlurMode && !isRead && !isAutoScrolling;
      final Color color = isHidden
          ? Colors.transparent
          : resolveWordColor(
              ayah: ayah,
              wordIndex: i,
              controller: controller,
              colors: colors,
            );

      final word = words[i];
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (isAutoScrolling) return;
          if (!isActive) {
            onVerseTap?.call();
          }
          if (controller.isWordYellow(ayah, i)) {
            onWordErrorTap(ayah, i, word);
          }
        };
      recognizersSink.add(recognizer);

      final style = TextStyle(
        fontFamily: 'HafsSmart',
        fontSize: app.fontSize,
        height: 2.6,
        wordSpacing: 5.0,
        color: color,
      );

      // ALWAYS add the word as a standard TextSpan!
      spans.add(
        TextSpan(
          text: word,
          style: style,
          recognizer: recognizer,
        ),
      );

      // Word separator
      if (i < words.length - 1) {
        spans.add(
          TextSpan(
            text: ' ',
            style: TextStyle(
              fontFamily: 'HafsSmart',
              fontSize: app.fontSize,
              height: 2.6,
              wordSpacing: 5.0,
            ),
          ),
        );
      }
    }

    return spans;
  }
}
