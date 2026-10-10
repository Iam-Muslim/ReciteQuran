import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../../state/app_state.dart';

/// Interactive modal dialog shown when voice search is actively listening.
/// Displays real-time speech transcription, live matching candidate Ayahs,
/// and allows instant tap-to-select for disambiguation.
class VoiceSearchDialog extends StatelessWidget {
  final VoidCallback onStop;
  final ValueNotifier<bool>? isLoading;
  final ValueNotifier<String>? asrTextNotifier;
  final ValueNotifier<VoiceSearchResult?>? searchResultNotifier;
  final void Function(int surah, int ayah)? onSelectCandidate;

  const VoiceSearchDialog({
    super.key,
    required this.onStop,
    this.isLoading,
    this.asrTextNotifier,
    this.searchResultNotifier,
    this.onSelectCandidate,
  });

  /// Static helper to display the voice search dialog cleanly.
  static void show(
    BuildContext context, {
    required VoidCallback onStop,
    ValueNotifier<bool>? isLoading,
    ValueNotifier<String>? asrTextNotifier,
    ValueNotifier<VoiceSearchResult?>? searchResultNotifier,
    void Function(int surah, int ayah)? onSelectCandidate,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => VoiceSearchDialog(
        onStop: onStop,
        isLoading: isLoading,
        asrTextNotifier: asrTextNotifier,
        searchResultNotifier: searchResultNotifier,
        onSelectCandidate: onSelectCandidate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isAr = app.isArabic;
    final media = MediaQuery.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: media.size.height * 0.78,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.gold.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: c.gold.withValues(alpha: 0.12),
              blurRadius: 36,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
            child: ValueListenableBuilder<bool>(
              valueListenable: isLoading ?? ValueNotifier(false),
              builder: (context, loading, _) {
                if (loading) {
                  return _buildLoadingState(c, isAr);
                }
                return _buildListeningContent(context, c, isAr);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeColors c, bool isAr) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(c.gold),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          isAr ? 'جاري تجهيز البحث الصوتي...' : 'Preparing voice search index...',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildListeningContent(
    BuildContext context,
    ThemeColors c,
    bool isAr,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Top Header Bar (Listening Indicator & Stop Button) ──
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.gold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mic_rounded, color: c.gold, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAr ? 'البحث الصوتي الفوري' : 'Live Voice Search',
                    style: TextStyle(
                      color: c.gold,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    isAr
                        ? 'اتلُ أي آية من القرآن الكريم'
                        : 'Recite any verse from the Quran',
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Stop button
            IconButton(
              icon: Icon(Icons.close_rounded, color: c.muted),
              tooltip: isAr ? 'إلغاء' : 'Cancel',
              onPressed: () {
                Navigator.of(context, rootNavigator: true).maybePop();
                onStop();
              },
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ── Live Speech Transcription Bubble ──
        if (asrTextNotifier != null)
          ValueListenableBuilder<String>(
            valueListenable: asrTextNotifier!,
            builder: (context, transcript, _) {
              final hasText = transcript.trim().isNotEmpty;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: hasText
                      ? c.gold.withValues(alpha: 0.08)
                      : c.bg.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasText
                        ? c.gold.withValues(alpha: 0.25)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasText ? Icons.record_voice_over_rounded : Icons.graphic_eq_rounded,
                      color: hasText ? c.gold : c.muted,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hasText
                            ? '« ${transcript.trim()} »'
                            : (isAr ? 'في انتظار تلاوتك...' : 'Listening to recitation...'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasText ? c.text : c.muted,
                          fontSize: 14,
                          fontWeight: hasText ? FontWeight.w600 : FontWeight.normal,
                          fontStyle: hasText ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

        const SizedBox(height: 14),

        // ── Live Candidate Results Stream ──
        if (searchResultNotifier != null)
          Flexible(
            child: ValueListenableBuilder<VoiceSearchResult?>(
              valueListenable: searchResultNotifier!,
              builder: (context, result, _) {
                if (result == null || result.candidates.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_stories_rounded,
                          size: 38,
                          color: c.muted.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isAr
                              ? 'استمر بالتلاوة للبحث في كامل المصحف (6,236 آية)...'
                              : 'Keep reciting to search across all 6,236 Ayahs...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final candidates = result.candidates;
                final isUnique = result.isUnique;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isUnique
                            ? Colors.green.withValues(alpha: 0.12)
                            : c.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isUnique
                                ? Icons.check_circle_outline_rounded
                                : Icons.travel_explore_rounded,
                            size: 16,
                            color: isUnique ? Colors.green : c.gold,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isUnique
                                  ? (isAr
                                      ? 'تم تحديد الآية بدقة! جاري الانتقال...'
                                      : 'Exact Ayah matched! Navigating...')
                                  : (isAr
                                      ? 'تطابق محتمل مع ${candidates.length} آيات (اختر أو تابع التلاوة):'
                                      : 'Matches ${candidates.length} Ayahs (tap or keep reciting):'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isUnique ? Colors.green : c.gold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Candidates list
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: candidates.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final match = candidates[index];
                          return _buildCandidateTile(
                            context,
                            match: match,
                            c: c,
                            isAr: isAr,
                            onTap: () {
                              Navigator.of(context, rootNavigator: true).maybePop();
                              onSelectCandidate?.call(match.surah, match.ayah);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCandidateTile(
    BuildContext context, {
    required AyahSearchMatch match,
    required ThemeColors c,
    required bool isAr,
    required VoidCallback onTap,
  }) {
    final title = isAr
        ? '${match.surahNameAr ?? 'سورة ${match.surah}'} — آية ${match.ayah}'
        : '${match.surahNameEn ?? 'Surah ${match.surah}'} — Ayah ${match.ayah}';

    final percentage = (match.score * 100).toInt();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: c.gold.withValues(alpha: 0.08),
        splashColor: c.gold.withValues(alpha: 0.15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.bg.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: c.gold.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: c.gold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: percentage >= 80
                                ? Colors.green.withValues(alpha: 0.15)
                                : c.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$percentage%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: percentage >= 80
                                  ? Colors.green
                                  : c.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (match.textUthmani != null && match.textUthmani!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        match.textUthmani!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'HafsSmart',
                          fontSize: 16,
                          color: c.text.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: c.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
