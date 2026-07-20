import 'package:flutter/material.dart';
import '../../state/app_state.dart';

/// Settings bottom sheet — clean, warm, and intuitive.
///
/// Design principles:
/// - Each setting is a clear row with icon + label + control
/// - Large touch targets (minimum 44px)
/// - No abbreviations — full labels always
/// - Warm gold accent on active selections
/// - Footer with Islamic dua
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
              child: Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.gold.withValues(alpha: 0.06),
                      blurRadius: 40,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Directionality(
                  textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Handle ──
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: c.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Title ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Icon(
                                Icons.settings_rounded,
                                color: c.gold,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isAr ? 'الإعدادات' : 'Settings',
                                style: TextStyle(
                                  color: c.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Settings Group ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.surfaceHigh.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: c.border.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                // 1. Font Size
                                _FontSliderTile(c: c, app: app, isAr: isAr),

                                _SettingDivider(c: c),

                                // 2. AutoScroll Speed
                                _AutoScrollSliderTile(
                                  c: c,
                                  app: app,
                                  isAr: isAr,
                                ),

                                _SettingDivider(c: c),

                                // 3. Tracking Strictness
                                _TrackingStrictnessTile(
                                  c: c,
                                  app: app,
                                  isAr: isAr,
                                ),

                                _SettingDivider(c: c),

                                // 3. Language
                                _SettingTile(
                                  icon: Icons.language_rounded,
                                  title: isAr ? 'اللغة' : 'Language',
                                  c: c,
                                  child: _PillSelector(
                                    labels: const ['عربي', 'English'],
                                    selected: isAr ? 0 : 1,
                                    c: c,
                                    onSelected: (i) {
                                      if ((i == 0 && !isAr) || (i == 1 && isAr)) {
                                        app.toggleLanguage();
                                      }
                                    },
                                  ),
                                ),

                                _SettingDivider(c: c),

                                // 4. Theme
                                _SettingTile(
                                  icon: Icons.palette_rounded,
                                  title: isAr ? 'المظهر' : 'Theme',
                                  c: c,
                                  child: _PillSelector(
                                    labels: isAr
                                        ? ['أبيض', 'أسود']
                                        : ['White', 'Black'],
                                    selected: app.theme.index,
                                    c: c,
                                    onSelected: (i) =>
                                        app.setTheme(AppTheme.values[i]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Footer Dua ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'ربنا تقبل منا انك انت السميع العليم\nهذا من فضل ربي',
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: c.gold.withValues(alpha: 0.45),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
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

/// Thin separator line between settings.
class _SettingDivider extends StatelessWidget {
  final ThemeColors c;
  const _SettingDivider({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: c.border.withValues(alpha: 0.2),
    );
  }
}

/// A single setting row with icon, title, and control widget.
class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final ThemeColors c;
  final Widget child;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.c,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: c.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              title,
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: child),
        ],
      ),
    );
  }
}

/// Font size slider tile — custom layout with slider.
class _FontSliderTile extends StatefulWidget {
  final ThemeColors c;
  final AppState app;
  final bool isAr;

  const _FontSliderTile({
    required this.c,
    required this.app,
    required this.isAr,
  });

  @override
  State<_FontSliderTile> createState() => _FontSliderTileState();
}

class _FontSliderTileState extends State<_FontSliderTile> {
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.format_size_rounded, color: c.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              isAr ? 'حجم الخط' : 'Font Size',
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text(
                  'أ',
                  style: TextStyle(
                    fontFamily: 'HafsSmart',
                    color: c.muted,
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      trackHeight: 4,
                      activeTrackColor: c.gold,
                      inactiveTrackColor: c.border.withValues(alpha: 0.5),
                      thumbColor: c.gold,
                      overlayColor: c.gold.withValues(alpha: 0.15),
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
                Text(
                  'أ',
                  style: TextStyle(
                    fontFamily: 'HafsSmart',
                    color: c.muted,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Modern pill-shaped segmented selector.
///
/// Uses warm gold for active pill. Large enough for elderly touch targets.
class _PillSelector extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ThemeColors c;
  final ValueChanged<int> onSelected;

  const _PillSelector({
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
        color: c.bg,
        borderRadius: BorderRadius.circular(14),
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSel ? c.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: isSel
                      ? [
                          BoxShadow(
                            color: c.gold.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: isSel
                          ? Colors.white
                          : c.text.withValues(alpha: 0.65),
                      fontSize: 13,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
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

/// AutoScroll speed slider tile — vertical layout for wider slider.
class _AutoScrollSliderTile extends StatefulWidget {
  final ThemeColors c;
  final AppState app;
  final bool isAr;

  const _AutoScrollSliderTile({
    required this.c,
    required this.app,
    required this.isAr,
  });

  @override
  State<_AutoScrollSliderTile> createState() => _AutoScrollSliderTileState();
}

class _AutoScrollSliderTileState extends State<_AutoScrollSliderTile> {
  late double _localSpeed;

  @override
  void initState() {
    super.initState();
    _localSpeed = widget.app.autoScrollSpeed.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = widget.app;
    final isAr = widget.isAr;

    const labels = ['0.25x', '0.5x', '1x', '1.5x', '2x', '2.5x', '3x'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, color: c.gold, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isAr ? 'سرعة التمرير التلقائي (وضع القراءة)' : 'Auto-Scroll Speed (Read Mode)',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                labels[_localSpeed.toInt()],
                style: TextStyle(
                  color: c.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              trackHeight: 4,
              activeTrackColor: c.gold,
              inactiveTrackColor: c.border.withValues(alpha: 0.5),
              thumbColor: c.gold,
              overlayColor: c.gold.withValues(alpha: 0.15),
              tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
              activeTickMarkColor: c.surface,
              inactiveTickMarkColor: c.border,
            ),
            child: Slider(
              value: _localSpeed,
              min: 0,
              max: (labels.length - 1).toDouble(),
              divisions: labels.length - 1,
              label: labels[_localSpeed.toInt()],
              onChanged: (v) {
                setState(() => _localSpeed = v);
              },
              onChangeEnd: (v) {
                app.setAutoScrollSpeed(v.toInt());
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Modern Tracking Strictness tile that explains each mode clearly.
class _TrackingStrictnessTile extends StatelessWidget {
  final ThemeColors c;
  final AppState app;
  final bool isAr;

  const _TrackingStrictnessTile({
    required this.c,
    required this.app,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final titles = isAr ? ['سهل', 'عادي', 'صعب'] : ['Easy', 'Normal', 'Hard'];
    final descs = isAr
        ? [
            'يتجاهل أخطاء الحروف البسيطة والمدود الزائدة.',
            'تطابق متوازن. يظهر جميع الأخطاء وأحكام التجويد.',
            'تطابق دقيق جداً وحساس لأي خطأ في النطق.'
          ]
        : [
            'Hides basic letter errors & extra elongations.',
            'Balanced matching. Shows all errors and Tajweed rules.',
            'Very strict matching. Sensitive to exact pronunciation.'
          ];

    final int sel = app.trackingStrictness.index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.track_changes_rounded, color: c.gold, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isAr ? 'مستوى التصحيح' : 'Correction Level',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PillSelector(
            labels: titles,
            selected: sel,
            c: c,
            onSelected: (i) {
              app.setTrackingStrictness(TrackingStrictness.values[i]);
            },
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.1),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Container(
              key: ValueKey(sel),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.gold.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.info_outline_rounded, color: c.gold, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      descs[sel],
                      style: TextStyle(
                        color: c.text.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
