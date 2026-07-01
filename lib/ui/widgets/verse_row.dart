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

class VerseRow extends StatefulWidget {
  final QuranVerse verse;
  final HighlightingController controller;
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
    if (widget.controller.isWordYellow(widget.verse.ayah, cIdx)) return Colors.orange; // Tajweed/Tashkeel warning color
    

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
      backgroundColor: AppState.instance.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        final c = AppState.instance.colors;
        final app = AppState.instance;
        final isAr = app.isArabic;

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: Directionality(
            textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
            child: Scrollbar(
              thumbVisibility: true,
              thickness: 4,
              radius: const Radius.circular(4),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 48),
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // The Uthmani Word
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: c.gold.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.gold.withValues(alpha: 0.2)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    word,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: 'HafsSmart',
                      fontSize: app.fontSize * 1.2,
                      color: c.text,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                Text(isAr ? 'تفاصيل الخطأ' : 'Error Details', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.text)),
                const SizedBox(height: 16),
                
                ...errors.map((e) {
                  String cleanPhoneticString(String input) {
                    return input
                        .replaceAll('\u06e5', 'و') // Small waw -> waw
                        .replaceAll('\u06e6', 'ي') // Small yaa -> yaa
                        .replaceAll('\u06ba', 'ن') // Noon mokhfah -> noon
                        .replaceAll('\u06fe', 'م') // Meem mokhfah -> meem
                        .replaceAll('\u0687', '')  // Qalqalah/Waqf marker
                        .replaceAll('ڇ', '')       // Qalqalah bounce phonetic marker
                        .replaceAll('ۜ', '')       // Sakt marker
                        .replaceAll('۪', '')       // Imala marker
                        .replaceAll('ؙ', '')       // Tasheel/Ishmam marker
                        .replaceAll('ٲ', 'أ');     // Alif wavy hamza -> Alif
                  }

                  final String expected = e.expectedPh.isEmpty ? '(none)' : cleanPhoneticString(e.expectedPh);
                  final String predicted = e.predictedPh.isEmpty ? '(none)' : cleanPhoneticString(e.predictedPh);
                  
                  String explanation = '';
                  String title = '';
                  IconData icon;
                  Color iconColor;

                  if (e.errorType.toString().contains('tajweed')) {
                    title = isAr ? 'مخالفة حكم تجويد' : 'Tajweed Rule Violation';
                    icon = Icons.menu_book_rounded;
                    iconColor = Colors.orange;
                    String ruleName = isAr 
                        ? (e.expectedRule?.name.ar ?? 'حكم تجويد')
                        : (e.expectedRule?.name.en ?? 'Tajweed rule');
                    if (ruleName.isEmpty && e.expectedRule?.name.ar != null) {
                        ruleName = e.expectedRule!.name.ar;
                    }
                    explanation = isAr
                        ? 'قرأت "$predicted"، ولكن كان يجب أن تقرأها بحكم "$ruleName" كـ "$expected" بالطريقة الصحيحة.'
                        : 'You recited "$predicted", but you should have recited it with "$ruleName" as "$expected" in the expected way.';
                  } else if (e.errorType.toString().contains('tashkeel')) {
                    title = isAr ? 'خطأ في الحركات' : 'Harakat (Vowel) Error';
                    icon = Icons.spellcheck_rounded;
                    iconColor = Colors.blue;
                    explanation = isAr
                        ? 'نطقت الحركة كـ "$predicted"، ولكن النطق الصحيح هو "$expected".'
                        : 'You pronounced the vowels as "$predicted", but the expected pronunciation is "$expected".';
                  } else {
                    title = isAr ? 'خطأ في النطق' : 'Pronunciation Error';
                    icon = Icons.record_voice_over_rounded;
                    iconColor = c.red;
                    explanation = isAr
                        ? 'قلت "$predicted"، ولكن كان يجب أن تقرأ "$expected".'
                        : 'You said "$predicted", but you should have recited "$expected".';
                  }

                  // Add hints for removed special phonetic markers so the user understands the context
                  bool hasSakt = e.expectedPh.contains('ۜ');
                  bool hasImala = e.expectedPh.contains('۪');
                  bool hasTasheel = e.expectedPh.contains('ؙ');
                  bool hasQalqalahMarker = e.expectedPh.contains('ڇ') || e.expectedPh.contains('\u0687');
                  
                  String specialHint = '';
                  if (hasSakt) specialHint += isAr ? '\n• يتطلب سكتة (توقف قصير بدون تنفس).' : '\n• Requires a Sakt (short breathless pause).';
                  if (hasImala) specialHint += isAr ? '\n• يتطلب إمالة (إمالة الفتحة نحو الكسرة).' : '\n• Requires Imala (inclining the vowel).';
                  if (hasTasheel) specialHint += isAr ? '\n• يتطلب تسهيل (تليين الهمزة).' : '\n• Requires Tasheel (softening of the Hamza).';
                  if (hasQalqalahMarker && !e.errorType.toString().contains('tajweed')) {
                    specialHint += isAr ? '\n• يتطلب قلقلة (صدى للصوت).' : '\n• Requires Qalqalah (echoing sound).';
                  }

                  if (specialHint.isNotEmpty) {
                    explanation += '\n$specialHint';
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.border.withValues(alpha: 0.5)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: iconColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: TextStyle(color: c.text, fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 4),
                              Text(explanation, style: TextStyle(color: c.muted, fontSize: 13, height: 1.4)),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: c.border.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Column(
                                      children: [
                                        Text(isAr ? 'المتوقع' : 'Expected', style: TextStyle(color: c.muted, fontSize: 11)),
                                        Text(expected, style: TextStyle(color: c.green, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'HafsSmart')),
                                      ],
                                    ),
                                    Container(width: 1, height: 32, color: c.border.withValues(alpha: 0.3)),
                                    Column(
                                      children: [
                                        Text(isAr ? 'قلت' : 'You Said', style: TextStyle(color: c.muted, fontSize: 11)),
                                        Text(predicted, style: TextStyle(color: c.red, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'HafsSmart')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
              ),
            ),
          ),
        );
      }
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
      final isActiveWord = isActive && ctrl.activeWordIndex == cIdx;
      final isRead =
          cIdx >= 0 &&
          (ctrl.isWordGreen(ayah, cIdx) || ctrl.isWordRed(ayah, cIdx) || ctrl.isWordYellow(ayah, cIdx));

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

      final recognizer = TapGestureRecognizer()..onTap = () {
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
            height: 2.5,
            wordSpacing: 12.0,
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
              height: 2.5,
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
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? c.gold.withValues(alpha: 0.08) : Colors.transparent,
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
                _ayahArabicDigits,
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



