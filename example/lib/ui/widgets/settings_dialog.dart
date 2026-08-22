import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../state/app_state.dart';
import 'settings/autoscroll_slider_tile.dart';
import 'settings/font_slider_tile.dart';
import 'settings/setting_tile.dart';

/// Settings modal bottom sheet with modern styling.
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

        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: c.gold.withValues(alpha: 0.08),
                  blurRadius: 40,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: Material(
                color: Colors.transparent,
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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

                        // ── Title ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: c.gold.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.settings_rounded,
                                  color: c.gold,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                isAr ? 'الإعدادات' : 'Settings',
                                style: TextStyle(
                                  color: c.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              // Reset Button
                              // Reset Button
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () async {
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.clear();
                                    if (context.mounted) {
                                      await app.load();
                                      if (context.mounted) {
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              isAr 
                                                ? 'تمت إعادة التعيين بنجاح.'
                                                : 'Settings reset successfully.',
                                              textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
                                            ),
                                            backgroundColor: c.gold,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    child: Text(
                                      isAr ? 'إعادة تعيين' : 'Reset',
                                      style: TextStyle(
                                        color: c.text.withValues(alpha: 0.6),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12), // Reduced from 20

                        // ── Application Preferences Card ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.surfaceHigh,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                // 1. Language
                                SettingTile(
                                  icon: Icons.language_rounded,
                                  title: isAr ? 'اللغة' : 'Language',
                                  c: c,
                                  trailing: PremiumPillSelector(
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
                                PremiumSettingDivider(c: c),

                                // 2. Theme
                                SettingTile(
                                  icon: Icons.palette_rounded,
                                  title: isAr ? 'المظهر' : 'Theme',
                                  c: c,
                                  trailing: PremiumPillSelector(
                                    labels: isAr ? ['أبيض', 'أسود'] : ['White', 'Black'],
                                    selected: app.theme.index,
                                    c: c,
                                    onSelected: (i) => app.setTheme(AppTheme.values[i]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // ── Reading Preferences Card ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.surfaceHigh,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                // 1. Font Size
                                FontSliderTile(c: c, app: app, isAr: isAr),
                                PremiumSettingDivider(c: c),

                                // 2. AutoScroll Speed
                                AutoScrollSliderTile(c: c, app: app, isAr: isAr),
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
