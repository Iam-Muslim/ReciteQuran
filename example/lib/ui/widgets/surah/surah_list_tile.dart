import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../../state/app_state.dart';

/// Single interactive row tile for a Surah in the picker sheet.
class SurahListTile extends StatelessWidget {
  final int surahNumber;
  final QuranVerse surahMeta;
  final bool isSelected;
  final VoidCallback onTap;

  const SurahListTile({
    super.key,
    required this.surahNumber,
    required this.surahMeta,
    required this.isSelected,
    required this.onTap,
  });

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
    final app = AppState.instance;
    final c = app.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? c.gold.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
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
                  color: isSelected ? c.gold : c.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: isSelected
                      ? null
                      : Border.all(color: c.border.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 20,
                      )
                    : Text(
                        app.isArabic
                            ? _toArabicDigits(surahNumber)
                            : '$surahNumber',
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      surahMeta.surahName,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: 'HafsSmart',
                        color: isSelected ? c.gold : c.text,
                        fontSize: 18,
                        fontWeight: isSelected
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
                color: isSelected ? c.gold : c.border,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
