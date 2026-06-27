import 'package:flutter/material.dart';
import '../../state/app_state.dart';

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

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Container(
                  decoration: BoxDecoration(color: c.surface),
                  child: Directionality(
                    textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
                    child: Scrollbar(
                      thumbVisibility: true,
                      radius: const Radius.circular(4),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Handle ────────────────────────────────────────────
                            Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: c.border.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Title ─────────────────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                isAr ? 'الإعدادات' : 'Settings',
                                style: TextStyle(
                                  color: c.gold,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 1. ── Font Size ─────────────────────────────────────────
                            _FontSliderCard(c: c, app: app, isAr: isAr),
                            const SizedBox(height: 8),

                            // 2. ── AutoScroll Speed ─────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: _SettingCard(
                                title: isAr
                                    ? 'سرعة التمرير التلقائي'
                                    : 'AutoScroll Speed',
                                icon: Icons.speed_rounded,
                                c: c,
                                child: _SegmentedSelector(
                                  labels: const ['1x', '2x'],
                                  selected: app.autoScrollSpeed - 1,
                                  c: c,
                                  onSelected: (i) =>
                                      app.setAutoScrollSpeed(i + 1),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 3. ── Language ─────────────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: _SettingCard(
                                title: isAr ? 'اللغة' : 'Language',
                                icon: Icons.language_rounded,
                                c: c,
                                child: _SegmentedSelector(
                                  labels: isAr
                                      ? ['عربي', 'English']
                                      : ['عربي', 'English'],
                                  selected: isAr ? 0 : 1,
                                  c: c,
                                  onSelected: (i) {
                                    if ((i == 0 && !isAr) || (i == 1 && isAr)) {
                                      app.toggleLanguage();
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 4. ── Lookahead ─────────────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: _SettingCard(
                                title: isAr ? 'التخطي التلقائي (Lookahead)' : 'Auto Skip (Lookahead)',
                                icon: Icons.fast_forward_rounded,
                                c: c,
                                child: _SegmentedSelector(
                                  labels: isAr
                                      ? ['تفعيل', 'إيقاف']
                                      : ['On', 'Off'],
                                  selected: app.isLookaheadEnabled ? 0 : 1,
                                  c: c,
                                  onSelected: (i) {
                                    if ((i == 0 && !app.isLookaheadEnabled) || (i == 1 && app.isLookaheadEnabled)) {
                                      app.toggleLookahead();
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 5. ── Matching Difficulty ─────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: _SettingCard(
                                title: isAr ? 'مستوى التطابق' : 'Matching Level',
                                icon: Icons.troubleshoot_rounded,
                                c: c,
                                child: _SegmentedSelector(
                                  labels: isAr
                                      ? ['سهل', 'دقيق']
                                      : ['Easy', 'Strict'],
                                  selected: app.matchingDifficulty == MatchingDifficulty.easy ? 0 : 1,
                                  c: c,
                                  onSelected: (i) {
                                    if ((i == 0 && app.matchingDifficulty != MatchingDifficulty.easy) ||
                                        (i == 1 && app.matchingDifficulty != MatchingDifficulty.hard)) {
                                      app.toggleMatchingDifficulty();
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 6. ── Theme ────────────────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: _SettingCard(
                                title: isAr ? 'المظهر' : 'Theme',
                                icon: Icons.palette_rounded,
                                c: c,
                                child: _SegmentedSelector(
                                  labels: isAr
                                      ? ['فاتح', 'داكن']
                                      : ['Light', 'Dark'],
                                  selected: app.theme.index,
                                  c: c,
                                  onSelected: (i) =>
                                      app.setTheme(AppTheme.values[i]),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Footer ───────────────────────────────────────────
                            Center(
                              child: Column(
                                children: [
                                  Text(
                                    'ربنا تقبل منا انك انت السميع العليم - هذا من فضل ربي  ',
                                    style: TextStyle(
                                      color: c.gold.withValues(alpha: 0.5),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Modern Card for Settings
class _SettingCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final ThemeColors c;
  final Widget child;

  const _SettingCard({
    required this.title,
    this.icon,
    required this.c,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surfaceHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: c.gold, size: 18),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: child),
        ],
      ),
    );
  }
}

// Font Slider Card
class _FontSliderCard extends StatefulWidget {
  final ThemeColors c;
  final AppState app;
  final bool isAr;

  const _FontSliderCard({
    required this.c,
    required this.app,
    required this.isAr,
  });

  @override
  State<_FontSliderCard> createState() => _FontSliderCardState();
}

class _FontSliderCardState extends State<_FontSliderCard> {
  late double _localSize;

  @override
  void initState() {
    super.initState();
    _localSize = widget.app.fontSize;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = widget.app;
    final isAr = widget.isAr;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: c.surfaceHigh.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                isAr ? 'حجم الخط' : 'Font Size',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Icon(Icons.text_decrease_rounded, color: c.muted, size: 14),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                        trackHeight: 3,
                        activeTrackColor: c.gold,
                        inactiveTrackColor: c.border.withValues(alpha: 0.4),
                        thumbColor: c.gold,
                      ),
                      child: Slider(
                        value: _localSize,
                        min: 16.0,
                        max: 42.0,
                        onChanged: (v) {
                          setState(() => _localSize = v);
                        },
                        onChangeEnd: (v) {
                          app.setFontSize(v);
                        },
                      ),
                    ),
                  ),
                  Icon(Icons.text_increase_rounded, color: c.muted, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Modern Segmented Selector
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
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isSel = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSel ? c.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSel
                      ? [
                          BoxShadow(
                            color: c.gold.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: isSel
                          ? Colors.white
                          : c.text.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                    ),
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
