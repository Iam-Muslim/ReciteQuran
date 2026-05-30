// Displays a single Quranic verse (ayah) with word-by-word highlighting.
//
// Uses fingerprint-based diffing for near-zero CPU usage:
// - Listens to BOTH [LiveRecitationController] AND [AppState]
// - Computes a compact hash of this verse's visual state
// - Only rebuilds when THIS verse's fingerprint actually changes
// - Caches the [TextSpan] list between rebuilds
//
// Highlighting modes:
// - Green/emerald: correctly recited word
// - Red/rose: skipped or incorrect word
// - Amber: the word currently being tracked
// - Hidden (blur mode): unrecited words match background color
import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../data/models/quran_data.dart';
import '../../recording/live_recitation_controller.dart';

class VerseRow extends StatefulWidget {
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

  @override
  State<VerseRow> createState() => _VerseRowState();
}

class _VerseRowState extends State<VerseRow> {
  /// Cached fingerprint — only rebuild when this changes.
  int _lastFingerprint = -1;

  /// Cached TextSpan list — avoids re-allocating on every build.
  List<InlineSpan>? _cachedSpans;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
    AppState.instance.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(VerseRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onStateChanged);
      widget.controller.addListener(_onStateChanged);
      _invalidate();
    }
    if (oldWidget.isAutoScrolling != widget.isAutoScrolling) {
      _invalidate();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    AppState.instance.removeListener(_onStateChanged);
    super.dispose();
  }

  /// Force cache invalidation.
  void _invalidate() {
    _lastFingerprint = -1;
    _cachedSpans = null;
  }

  /// Callback for both controller and AppState changes.
  /// Computes fingerprint and only triggers setState if it changed.
  void _onStateChanged() {
    final fp = _computeFingerprint();
    if (fp != _lastFingerprint) {
      _lastFingerprint = fp;
      _cachedSpans = null;
      setState(() {});
    }
  }

  /// Produces a compact hash of this verse's current visual state.
  /// Includes: active state, current word index, green/red sets,
  /// blur mode, font size, mistake level, and theme.
  int _computeFingerprint() {
    final ctrl = widget.controller;
    final app = AppState.instance;
    final ayah = widget.verse.ayah;
    final surah = widget.verse.surah;

    final activeMatch = ctrl.currentMatchedVerse;
    final bool isActive =
        activeMatch != null &&
        activeMatch.verse.surah == surah &&
        activeMatch.verse.ayah == ayah;
    final bool isCompleted = ctrl.completedAyahs.contains(ayah);

    // Jenkins-style hash combining
    int hash = isActive ? 1 : 0;
    hash = hash * 31 + (isCompleted ? 1 : 0);

    // Hash green/red word sets for this ayah.
    // Completed ayahs have frozen state — skip the word loop entirely.
    // This eliminates ~30 function calls per completed visible verse per cycle.
    if (isCompleted) {
      hash = hash * 31 + 999; // Stable constant — hash never changes
    } else {
      final wordCount = widget.verse.uthmaniWords.length;
      for (int i = 0; i < wordCount; i++) {
        final cIdx = widget.verse.uthmaniToCleanMap[i];
        if (cIdx >= 0) {
          if (ctrl.isWordGreen(ayah, cIdx)) hash = hash * 31 + (i + 1) * 7;
          if (ctrl.isWordRed(ayah, cIdx)) hash = hash * 31 + (i + 1) * 13;
        }
      }
    }

    // AppState properties — triggers rebuild on any UI setting change
    hash = hash * 31 + (app.isBlurMode ? 1 : 0);
    hash = hash * 31 + (widget.isAutoScrolling ? 1 : 0);
    hash = hash * 31 + app.fontSize.hashCode;
    hash = hash * 31 + app.mistakeLevel.index;
    hash = hash * 31 + app.theme.index;

    return hash;
  }

  /// Determines the color for word at UI index [i].
  Color _getColor(int i, ThemeColors c, AppState app) {
    final cIdx = widget.verse.uthmaniToCleanMap[i];
    if (cIdx < 0) return c.text;

    if (app.mistakeLevel == MistakeLevel.none) {
      if (widget.controller.isWordGreen(widget.verse.ayah, cIdx)) return c.gold;
      return c.text;
    }

    if (widget.controller.isWordGreen(widget.verse.ayah, cIdx)) return c.green;
    if (widget.controller.isWordRed(widget.verse.ayah, cIdx)) return c.red;

    return c.text;
  }

  /// Converts an integer to Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩).
  String _toArabicDigits(int number) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number
        .toString()
        .split('')
        .map((e) => digits[int.parse(e)])
        .join('');
  }

  /// Builds the list of [TextSpan]s for this verse's words.
  /// Only called when the fingerprint changes (cache miss).
  /// Builds the list of [InlineSpan]s for this verse's words.
  /// Only called when the fingerprint changes (cache miss).
  List<InlineSpan> _buildSpans(
    List<String> words,
    bool isActive,
    AppState app,
    ThemeColors c,
  ) {
    final List<InlineSpan> spans = [];
    final ctrl = widget.controller;
    final ayah = widget.verse.ayah;

    for (int i = 0; i < words.length; i++) {
      final cIdx = widget.verse.uthmaniToCleanMap[i];
      final isRead =
          cIdx >= 0 &&
          (ctrl.isWordGreen(ayah, cIdx) || ctrl.isWordRed(ayah, cIdx));

      // Zero-GPU blur: unrecited words match background color (invisible).
      // Words "materialize" instantly when highlighted green/red.
      final isHidden = app.isBlurMode && !isRead && !widget.isAutoScrolling;

      // Unmatched words use text color, matched use green/red
      final Color color;
      if (isHidden) {
        color = Colors.transparent;
      } else {
        color = _getColor(i, c, app);
      }

      spans.add(
        TextSpan(
          text: words[i],
          style: TextStyle(
            fontFamily: 'HafsSmart',
            fontSize: app.fontSize,
            height: 2.4,
            wordSpacing: 6.0,
            color: color,
          ),
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
              height: 1.8,
            ),
          ),
        );
      }
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.instance;
    final ThemeColors c = app.colors;
    final words = widget.verse.uthmaniWords;

    final activeMatch = widget.controller.currentMatchedVerse;
    final bool isActive =
        activeMatch != null &&
        activeMatch.verse.surah == widget.verse.surah &&
        activeMatch.verse.ayah == widget.verse.ayah;

    // Use cached spans if available, otherwise build them
    _cachedSpans ??= _buildSpans(words, isActive, app, c);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isActive ? 8 : 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? c.gold.withValues(alpha: 0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? c.gold.withValues(alpha: 0.2)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          textDirection: TextDirection.rtl,
          children: [
            Expanded(
              child: RichText(
                textAlign: TextAlign.justify,
                textDirection: TextDirection.rtl,
                text: TextSpan(children: _cachedSpans),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 16, bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? c.gold.withValues(alpha: 0.15)
                    : c.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? c.gold.withValues(alpha: 0.3)
                      : c.border.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Text(
                _toArabicDigits(widget.verse.ayah),
                style: TextStyle(
                  fontFamily: 'Inter', // Modern font for digits
                  fontSize: app.fontSize * 0.35,
                  fontWeight: FontWeight.w600,
                  color: isActive ? c.gold : c.muted.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
