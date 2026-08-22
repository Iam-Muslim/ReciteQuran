import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../state/app_state.dart';
import 'dialogs/error_detail_dialog.dart';
import 'helpers/verse_span_builder.dart';
import 'tajweed_tutorial_word.dart';

/// Displays a single Quranic verse (Ayah) with word-by-word highlighting.
///
/// Features:
/// - Fingerprint-based diffing for near-zero CPU / 60 FPS scrolling.
/// - Selective listener attachment (only active + adjacent Ayahs subscribe to ASR frames).
/// - Modular TextSpan rendering via [VerseSpanBuilder].
/// - Interactive Tajweed error breakdown via [ErrorDetailDialog].
class VerseRow extends StatefulWidget {
  final QuranVerse verse;
  final HighlightingController controller;
  final bool isAutoScrolling;
  final VoidCallback? onTap;
  final VoidCallback? onWordErrorTap;

  const VerseRow({
    super.key,
    required this.verse,
    required this.controller,
    required this.isAutoScrolling,
    this.onTap,
    this.onWordErrorTap,
  });

  @override
  State<VerseRow> createState() => _VerseRowState();
}

class _VerseRowState extends State<VerseRow> {
  /// Cached fingerprint — only rebuilds when visual state changes.
  int _lastFingerprint = -1;

  /// Cached TextSpan list — avoids re-allocating on every build.
  List<InlineSpan>? _cachedSpans;
  late String _ayahArabicDigits;
  bool _isListeningToController = false;

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _ayahArabicDigits = _toArabicDigits(widget.verse.ayah);
    widget.controller.activeAyah.addListener(_onActiveAyahChanged);
    widget.controller.globalRevision.addListener(_onStateChanged);
    AppState.instance.addListener(_onStateChanged);
    _updateSubscription();
  }

  @override
  void didUpdateWidget(VerseRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.activeAyah.removeListener(_onActiveAyahChanged);
      oldWidget.controller.globalRevision.removeListener(_onStateChanged);
      if (_isListeningToController) {
        oldWidget.controller.removeListener(_onStateChanged);
      }
      widget.controller.activeAyah.addListener(_onActiveAyahChanged);
      widget.controller.globalRevision.addListener(_onStateChanged);
      _isListeningToController = false;
      _updateSubscription();
      _invalidate();
    }
    if (oldWidget.isAutoScrolling != widget.isAutoScrolling) {
      if (AppState.instance.isBlurMode) {
        _invalidate();
      }
    }
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    widget.controller.activeAyah.removeListener(_onActiveAyahChanged);
    widget.controller.globalRevision.removeListener(_onStateChanged);
    if (_isListeningToController) {
      widget.controller.removeListener(_onStateChanged);
    }
    AppState.instance.removeListener(_onStateChanged);
    _disposeRecognizers();
    super.dispose();
  }

  void _onActiveAyahChanged() {
    _updateSubscription();
    _onStateChanged();
  }

  void _updateSubscription() {
    final int? active = widget.controller.activeAyah.value;
    final int myAyah = widget.verse.ayah;

    // Listen to 60fps highlights ONLY if we are the active or preceding Ayah
    bool shouldListen = false;
    if (active != null) {
      if (myAyah == active || myAyah == active - 1) {
        shouldListen = true;
      }
    }
    if (shouldListen && !_isListeningToController) {
      widget.controller.addListener(_onStateChanged);
      _isListeningToController = true;
    } else if (!shouldListen && _isListeningToController) {
      widget.controller.removeListener(_onStateChanged);
      _isListeningToController = false;
    }
  }

  void _invalidate() {
    _lastFingerprint = -1;
    _cachedSpans = null;
  }

  void _onStateChanged() {
    final fp = _computeFingerprint();
    if (fp != _lastFingerprint) {
      _lastFingerprint = fp;
      _cachedSpans = null;
      setState(() {});
    }
  }

  /// Compact hash representing active state, word colors, blur, theme, and font size.
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

    int hash = isActive ? 1 : 0;
    hash = hash * 31 + (isCompleted ? 1 : 0);

    final wordCount = widget.verse.uthmaniWords.length;
    for (int i = 0; i < wordCount; i++) {
      if (ctrl.isWordGreen(ayah, i)) hash = hash * 31 + (i + 1) * 7;
      if (ctrl.isWordRed(ayah, i)) hash = hash * 31 + (i + 1) * 13;
      if (ctrl.isWordYellow(ayah, i)) hash = hash * 31 + (i + 1) * 17;
    }

    hash = hash * 31 + (app.isBlurMode ? 1 : 0);
    hash = hash * 31 + (app.isBlurMode && widget.isAutoScrolling ? 1 : 0);
    hash = hash * 31 + app.fontSize.hashCode;
    hash = hash * 31 + app.theme.index;
    hash = hash * 31 + (app.hasClickedTajweedWord ? 1 : 0);
    return hash;
  }

  void _handleWordErrorTap(int ayah, int wordIdx, String word) {
    AppState.instance.markTajweedWordClicked();
    final errors = widget.controller.getWordErrors(ayah, wordIdx);
    if (errors != null && errors.isNotEmpty) {
      ErrorDetailDialog.show(context, word: word, errors: errors);
      widget.onWordErrorTap?.call();
    }
  }

  static String _toArabicDigits(int number) {
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
    final words = widget.verse.uthmaniWords;
    final activeMatch = widget.controller.currentMatchedVerse;
    final bool isActive =
        activeMatch != null &&
        activeMatch.verse.surah == widget.verse.surah &&
        activeMatch.verse.ayah == widget.verse.ayah;

    if (_cachedSpans == null) {
      _disposeRecognizers();
      _cachedSpans = VerseSpanBuilder.buildSpans(
        words: words,
        ayah: widget.verse.ayah,
        isActive: isActive,
        isAutoScrolling: widget.isAutoScrolling,
        controller: widget.controller,
        app: app,
        colors: c,
        recognizersSink: _recognizers,
        onVerseTap: widget.onTap,
        onWordErrorTap: _handleWordErrorTap,
      );
    }

    return GestureDetector(
      onTap: widget.isAutoScrolling ? null : widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? c.gold.withValues(alpha: 0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? c.gold.withValues(alpha: 0.18)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Verse Text ──
            CustomPaint(
              foregroundPainter: _cachedSpans != null
                  ? TajweedTooltipPainter(
                      words: words,
                      ayah: widget.verse.ayah,
                      controller: widget.controller,
                      app: app,
                      cachedSpans: _cachedSpans!,
                    )
                  : null,
              child: RichText(
                textAlign: TextAlign.justify,
                textDirection: TextDirection.rtl,
                text: TextSpan(children: _cachedSpans),
              ),
            ),

            // ── Ayah Number Badge ──
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                child: Text(
                  _ayahArabicDigits,
                  style: TextStyle(
                    fontFamily: 'HafsSmart',
                    fontSize: app.fontSize * 0.75,
                    fontWeight: FontWeight.w600,
                    color: isActive ? c.gold : c.muted.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
