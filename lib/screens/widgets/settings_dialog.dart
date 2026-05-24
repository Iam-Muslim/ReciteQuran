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

        return Directionality(
          textDirection: app.isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Dialog(
            backgroundColor: c.bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    app.isArabic ? 'الإعدادات' : 'Settings',
                    style: TextStyle(
                      color: c.gold,
                      fontSize: 24,
                      fontFamily: 'ScheherazadeNew',
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // Language Toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        app.isArabic ? 'اللغة / Language' : 'Language / اللغة',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontFamily: 'ScheherazadeNew',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Switch(
                        value: !app.isArabic,
                        onChanged: (_) => app.toggleLanguage(),
                        activeColor: c.gold,
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  // Font Weight Chooser
                  Text(
                    app.isArabic ? 'سمك الخط' : 'Font Weight',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontFamily: 'ScheherazadeNew',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildWeightButton(
                        app,
                        c,
                        app.isArabic ? 'عادي' : 'Regular',
                        FontWeight.w400,
                      ),
                      _buildWeightButton(
                        app,
                        c,
                        app.isArabic ? 'متوسط' : 'Medium',
                        FontWeight.w500,
                      ),
                      _buildWeightButton(
                        app,
                        c,
                        app.isArabic ? 'شبه غامق' : 'Semi Bold',
                        FontWeight.w600,
                      ),
                      _buildWeightButton(
                        app,
                        c,
                        app.isArabic ? 'غامق' : 'Bold',
                        FontWeight.w700,
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  // Mistake Level Chooser
                  Text(
                    app.isArabic ? 'مستوى التدقيق' : 'Mistake Checking',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontFamily: 'ScheherazadeNew',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildLevelButton(
                        app,
                        c,
                        app.isArabic ? 'بدون' : 'None',
                        MistakeLevel.none,
                      ),
                      _buildLevelButton(
                        app,
                        c,
                        app.isArabic ? 'سهل' : 'Easy',
                        MistakeLevel.easy,
                      ),
                      _buildLevelButton(
                        app,
                        c,
                        app.isArabic ? 'متوسط' : 'Medium',
                        MistakeLevel.medium,
                      ),
                      _buildLevelButton(
                        app,
                        c,
                        app.isArabic ? 'صعب' : 'Hard',
                        MistakeLevel.hard,
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  // Lookahead Chooser
                  Text(
                    app.isArabic ? 'الكلمات المتتبعة' : 'Lookahead Words',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontFamily: 'ScheherazadeNew',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildLookaheadButton(app, c, '1', 1),
                      _buildLookaheadButton(app, c, '2', 2),
                      _buildLookaheadButton(app, c, '3', 3),
                      _buildLookaheadButton(app, c, '4', 4),
                      _buildLookaheadButton(app, c, '5', 5),
                    ],
                  ),
                  const Divider(height: 32),
                  // Privacy Policy Button
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _showPrivacyPolicy(context, app, c),
                      icon: Icon(Icons.privacy_tip_outlined, color: c.gold),
                      label: Text(
                        app.isArabic ? 'سياسة الخصوصية' : 'Privacy Policy',
                        style: TextStyle(
                          color: c.gold,
                          fontFamily: 'ScheherazadeNew',
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'هذا من فضل ربي \n الحمدلله - Thanks to Allah the greatest \n'
                    '\nFont: Scheherazade New',
                    style: TextStyle(color: c.muted, fontSize: 10),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeightButton(
    AppState app,
    ThemeColors c,
    String label,
    FontWeight weight,
  ) {
    final isSelected = app.fontWeight == weight;
    return Expanded(
      child: InkWell(
        onTap: () => app.setFontWeight(weight),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? c.gold : Colors.transparent,
            border: Border.all(color: c.gold),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontFamily: 'ScheherazadeNew',
              fontSize: 13,
              fontWeight: weight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLevelButton(
    AppState app,
    ThemeColors c,
    String label,
    MistakeLevel level,
  ) {
    final isSelected = app.mistakeLevel == level;
    return Expanded(
      child: InkWell(
        onTap: () => app.setMistakeLevel(level),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? c.gold : Colors.transparent,
            border: Border.all(color: c.gold),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontFamily: 'ScheherazadeNew',
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLookaheadButton(
    AppState app,
    ThemeColors c,
    String label,
    int lookahead,
  ) {
    final isSelected = app.lookahead == lookahead;
    return Expanded(
      child: InkWell(
        onTap: () => app.setLookahead(lookahead),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? c.gold : Colors.transparent,
            border: Border.all(color: c.gold),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontFamily: 'ScheherazadeNew',
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context, AppState app, ThemeColors c) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: c.bg,
          title: Text(
            app.isArabic ? 'سياسة الخصوصية' : 'Privacy Policy',
            style: TextStyle(
              color: c.gold,
              fontFamily: 'ScheherazadeNew',
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          content: SingleChildScrollView(
            child: Text(
              app.isArabic
                  ? "يطلب هذا التطبيق إذن الوصول إلى الميكروفون (RECORD_AUDIO) للاستماع إلى تلاوتك وتتبعها.\n\n"
                        "تتم جميع عمليات معالجة الصوت محلياً (100% Offline) على جهازك بالكامل.\n"
                        "نحن لا نقوم بجمع، أو نقل، أو تخزين، أو مشاركة بياناتك الصوتية أو أي معلومات شخصية مع أي خوادم أو جهات خارجية.\n\n"
                        "لا يتصل هذا التطبيق بالإنترنت على الإطلاق، مما يضمن خصوصيتك التامة."
                  : "This app requires Microphone access (RECORD_AUDIO) to listen to and track your recitation.\n\n"
                        "All audio processing is done 100% OFFLINE locally on your device.\n"
                        "We DO NOT collect, transmit, store, or share your voice data or any personal information with any third-party servers.\n\n"
                        "This app does not connect to the internet, guaranteeing your complete privacy.",
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ScheherazadeNew',
                fontSize: 16,
              ),
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                app.isArabic ? 'حسناً' : 'OK',
                style: TextStyle(color: c.gold, fontFamily: 'ScheherazadeNew'),
              ),
            ),
          ],
        );
      },
    );
  }
}
