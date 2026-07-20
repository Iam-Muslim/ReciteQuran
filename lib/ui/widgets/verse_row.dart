// Displays a single Quranic verse (ayah) with word-by-word highlighting.
//
// Uses fingerprint-based diffing for near-zero CPU usage:
// - Listens to BOTH [HighlightingController] AND [AppState]
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
import 'package:flutter/gestures.dart';
import '../../state/app_state.dart';
import '../../data/quran_data.dart';
import '../../tracking/word/highlighting_controller.dart';
import '../../tracking/tajweed/error_explainer.dart';

class VerseRow extends StatefulWidget {
  final QuranVerse verse;
  final WebHighlightingController controller;
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
  late String _ayahArabicDigits;
  bool _isListeningToController = false;
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

  final List<TapGestureRecognizer> _recognizers = [];
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
    // Always trigger a check when active ayah changes to apply or clear active styles
    _onStateChanged();
  }

  void _updateSubscription() {
    final int? active = widget.controller.activeAyah.value;
    final int myAyah = widget.verse.ayah;
    // We should listen to 60fps highlights ONLY if we are the active ayah,
    // or if we are the immediately previous ayah (to catch the final completion frames).
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
    if (isActive) {
      hash = hash * 31 + (ctrl.activeWordIndex ?? -1);
    }
    // Hash green/red/yellow word sets for this ayah.
    final wordCount = widget.verse.uthmaniWords.length;
    for (int i = 0; i < wordCount; i++) {
      final cIdx = i;
      if (cIdx >= 0) {
        if (ctrl.isWordGreen(ayah, cIdx)) hash = hash * 31 + (i + 1) * 7;
        if (ctrl.isWordRed(ayah, cIdx)) hash = hash * 31 + (i + 1) * 13;
        if (ctrl.isWordYellow(ayah, cIdx)) hash = hash * 31 + (i + 1) * 17;
      }
    }
    // AppState properties — triggers rebuild on any UI setting change
    hash = hash * 31 + (app.isBlurMode ? 1 : 0);
    hash = hash * 31 + (app.isBlurMode && widget.isAutoScrolling ? 1 : 0);
    hash = hash * 31 + app.fontSize.hashCode;
    hash = hash * 31 + 0;
    hash = hash * 31 + app.theme.index;
    return hash;
  }

  /// Determines the color for word at UI index [i].
  Color _getColor(int i, ThemeColors c, AppState app) {
    final cIdx = i;
    if (cIdx < 0) return c.text;
    if (widget.controller.isWordGreen(widget.verse.ayah, cIdx)) return c.green;
    if (widget.controller.isWordRed(widget.verse.ayah, cIdx)) return c.red;
    if (widget.controller.isWordYellow(widget.verse.ayah, cIdx))
      return c.currentWord; // Tajweed/Tashkeel warning color
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

  void _showWordError(int ayah, int wordIdx, String word) {
    final errors = widget.controller.getWordErrors(ayah, wordIdx);
    if (errors == null || errors.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final c = AppState.instance.colors;
        final app = AppState.instance;
        final isAr = app.isArabic;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: c.gold.withValues(alpha: 0.08),
                blurRadius: 40,
                spreadRadius: 0,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Directionality(
            textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Handle Bar ──
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // ── Scrollable Content ──
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Compact Header: Word (Right) & Error Count (Left) ──
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: c.gold.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: c.gold.withValues(alpha: 0.15),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Right (in RTL): Small Uthmani Word
                              Text(
                                word,
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  fontFamily: 'HafsSmart',
                                  fontSize: 26,
                                  color: c.text,
                                  height: 1.3,
                                ),
                              ),
                              // Left (in RTL): Number of errors badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: c.red.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  errors.length == 1
                                      ? (isAr ? '1 خطأ' : '1 Error')
                                      : (isAr
                                            ? '${errors.length} أخطاء'
                                            : '${errors.length} Errors'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: c.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ── Error Cards Layout (Thumbnail Squares / Rectangles) ──
                        ..._buildErrorCardsLayout(errors, c, isAr),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Cleans phonetic markers to show readable Arabic
  static String _cleanPhonetic(String input) {
    return input
        .replaceAll('\u06e5', 'و')
        .replaceAll('\u06e6', 'ي')
        .replaceAll('\u06ba', 'ن')
        .replaceAll('\u06fe', 'م')
        .replaceAll('\u0687', '')
        .replaceAll('ڇ', '')
        .replaceAll('ۜ', '')
        .replaceAll('۪', '')
        .replaceAll('ؙ', '')
        .replaceAll('ٲ', 'أ')
        .replaceAll('\u0640', '');
  }

  /// Action badge text
  static String _actionBadge(SpeechErrorType type, bool isAr) {
    switch (type) {
      case SpeechErrorType.delete:
        return isAr ? 'حذف' : 'Skipped';
      case SpeechErrorType.insert:
        return isAr ? 'زيادة' : 'Added';
      case SpeechErrorType.replace:
        return isAr ? 'تبديل' : 'Changed';
    }
  }

  List<Widget> _buildErrorCardsLayout(
    List<ReciterError> errors,
    ThemeColors c,
    bool isAr,
  ) {
    if (errors.length == 1) {
      return [_buildErrorCard(errors[0], c, isAr, isCompact: false)];
    }
    List<Widget> rows = [];
    int i = 0;
    while (i < errors.length) {
      if (i + 1 < errors.length) {
        // Two cards in same row as squares/thumbnails
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildErrorCard(errors[i], c, isAr, isCompact: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildErrorCard(
                      errors[i + 1],
                      c,
                      isAr,
                      isCompact: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        i += 2;
      } else {
        // Last odd card taking the full width space as a rectangle
        rows.add(_buildErrorCard(errors[i], c, isAr, isCompact: false));
        i += 1;
      }
    }
    return rows;
  }

  Widget _buildErrorCard(
    ReciterError e,
    ThemeColors c,
    bool isAr, {
    bool isCompact = false,
  }) {
    final expected = e.expectedPh.isEmpty ? '—' : _cleanPhonetic(e.expectedPh);
    final predicted = e.predictedPh.isEmpty
        ? '—'
        : _cleanPhonetic(e.predictedPh);
    final bool isDurationErr =
        e.expectedDuration != null && e.actualDuration != null;

    // ── Determine category styling ──
    String title;
    IconData? icon;
    Color accent;
    String desc;

    if (e.errorType == ErrorCategory.tajweed) {
      // Tajweed rule error
      String ruleName = isAr
          ? (e.expectedRule?.name.ar ?? '')
          : (e.expectedRule?.name.en ?? '');
      if (ruleName.isEmpty) {
        ruleName = isAr ? 'حكم تجويد' : 'Tajweed Rule';
      }
      title = ruleName;
      icon = null;
      accent = const Color(0xFFDAA520);

      if (isDurationErr) {
        desc = (e.actualDuration! < e.expectedDuration!)
            ? (isAr ? 'يجب إطالة الصوت أكثر' : 'Hold the sound longer')
            : (isAr ? 'الصوت مطوّل أكثر من اللازم' : 'Sound held too long');
      } else {
        desc = isAr
            ? 'لم يتم تطبيق حكم التجويد بشكل صحيح'
            : 'Tajweed rule not applied correctly';
      }
    } else if (e.errorType == ErrorCategory.tashkeel) {
      title = isAr ? 'خطأ في التشكيل' : 'Vowel Mark Error';
      icon = Icons.spellcheck_rounded;
      accent = const Color(0xFF5B8DEF);
      desc = isAr
          ? 'الحركة المنطوقة تختلف عن الصحيحة'
          : 'Pronounced vowel differs from correct one';
    } else {
      if (e.speechErrorType == SpeechErrorType.insert) {
        title = isAr ? 'إضافة حرف زائد' : 'Extra Letter Added';
      } else {
        title = isAr ? 'خطأ في النطق' : 'Pronunciation Error';
      }
      icon = Icons.record_voice_over_rounded;
      accent = c.red;
      if (e.speechErrorType == SpeechErrorType.delete) {
        desc = isAr ? 'تم حذف هذا الحرف' : 'This letter was skipped';
      } else if (e.speechErrorType == SpeechErrorType.insert) {
        desc = isAr ? 'تم إضافة حرف زائد' : 'An extra letter was added';
      } else {
        desc = isAr ? 'تم نطق حرف مختلف' : 'A different letter was pronounced';
      }
    }

    return Container(
      margin: isCompact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 16,
              vertical: isCompact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: accent, size: isCompact ? 16 : 18),
                  SizedBox(width: isCompact ? 6 : 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: isCompact ? 2 : null,
                    overflow: isCompact ? TextOverflow.ellipsis : null,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: isCompact ? 13 : 15,
                    ),
                  ),
                ),
                if (e.errorType == ErrorCategory.normal) ...[
                  SizedBox(width: isCompact ? 4 : 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 6 : 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _actionBadge(e.speechErrorType, isAr),
                      style: TextStyle(
                        color: accent,
                        fontSize: isCompact ? 10 : 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Body ──
          Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 12 : 16,
              isCompact ? 10 : 12,
              isCompact ? 12 : 16,
              isCompact ? 12 : 14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description
                Text(
                  desc,
                  maxLines: isCompact ? 2 : null,
                  overflow: isCompact ? TextOverflow.ellipsis : null,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: isCompact ? 12 : 13,
                    height: isCompact ? 1.3 : 1.4,
                  ),
                ),
                SizedBox(height: isCompact ? 8 : 12),

                // Duration bar
                if (isDurationErr) ...[
                  _buildDurationBar(
                    e.expectedDuration!,
                    e.actualDuration!,
                    accent,
                    c,
                    isAr,
                    isCompact: isCompact,
                  ),
                  SizedBox(height: isCompact ? 8 : 12),
                ],

                // Phoneme comparison box or Original Letter box
                if (isDurationErr || e.errorType == ErrorCategory.tajweed) ...[
                  if (expected != '—' && expected.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isCompact ? 8 : 12),
                      decoration: BoxDecoration(
                        color: c.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: c.border.withValues(alpha: 0.25),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        expected,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: c.text,
                          fontSize: isCompact ? 24 : 28,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'HafsSmart',
                        ),
                      ),
                    ),
                ] else ...[
                  if (expected != '—' || predicted != '—')
                    Container(
                      padding: EdgeInsets.all(isCompact ? 8 : 12),
                      decoration: BoxDecoration(
                        color: c.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: c.border.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Expected
                          Expanded(
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: c.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        isAr ? 'الصواب' : 'Correct',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: c.green,
                                          fontSize: isCompact ? 10 : 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  expected,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                    color: c.text,
                                    fontSize: isCompact ? 20 : 24,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'HafsSmart',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Arrow
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 4 : 8,
                            ),
                            child: Icon(
                              isAr
                                  ? Icons.arrow_back_rounded
                                  : Icons.arrow_forward_rounded,
                              color: c.border,
                              size: isCompact ? 14 : 18,
                            ),
                          ),
                          // Predicted
                          Expanded(
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: c.red,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        isAr ? 'نطقك' : 'Yours',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: c.red,
                                          fontSize: isCompact ? 10 : 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  predicted,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                    color: c.text,
                                    fontSize: isCompact ? 20 : 24,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'HafsSmart',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationBar(
    double expected,
    double actual,
    Color accent,
    ThemeColors c,
    bool isAr, {
    bool isCompact = false,
  }) {
    double ratio = (actual / expected).clamp(0.0, 1.0);
    bool isTooShort = actual < expected;
    return Container(
      padding: EdgeInsets.all(isCompact ? 8 : 12),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isAr ? 'المدة' : 'Duration',
                style: TextStyle(
                  color: c.muted,
                  fontSize: isCompact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${actual.toStringAsFixed(2)}s',
                style: TextStyle(
                  color: isTooShort ? c.red : c.green,
                  fontSize: isCompact ? 11 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                ' / ${expected.toStringAsFixed(2)}s',
                style: TextStyle(
                  color: c.muted,
                  fontSize: isCompact ? 10 : 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 6 : 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: c.border.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Exact progress bar percentage (actual / expected)
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isTooShort
                            ? c.red.withValues(alpha: 0.7)
                            : c.green.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isCompact) ...[
            const SizedBox(height: 4),
            Text(
              isTooShort
                  ? (isAr ? 'أطِل الصوت أكثر ↑' : 'Hold sound longer ↑')
                  : (isAr ? 'الصوت أطول من اللازم ↓' : 'Sound too long ↓'),
              style: TextStyle(
                color: isTooShort
                    ? c.red.withValues(alpha: 0.7)
                    : accent.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the list of [InlineSpan]s for this verse's words.
  /// Only called when the fingerprint changes (cache miss).
  List<InlineSpan> _buildSpans(
    List<String> words,
    bool isActive,
    AppState app,
    ThemeColors c,
  ) {
    _disposeRecognizers();
    final List<InlineSpan> spans = [];
    final ctrl = widget.controller;
    final ayah = widget.verse.ayah;
    for (int i = 0; i < words.length; i++) {
      final cIdx = i;
      final isRead =
          cIdx >= 0 &&
          (ctrl.isWordGreen(ayah, cIdx) ||
              ctrl.isWordRed(ayah, cIdx) ||
              ctrl.isWordYellow(ayah, cIdx));
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
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (widget.isAutoScrolling) return;
          if (!isActive) {
            widget.onTap?.call();
          }
          // Show the word error regardless of previous active state since we just activated it
          // and errors are now persisted across ayah activations.
          if (ctrl.isWordYellow(ayah, cIdx)) {
            _showWordError(ayah, cIdx, words[i]);
          }
        };
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: words[i],
          style: TextStyle(
            fontFamily: 'HafsSmart',
            fontSize: app.fontSize,
            height: 2.6,
            wordSpacing: 5.0,
            color: color,
          ),
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

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.instance;
    final ThemeColors c = app.colors;
    final words = widget.verse.uthmaniWords;
    final activeMatch = widget.controller.currentMatchedVerse;
    final bool hasAnyActive = activeMatch != null;
    final bool isActive =
        hasAnyActive &&
        activeMatch.verse.surah == widget.verse.surah &&
        activeMatch.verse.ayah == widget.verse.ayah;
    // Use cached spans if available, otherwise build them
    _cachedSpans ??= _buildSpans(words, isActive, app, c);
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
            RichText(
              textAlign: TextAlign.justify,
              textDirection: TextDirection.rtl,
              text: TextSpan(children: _cachedSpans),
            ),
            // ── Ayah Number Badge (bottom-end aligned) ──
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
