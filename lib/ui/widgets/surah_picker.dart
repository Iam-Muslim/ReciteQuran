import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../tracking/highlighting_controller.dart';
import '../../data/quran_data.dart';

class SurahPickerSheet extends StatefulWidget {
  final int current;
  final void Function(int surah, {int? ayah}) onPick;
  final HighlightingController controller;
  final bool isRecording;
  final VoidCallback onToggleRecord;

  const SurahPickerSheet({
    super.key,
    required this.current,
    required this.onPick,
    required this.controller,
    required this.isRecording,
    required this.onToggleRecord,
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

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final ThemeColors c = app.colors;

    final normQuery = _query;

    final List<int> items = [];
    for (int i = 0; i < _surahs.length; i++) {
      if (_query.isEmpty ||
          _normalizedNames[i].contains(normQuery) ||
          _surahs[i].surahNameEn.toLowerCase().contains(_query.toLowerCase()) ||
          '${i + 1}'.contains(_query)) {
        items.add(i);
      }
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.75,
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

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: Material(
            color: c.surface,
            child: Directionality(
              textDirection: app.isArabic
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Sleek Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.border.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Search field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            decoration: BoxDecoration(
                              color: c.surfaceHigh.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: c.border.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: TextField(
                              onChanged: (v) => setState(() => _query = v),
                              style: TextStyle(
                                color: app.isDarkMode
                                    ? Colors.white
                                    : Colors.black,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: (app.isArabic
                                    ? 'ابحث عن سورة...'
                                    : 'Search Surah...'),
                                hintStyle: TextStyle(
                                  color: c.muted,
                                  fontStyle: FontStyle.normal,
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Surah list
                  Expanded(
                    child: ListView.builder(
                      controller: ctrl,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 24, top: 8),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final int idx = items[i];
                        final int sNum = idx + 1;
                        final bool sel = widget.current == sNum;
                        final QuranVerse surahMeta = _surahs[idx];

                        final String displayName = app.isArabic
                            ? surahMeta.surahName
                            : "${surahMeta.surahNameEn} - ${surahMeta.surahName}";

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          child: GestureDetector(
                            onTap: () => widget.onPick(sNum),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: sel
                                    ? c.gold.withValues(alpha: 0.1)
                                    : c.surfaceHigh.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: sel
                                      ? c.gold.withValues(alpha: 0.5)
                                      : c.border.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                                boxShadow: sel
                                    ? [
                                        BoxShadow(
                                          color: c.gold.withValues(alpha: 0.05),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Row(
                                children: [
                                  // Leading Number / Icon
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: sel ? c.gold : c.surface,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: sel
                                            ? Colors.transparent
                                            : c.border.withValues(alpha: 0.3),
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
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Surah Name
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      textAlign: app.isArabic
                                          ? TextAlign.right
                                          : TextAlign.left,
                                      style: TextStyle(
                                        fontFamily: app.isArabic
                                            ? 'HafsSmart'
                                            : 'Inter',
                                        color: sel ? c.gold : c.text,
                                        fontSize: app.isArabic ? 18 : 16,
                                        fontWeight: sel
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                      ),
                                    ),
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
          ),
        );
      },
    );
  }
}
