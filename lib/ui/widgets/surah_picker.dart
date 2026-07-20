import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../tracking/word/highlighting_controller.dart';
import '../../data/quran_data.dart';

/// Surah Picker — full-screen bottom sheet with search.
///
/// Design principles:
/// - Clean list with large touch targets (64px rows)
/// - Search field always visible at top
/// - Current surah highlighted with warm gold
/// - Arabic calligraphy font for surah names
/// - Voice search mic button for hands-free navigation
class SurahPickerSheet extends StatefulWidget {
  final int current;
  final void Function(int surah, {int? ayah}) onPick;
  final WebHighlightingController controller;
  final bool isRecording;
  final bool isVoiceSearching;
  final VoidCallback onToggleRecord;
  final VoidCallback onVoiceSearchToggle;

  const SurahPickerSheet({
    super.key,
    required this.current,
    required this.onPick,
    required this.controller,
    required this.isRecording,
    required this.isVoiceSearching,
    required this.onToggleRecord,
    required this.onVoiceSearchToggle,
  });

  @override
  State<SurahPickerSheet> createState() => _SurahPickerSheetState();
}

class _SurahPickerSheetState extends State<SurahPickerSheet> {
  String _query = '';
  late final List<QuranVerse> _surahs;
  late final List<String> _normalizedNames;
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    // Dynamically load from JSON repository instead of hardcoded lists
    _surahs = widget.controller.repository.surahMetadata;
    _normalizedNames = _surahs
        .map((s) => s.surahName)
        .toList();
  }

  String _toArabicDigits(int number) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number
        .toString()
        .split('')
        .map((e) => digits[int.parse(e)])
        .join('');
  }

  String _normalizeArabic(String text) {
    final RegExp diacritics = RegExp(r'[\u064B-\u065F\u0670]');
    String normalized = text.replaceAll(diacritics, '');
    
    // Normalize alifs
    normalized = normalized.replaceAll(RegExp(r'[أإآٱ]'), 'ا');
    // Normalize taa marbutah
    normalized = normalized.replaceAll('ة', 'ه');
    // Normalize alif maqsura
    normalized = normalized.replaceAll('ى', 'ي');
    // Normalize hamza forms
    normalized = normalized.replaceAll('ؤ', 'و');
    normalized = normalized.replaceAll('ئ', 'ي');
    
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final ThemeColors c = app.colors;

    final normQuery = _normalizeArabic(_query);

    final List<int> items = [];
    for (int i = 0; i < _surahs.length; i++) {
      if (_query.isEmpty ||
          _normalizeArabic(_normalizedNames[i]).contains(normQuery) ||
          _surahs[i].surahNameEn.toLowerCase().contains(_query.toLowerCase()) ||
          '${i + 1}'.contains(_query)) {
        items.add(i);
      }
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrolled && ctrl.hasClients && _query.isEmpty) {
            _scrolled = true;
            double offset =
                (widget.current - 1) * 72.0; // Estimated tile height
            if (offset > ctrl.position.maxScrollExtent) {
              offset = ctrl.position.maxScrollExtent;
            }
            ctrl.jumpTo(offset);
          }
        });

        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: c.gold.withValues(alpha: 0.06),
                blurRadius: 40,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Directionality(
            textDirection: app.isArabic
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Column(
              children: [
                const SizedBox(height: 12),

                // ── Handle ──
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),



                // ── Search + Voice Search ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      // Search Field
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: c.surfaceHigh.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: c.border.withValues(alpha: 0.3),
                            ),
                          ),
                          child: TextField(
                            onChanged: (v) => setState(() => _query = v),
                            style: TextStyle(
                              color: c.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: app.isArabic
                                  ? 'ابحث'
                                  : 'Search...',
                              hintStyle: TextStyle(
                                color: c.muted,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: c.gold,
                                size: 20,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Voice Search Button
                      GestureDetector(
                        onTap: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.pop(context);
                          }
                          widget.onVoiceSearchToggle();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          height: 50,
                          decoration: BoxDecoration(
                            color: widget.isVoiceSearching
                                ? c.gold
                                : c.surfaceHigh.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: widget.isVoiceSearching
                                  ? c.gold
                                  : c.border.withValues(alpha: 0.3),
                            ),
                            boxShadow: widget.isVoiceSearching
                                ? [
                                    BoxShadow(
                                      color: c.gold.withValues(alpha: 0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    )
                                  ]
                                : [],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.isVoiceSearching
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                                color: widget.isVoiceSearching
                                    ? Colors.white
                                    : c.gold,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                app.isArabic ? 'بحث بالصوت' : 'Voice Search',
                                style: TextStyle(
                                  color: widget.isVoiceSearching ? Colors.white : c.text,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),



                // ── Surah List ──
                Expanded(
                  child: ListView.builder(
                    controller: ctrl,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 32, top: 4),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final int idx = items[i];
                      final int sNum = idx + 1;
                      final bool sel = widget.current == sNum;
                      final QuranVerse surahMeta = _surahs[idx];

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: GestureDetector(
                          onTap: () => widget.onPick(sNum),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: sel
                                  ? c.gold.withValues(alpha: 0.1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: sel
                                    ? c.gold.withValues(alpha: 0.3)
                                    : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                // ── Number Badge ──
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? c.gold
                                        : c.surfaceHigh,
                                    borderRadius: BorderRadius.circular(14),
                                    border: sel
                                        ? null
                                        : Border.all(
                                            color: c.border.withValues(alpha: 0.3),
                                          ),
                                  ),
                                  alignment: Alignment.center,
                                  child: sel
                                      ? const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        )
                                      : Text(
                                          app.isArabic
                                              ? _toArabicDigits(sNum)
                                              : '$sNum',
                                          style: TextStyle(
                                            color: c.muted,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 14),

                                // ── Surah Names ──
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: app.isArabic
                                        ? CrossAxisAlignment.start
                                        : CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        surahMeta.surahName,
                                        textDirection: TextDirection.rtl,
                                        style: TextStyle(
                                          fontFamily: 'HafsSmart',
                                          color: sel ? c.gold : c.text,
                                          fontSize: 18,
                                          fontWeight: sel
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      if (!app.isArabic) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          surahMeta.surahNameEn,
                                          style: TextStyle(
                                            color: c.muted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // ── Arrow ──
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: sel
                                      ? c.gold
                                      : c.border,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
