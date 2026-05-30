// Settings bottom sheet — displays all user-configurable options.
//
// Content:
// - Language toggle (Arabic ↔ English)
// - Theme selector (Light / Dark)
// - Mistake checking level (None / Easy / Medium / Hard)
// - Lookahead words count (1-5)
// - Privacy policy link
//
// Uses a fixed-height [DraggableScrollableSheet] that fits its content
// without stretching or leaving empty space.
import 'package:flutter/material.dart';
import '../../core/app_state.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;

    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = app.colors;
        final isAr = app.isArabic;

        return DraggableScrollableSheet(
          initialChildSize: 0.52,
          maxChildSize: 0.52,
          minChildSize: 0.3,
          expand: false,
          builder: (_, ctrl) {
            return Container(
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Directionality(
                textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
                child: ListView(
                  controller: ctrl,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    // ── Handle ────────────────────────────────────────────
                    Center(
                      child: Container(
                        width: 32,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: c.border.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Title ─────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        isAr ? 'الإعدادات' : 'Settings',
                        style: TextStyle(
                          color: c.gold,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Language ──────────────────────────────────────────
                    _SettingTile(
                      title: isAr ? 'اللغة' : 'Language',
                      subtitle: isAr ? 'English' : 'العربية',
                      c: c,
                      trailing: Switch.adaptive(
                        value: !isAr,
                        onChanged: (_) => app.toggleLanguage(),
                        activeTrackColor: c.gold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Theme ────────────────────────────────────────────
                    _SectionLabel(title: isAr ? 'المظهر' : 'Theme', c: c),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _SegmentedSelector(
                        labels: isAr ? ['فاتح', 'داكن'] : ['Light', 'Dark'],
                        selected: app.theme.index,
                        c: c,
                        onSelected: (i) => app.setTheme(AppTheme.values[i]),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Mistake Level ────────────────────────────────────
                    _SectionLabel(
                      title: isAr ? 'مستوى التدقيق' : 'Mistake Checking',
                      c: c,
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _SegmentedSelector(
                        labels: isAr
                            ? ['بدون', 'سهل', 'متوسط', 'صعب']
                            : ['None', 'Easy', 'Medium', 'Hard'],
                        selected: app.mistakeLevel.index,
                        c: c,
                        onSelected: (i) =>
                            app.setMistakeLevel(MistakeLevel.values[i]),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Lookahead ────────────────────────────────────────
                    _SectionLabel(
                      title: isAr ? 'الكلمات المتتبعة' : 'Lookahead Words',
                      c: c,
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _SegmentedSelector(
                        labels: ['1', '2', '3', '4', '5'],
                        selected: app.lookahead - 1,
                        c: c,
                        onSelected: (i) => app.setLookahead(i + 1),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Footer ───────────────────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          // Elegant attribution
                          Text(
                            ' هذا من فضل ربي ',
                            style: TextStyle(
                              color: c.gold.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Small privacy link
                          GestureDetector(
                            onTap: () => _showPrivacyPolicy(context, app, c),
                            child: Text(
                              isAr ? 'سياسة الخصوصية' : 'Privacy Policy',
                              style: TextStyle(
                                color: c.muted.withValues(alpha: 0.4),
                                fontSize: 10,
                                decoration: TextDecoration.underline,
                                decorationColor: c.muted.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Shows the privacy policy dialog.
  void _showPrivacyPolicy(BuildContext context, AppState app, ThemeColors c) {
    final isAr = app.isArabic;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: c.bg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            isAr ? 'سياسة الخصوصية' : 'Privacy Policy',
            style: TextStyle(
              color: c.gold,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          content: SingleChildScrollView(
            child: Text(
              isAr
                  ? "يطلب هذا التطبيق إذن الوصول إلى الميكروفون (RECORD_AUDIO) "
                        "للاستماع إلى تلاوتك وتتبعها.\n\n"
                        "تتم جميع عمليات معالجة الصوت محلياً (100% Offline) "
                        "على جهازك بالكامل.\n"
                        "نحن لا نقوم بجمع، أو نقل، أو تخزين، أو مشاركة "
                        "بياناتك الصوتية أو أي معلومات شخصية.\n\n"
                        "لا يتصل هذا التطبيق بالإنترنت على الإطلاق."
                  : "This app requires Microphone access (RECORD_AUDIO) "
                        "to listen to and track your recitation.\n\n"
                        "All audio processing is done 100% OFFLINE locally "
                        "on your device.\n"
                        "We DO NOT collect, transmit, store, or share your "
                        "voice data or any personal information.\n\n"
                        "This app does not connect to the internet.",
              style: TextStyle(fontSize: 13, height: 1.5, color: c.text),
              textAlign: isAr ? TextAlign.right : TextAlign.left,
              textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                isAr ? 'حسناً' : 'OK',
                style: TextStyle(color: c.gold, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }
}

// A compact section label.
class _SectionLabel extends StatelessWidget {
  final String title;
  final ThemeColors c;

  const _SectionLabel({required this.title, required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        title,
        style: TextStyle(
          color: c.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// A clean settings tile with title, subtitle, and trailing widget.
class _SettingTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final ThemeColors c;
  final Widget trailing;

  const _SettingTile({
    required this.title,
    required this.subtitle,
    required this.c,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16), // More rounded
          border: Border.all(color: c.border.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: c.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: c.muted, 
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

// A horizontal segmented selector — modern alternative to ChoiceChips.
class _SegmentedSelector extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ThemeColors c;
  final ValueChanged<int> onSelected;

  const _SegmentedSelector({
    required this.labels,
    required this.selected,
    required this.c,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isSel = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSel ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSel 
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : [],
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: isSel ? c.gold : c.muted.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
