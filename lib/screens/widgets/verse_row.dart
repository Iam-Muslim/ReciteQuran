/// Displays a single Quranic verse (ayah) with word-by-word highlighting.
///
/// Uses fingerprint-based diffing for near-zero CPU usage:
/// - Listens to BOTH [LiveRecitationController] AND [AppState]
/// - Computes a compact hash of this verse's visual state
/// - Only rebuilds when THIS verse's fingerprint actually changes
/// - Caches the [TextSpan] list between rebuilds
///
/// Highlighting modes:
/// - Green/emerald: correctly recited word
/// - Red/rose: skipped or incorrect word
/// - Amber: the word currently being tracked
/// - Hidden (blur mode): unrecited words match background color
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
    final bool isActive = activeMatch != null &&
        activeMatch.verse.surah == surah &&
        activeMatch.verse.ayah == ayah;
    final bool isCompleted = ctrl.completedAyahs.contains(ayah);

    // Jenkins-style hash combining
    int hash = isActive ? 1 : 0;
    hash = hash * 31 + (isActive ? ctrl.currentWordIndex : 0);
    hash = hash * 31 + (isCompleted ? 1 : 0);

    // Hash green/red word sets for this ayah
    if (ctrl.isWordGreen(ayah, 0) || !isCompleted) {
      final wordCount = widget.verse.uthmaniWords.length;
      for (int i = 0; i < wordCount; i++) {
        if (ctrl.isWordGreen(ayah, i)) hash = hash * 31 + (i + 1) * 7;
        if (ctrl.isWordRed(ayah, i)) hash = hash * 31 + (i + 1) * 13;
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

  /// Determines the color for word at index [i].
  Color _getColor(int i, ThemeColors c, AppState app) {
    if (app.mistakeLevel == MistakeLevel.none) {
      if (widget.controller.isWordGreen(widget.verse.ayah, i)) return c.gold;
      return c.text;
    }

    if (widget.controller.isWordGreen(widget.verse.ayah, i)) return c.green;
    if (widget.controller.isWordRed(widget.verse.ayah, i)) return c.red;

    return c.text;
  }

  /// Converts an integer to Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩).
  String _toArabicDigits(int number) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number.toString().split('').map((e) => digits[int.parse(e)]).join('');
  }

  /// Builds the list of [TextSpan]s for this verse's words.
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
      final isCurrent = isActive && i == ctrl.currentWordIndex;
      final isRead = ctrl.isWordGreen(ayah, i) ||
          ctrl.isWordRed(ayah, i) ||
          (isActive && i < ctrl.currentWordIndex);

      // Zero-GPU blur: unrecited words match background color (invisible).
      // Words "materialize" instantly when highlighted green/red/amber.
      final isHidden =
          app.isBlurMode && !isRead && !isCurrent && !widget.isAutoScrolling;

      // Current word uses distinct amber color (no underline = no diacritic collision)
      final Color color;
      if (isHidden) {
        color = c.bg;
      } else if (isCurrent) {
        color = c.currentWord;
      } else {
        color = _getColor(i, c, app);
      }

      spans.add(TextSpan(
        text: words[i],
        style: TextStyle(
          fontFamily: 'QPC_Hafs',
          fontSize: app.fontSize,
          height: 2.4,
          wordSpacing: 6.0,
          color: color,
        ),
      ));

      // Word separator
      if (i < words.length - 1) {
        spans.add(TextSpan(
          text: ' ',
          style: TextStyle(
            fontFamily: 'QPC_Hafs',
            fontSize: app.fontSize,
            height: 1.8,
          ),
        ));
      }
    }

    // Inline ayah number — plain Arabic digits with generous spacing
    spans.add(TextSpan(
      text: '       ${_toArabicDigits(widget.verse.ayah)}',
      style: TextStyle(
        fontFamily: '',
        fontSize: app.fontSize * 0.38,
        color: c.muted.withValues(alpha: 0.35),
        height: 2.4,
      ),
    ));

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.instance;
    final ThemeColors c = app.colors;
    final words = widget.verse.uthmaniWords;

    final activeMatch = widget.controller.currentMatchedVerse;
    final bool isActive = activeMatch != null &&
        activeMatch.verse.surah == widget.verse.surah &&
        activeMatch.verse.ayah == widget.verse.ayah;

    // Use cached spans if available, otherwise build them
    _cachedSpans ??= _buildSpans(words, isActive, app, c);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? c.gold.withValues(alpha: 0.03) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          // Always apply border (transparent when inactive) to prevent layout shift
          border: Border(
            right: BorderSide(
              color: isActive ? c.gold.withValues(alpha: 0.5) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: RichText(
          textAlign: TextAlign.justify,
          textDirection: TextDirection.rtl,
          text: TextSpan(children: _cachedSpans),
        ),
      ),
    );
  }
}
