import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/app_state.dart';
import '/tajweed/providers/muaalem_provider.dart';

class TajweedSettingsScreen extends ConsumerWidget {
  const TajweedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = AppState.instance;
    final tSettings = ref.watch(tajweedSettingsProvider);
    final tNotifier = ref.read(tajweedSettingsProvider.notifier);
    final c = app.colors;

    return Directionality(
      textDirection: app.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: c.muted),
          title: Text(
            app.isArabic ? 'الإعدادات' : 'Settings',
            style: TextStyle(color: c.gold, fontWeight: FontWeight.bold),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                app.isArabic ? 'تم' : 'Done',
                style: TextStyle(color: c.gold, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        body: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // Rewaya Section
            _buildSection(
              c,
              app,
              title: app.isArabic ? 'الرواية' : 'Recitation Style',
              footer: app.isArabic
                  ? 'اختر رواية القراءة المستخدمة'
                  : 'Select your recitation style',
              child: _buildPickerRow(
                c,
                title: app.isArabic ? 'الرواية' : 'Style',
                value: tSettings.rewaya == 'hafs'
                    ? (app.isArabic ? 'حفص' : 'Hafs')
                    : tSettings.rewaya == 'warsh'
                    ? (app.isArabic ? 'ورش' : 'Warsh')
                    : (app.isArabic ? 'قالون' : 'Qaloon'),
                onTap: () {
                  final next = tSettings.rewaya == 'hafs'
                      ? 'warsh'
                      : tSettings.rewaya == 'warsh'
                      ? 'qaloon'
                      : 'hafs';
                  tNotifier.updateSettings(tSettings.copyWith(rewaya: next));
                },
              ),
            ),

            const SizedBox(height: 24),

            // Madd Settings Section
            _buildSection(
              c,
              app,
              title: app.isArabic ? 'إعدادات المد' : 'Madd Settings',
              icon: Icons.waves_rounded,
              footer: app.isArabic
                  ? 'اضبط أطوال المد حسب طريقة القراءة التي تتبعها. القيم الافتراضية مناسبة لأغلب القراء.'
                  : 'Adjust Madd lengths according to your reading style.',
              child: Column(
                children: [
                  _buildMaddControl(
                    c,
                    app,
                    title: app.isArabic ? 'مد منفصل' : 'Madd Monfasel',
                    value: tSettings.maddMonfaselLen,
                    min: 2,
                    max: 6,
                    example: app.isArabic
                        ? 'مثال: وَمَآ أَنزَلْنَا'
                        : 'Example: وَمَآ أَنزَلْنَا',
                    onChanged: (val) => tNotifier.updateSettings(
                      tSettings.copyWith(maddMonfaselLen: val),
                    ),
                  ),
                  Divider(color: c.border.withValues(alpha: 0.3), height: 32),
                  _buildMaddControl(
                    c,
                    app,
                    title: app.isArabic ? 'مد متصل' : 'Madd Mottasel',
                    value: tSettings.maddMottaselLen,
                    min: 4,
                    max: 6,
                    example: app.isArabic
                        ? 'مثال: جَآءَ، سُوٓءُ'
                        : 'Example: جَآءَ، سُوٓءُ',
                    onChanged: (val) => tNotifier.updateSettings(
                      tSettings.copyWith(maddMottaselLen: val),
                    ),
                  ),
                  Divider(color: c.border.withValues(alpha: 0.3), height: 32),
                  _buildMaddControl(
                    c,
                    app,
                    title: app.isArabic
                        ? 'مد متصل (وقف)'
                        : 'Madd Mottasel (Waqf)',
                    value: tSettings.maddMottaselWaqf,
                    min: 4,
                    max: 6,
                    example: app.isArabic
                        ? 'المد المتصل عند الوقف'
                        : 'Madd Mottasel when stopping',
                    onChanged: (val) => tNotifier.updateSettings(
                      tSettings.copyWith(maddMottaselWaqf: val),
                    ),
                  ),
                  Divider(color: c.border.withValues(alpha: 0.3), height: 32),
                  _buildMaddControl(
                    c,
                    app,
                    title: app.isArabic ? 'مد عارض للسكون' : 'Madd Aared',
                    value: tSettings.maddAaredLen,
                    min: 2,
                    max: 6,
                    example: app.isArabic
                        ? 'مثال: نَسْتَعِينْ، الرَّحِيمْ'
                        : 'Example: نَسْتَعِينْ، الرَّحِيمْ',
                    onChanged: (val) => tNotifier.updateSettings(
                      tSettings.copyWith(maddAaredLen: val),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Reset Section
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border.withValues(alpha: 0.5)),
              ),
              child: ListTile(
                leading: Icon(Icons.refresh_rounded, color: c.red),
                title: Text(
                  app.isArabic ? 'إعادة الضبط للافتراضي' : 'Reset to Defaults',
                  style: TextStyle(color: c.red, fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  tNotifier.resetToDefaults();
                },
              ),
            ),

            const SizedBox(height: 24),

            // Info Section
            _buildSection(
              c,
              app,
              title: app.isArabic ? 'معلومات عن المد' : 'Madd Information',
              icon: Icons.info_outline_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(
                    c,
                    app,
                    'المد المنفصل',
                    'حرف مد في آخر كلمة وهمزة في أول الكلمة التالية',
                  ),
                  Divider(color: c.border.withValues(alpha: 0.3), height: 24),
                  _buildInfoRow(
                    c,
                    app,
                    'المد المتصل',
                    'حرف مد وبعده همزة في نفس الكلمة',
                  ),
                  Divider(color: c.border.withValues(alpha: 0.3), height: 24),
                  _buildInfoRow(
                    c,
                    app,
                    'المد العارض',
                    'حرف مد وبعده حرف ساكن سكونًا عارضًا للوقف',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    ThemeColors c,
    AppState app, {
    required String title,
    required Widget child,
    String? footer,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: c.muted),
                const SizedBox(width: 8),
              ],
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: c.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border.withValues(alpha: 0.5)),
          ),
          child: child,
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
            child: Text(footer, style: TextStyle(color: c.muted, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildPickerRow(
    ThemeColors c, {
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: c.text, fontSize: 16)),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  color: c.gold,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: c.muted, size: 20),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMaddControl(
    ThemeColors c,
    AppState app, {
    required String title,
    required int value,
    required int min,
    required int max,
    required String example,
    required Function(int) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              app.isArabic ? '$value حركات' : '$value Harakat',
              style: TextStyle(color: c.muted, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (int i = min; i <= max; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: value == i ? c.gold : c.surfaceHigh,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: value == i ? c.gold : c.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      i.toString(),
                      style: TextStyle(
                        color: value == i ? Colors.white : c.text,
                        fontWeight: value == i
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(example, style: TextStyle(color: c.muted, fontSize: 12)),
      ],
    );
  }

  Widget _buildInfoRow(ThemeColors c, AppState app, String title, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(desc, style: TextStyle(color: c.muted, fontSize: 12)),
      ],
    );
  }
}
