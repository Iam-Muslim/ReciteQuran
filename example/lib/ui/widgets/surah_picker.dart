import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../state/app_state.dart';
import 'surah/surah_list_tile.dart';

/// Surah Picker modal bottom sheet with search and voice navigation.
class SurahPickerSheet extends StatefulWidget {
  final int current;
  final void Function(int surah, {int? ayah}) onPick;
  final HighlightingController controller;
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
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _surahs = widget.controller.repository.surahMetadata;
    _normalizedNames = _surahs.map((s) => s.surahName).toList();
  }

  String _normalizeArabic(String text) {
    final RegExp diacritics = RegExp(r'[\u064B-\u065F\u0670]');
    String normalized = text.replaceAll(diacritics, '');
    normalized = normalized.replaceAll(RegExp(r'[أإآٱ]'), 'ا');
    normalized = normalized.replaceAll('ة', 'ه');
    normalized = normalized.replaceAll('ى', 'ي');
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrolled && _scrollCtrl.hasClients && _query.isEmpty) {
        _scrolled = true;
        double offset = (widget.current - 1) * 90.0;
        if (offset > _scrollCtrl.position.maxScrollExtent) {
          offset = _scrollCtrl.position.maxScrollExtent;
        }
        _scrollCtrl.jumpTo(offset);
      }
    });

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Container(
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
                              hintText: app.isArabic ? 'ابحث' : 'Search...',
                              hintStyle: TextStyle(color: c.muted),
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
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
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
                                        ),
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
                                      color: widget.isVoiceSearching
                                          ? Colors.white
                                          : c.text,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: -24,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.gold,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                app.isArabic ? 'اضغط للبحث بالصوت' : 'Tap to voice search',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
            ),
            const SizedBox(height: 12),

                // ── Surah List ──
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    itemExtent: 90.0,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 32, top: 4),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final int idx = items[i];
                      final int sNum = idx + 1;
                      final bool isSel = widget.current == sNum;
                      final QuranVerse surahMeta = _surahs[idx];

                      return SurahListTile(
                        surahNumber: sNum,
                        surahMeta: surahMeta,
                        isSelected: isSel,
                        onTap: () => widget.onPick(sNum),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }
}
