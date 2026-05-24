import 'package:flutter/material.dart';
import 'dart:ui';
import '../../core/app_state.dart';
import '../../data/models/quran_data.dart';
import '../../recording/live_recitation_controller.dart';

class VerseRow extends StatelessWidget {
  final QuranVerse verse;
  final LiveRecitationController controller;
  final bool isAutoScrolling;
  final VoidCallback? onTap;

  const VerseRow({
    super.key,
    required this.verse,
    required this.controller,
    required this.isAutoScrolling,
    this.onTap,
  });

  List<String> get _words =>
      verse.textUthmani.split(" ").where((w) => w.isNotEmpty).toList();

  Color _getColor(int i, ThemeColors c, AppState app) {
    Color defaultColor = app.isDarkMode ? Colors.white : Colors.black;

    if (app.mistakeLevel == MistakeLevel.none) {
      if (controller.isWordGreen(verse.ayah, i)) return c.gold;
      return defaultColor;
    }

    if (controller.isWordGreen(verse.ayah, i)) return c.green;
    if (controller.isWordRed(verse.ayah, i)) return c.red;

    return defaultColor;
  }

  String _toArabicDigits(int number) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number
        .toString()
        .split('')
        .map((e) => digits[int.parse(e)])
        .join('');
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.instance;
    final ThemeColors c = app.colors;

    final allWords = _words;
    final wordsToDisplay = allWords;
    final int indexOffset = 0;

    // PERFORMANCE FIX: Only this specific verse listens to the AI engine!
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // NEW: The row independently decides if it is active based on the controller!
        final activeMatch = controller.currentMatchedVerse;
        final bool isActive =
            activeMatch != null &&
            activeMatch.verse.surah == verse.surah &&
            activeMatch.verse.ayah == verse.ayah;

        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? c.gold.withValues(alpha: 0.05)
                  : c.surface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? c.gold.withValues(alpha: 0.4)
                    : c.border.withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: c.gold.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Ayah number badge ───────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? c.gold.withValues(alpha: 0.15)
                              : c.surfaceHigh,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 4),
                            Text(
                              'آية ${_toArabicDigits(verse.ayah)}',
                              style: TextStyle(
                                color: isActive ? c.gold : c.muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                fontFamily: '',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Word-by-word text ───────────────────────────────────────────
                  RichText(
                    textAlign: TextAlign.justify,
                    textDirection: TextDirection.rtl,
                    text: TextSpan(
                      children: List.generate(wordsToDisplay.length, (i) {
                        final engineIndex = i + indexOffset;
                        final isCurrent =
                            isActive &&
                            engineIndex == controller.currentWordIndex;
                        final isRead = controller.isWordGreen(verse.ayah, engineIndex) ||
                            controller.isWordRed(verse.ayah, engineIndex) ||
                            (isActive && engineIndex < controller.currentWordIndex);
                        
                        final isBlurred =
                            app.isBlurMode &&
                            !isRead &&
                            !isAutoScrolling; // Disabled during auto-scroll

                        final targetStyle = TextStyle(
                          fontFamily: 'ScheherazadeNew',
                          fontSize: app.fontSize,
                          height: 2.8,
                          wordSpacing: 8.0,
                          color: _getColor(engineIndex, c, app),
                          fontWeight: app.fontWeight,
                        );

                        final blurredStyle = targetStyle.copyWith(
                          color: Colors.transparent,
                          shadows: [
                            Shadow(
                              color: c.muted.withValues(alpha: 0.9),
                              blurRadius: 16,
                            ),
                          ],
                        );

                        return <InlineSpan>[
                          TextSpan(
                            text: wordsToDisplay[i],
                            style: isCurrent
                                ? (isBlurred ? blurredStyle : targetStyle).copyWith(
                                    backgroundColor: c.gold.withValues(alpha: 0.25),
                                  )
                                : (isBlurred ? blurredStyle : targetStyle),
                          ),
                          if (i < wordsToDisplay.length - 1)
                            TextSpan(
                              text: ' ',
                              style: TextStyle(
                                fontFamily: 'ScheherazadeNew',
                                fontSize: app.fontSize,
                                height: 1.8,
                                fontWeight: app.fontWeight,
                              ),
                            ),
                        ];
                      }).expand((e) => e).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
