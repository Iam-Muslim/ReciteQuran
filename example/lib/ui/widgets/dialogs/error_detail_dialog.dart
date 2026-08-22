import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../../state/app_state.dart';

/// Modal bottom sheet presenting an interactive, detailed breakdown
/// of Tajweed, Tashkeel, or phonetic pronunciation errors for a specific word.
class ErrorDetailDialog extends StatelessWidget {
  final String word;
  final List<ReciterError> errors;

  const ErrorDetailDialog({
    super.key,
    required this.word,
    required this.errors,
  });

  /// Static helper to display the modal bottom sheet cleanly.
  static void show(
    BuildContext context, {
    required String word,
    required List<ReciterError> errors,
  }) {
    if (errors.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ErrorDetailDialog(word: word, errors: errors),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
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
                    // ── Compact Header: Word & Error Count ──
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

                    // ── Error Cards Layout ──
                    ..._buildErrorCardsLayout(errors, c, isAr),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cleans phonetic markers to show readable Arabic characters.
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

  /// Returns action badge text for speech errors.
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

    String title;
    IconData? icon;
    Color accent;
    String desc;

    if (e.errorType == ErrorCategory.tajweed) {
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
          // ── Card Header ──
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

          // ── Card Body ──
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
}
