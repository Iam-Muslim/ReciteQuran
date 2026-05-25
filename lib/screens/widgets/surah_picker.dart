/// Surah selection bottom sheet.
///
/// Displays all 114 surahs in a searchable, scrollable list.
/// Supports both Arabic and English names, with Arabic-Indic digits.
/// Auto-scrolls to the currently selected surah on first open.
import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../utils/normalizer.dart';

class SurahPickerSheet extends StatefulWidget {
  final int current;
  final void Function(int) onPick;

  const SurahPickerSheet({
    super.key,
    required this.current,
    required this.onPick,
  });

  @override
  State<SurahPickerSheet> createState() => _SurahPickerSheetState();
}

class _SurahPickerSheetState extends State<SurahPickerSheet> {
  String _query = '';

  static const List<String> _names = [
    "الفاتحة",
    "البقرة",
    "آل عمران",
    "النساء",
    "المائدة",
    "الأنعام",
    "الأعراف",
    "الأنفال",
    "التوبة",
    "يونس",
    "هود",
    "يوسف",
    "الرعد",
    "إبراهيم",
    "الحجر",
    "النحل",
    "الإسراء",
    "الكهف",
    "مريم",
    "طه",
    "الأنبياء",
    "الحج",
    "المؤمنون",
    "النور",
    "الفرقان",
    "الشعراء",
    "النمل",
    "القصص",
    "العنكبوت",
    "الروم",
    "لقمان",
    "السجدة",
    "الأحزاب",
    "سبأ",
    "فاطر",
    "يس",
    "الصافات",
    "ص",
    "الزمر",
    "غافر",
    "فصلت",
    "الشورى",
    "الزخرف",
    "الدخان",
    "الجاثية",
    "الأحقاف",
    "محمد",
    "الفتح",
    "الحجرات",
    "ق",
    "الذاريات",
    "الطور",
    "النجم",
    "القمر",
    "الرحمن",
    "الواقعة",
    "الحديد",
    "المجادلة",
    "الحشر",
    "الممتحنة",
    "الصف",
    "الجمعة",
    "المنافقون",
    "التغابن",
    "الطلاق",
    "التحريم",
    "الملك",
    "القلم",
    "الحاقة",
    "المعارج",
    "نوح",
    "الجن",
    "المزمل",
    "المدثر",
    "القيامة",
    "الإنسان",
    "المرسلات",
    "النبأ",
    "النازعات",
    "عبس",
    "التكوير",
    "الانفطار",
    "المطففين",
    "الانشقاق",
    "البروج",
    "الطارق",
    "الأعلى",
    "الغاشية",
    "الفجر",
    "البلد",
    "الشمس",
    "الليل",
    "الضحى",
    "الشرح",
    "التين",
    "العلق",
    "القدر",
    "البينة",
    "الزلزلة",
    "العاديات",
    "القارعة",
    "التكاثر",
    "العصر",
    "الهمزة",
    "الفيل",
    "قريش",
    "الماعون",
    "الكوثر",
    "الكافرون",
    "النصر",
    "المسد",
    "الإخلاص",
    "الفلق",
    "الناس",
  ];
  static const List<String> _namesEn = [
    "Al-Fatihah",
    "Al-Baqarah",
    "Ali 'Imran",
    "An-Nisa",
    "Al-Ma'idah",
    "Al-An'am",
    "Al-A'raf",
    "Al-Anfal",
    "At-Tawbah",
    "Yunus",
    "Hud",
    "Yusuf",
    "Ar-Ra'd",
    "Ibrahim",
    "Al-Hijr",
    "An-Nahl",
    "Al-Isra",
    "Al-Kahf",
    "Maryam",
    "Taha",
    "Al-Anbiya",
    "Al-Hajj",
    "Al-Mu'minun",
    "An-Nur",
    "Al-Furqan",
    "Ash-Shu'ara",
    "An-Naml",
    "Al-Qasas",
    "Al-'Ankabut",
    "Ar-Rum",
    "Luqman",
    "As-Sajdah",
    "Al-Ahzab",
    "Saba",
    "Fatir",
    "Ya-Sin",
    "As-Saffat",
    "Sad",
    "Az-Zumar",
    "Ghafir",
    "Fussilat",
    "Ash-Shura",
    "Az-Zukhruf",
    "Ad-Dukhan",
    "Al-Jathiyah",
    "Al-Ahqaf",
    "Muhammad",
    "Al-Fath",
    "Al-Hujurat",
    "Qaf",
    "Ad-Zariyat",
    "At-Tur",
    "An-Najm",
    "Al-Qamar",
    "Ar-Rahman",
    "Al-Waqi'ah",
    "Al-Hadid",
    "Al-Mujadilah",
    "Al-Hashr",
    "Al-Mumtahanah",
    "As-Saff",
    "Al-Jumu'ah",
    "Al-Munafiqun",
    "At-Taghabun",
    "At-Talaq",
    "At-Tahrim",
    "Al-Mulk",
    "Al-Qalam",
    "Al-Haqqah",
    "Al-Ma'arij",
    "Nuh",
    "Al-Jinn",
    "Al-Muzzammil",
    "Al-Muddaththir",
    "Al-Qiyamah",
    "Al-Insan",
    "Al-Mursalat",
    "An-Naba",
    "An-Nazi'at",
    "'Abasa",
    "At-Takwir",
    "Al-Infitar",
    "Al-Mutaffifin",
    "Al-Inshiqaq",
    "Al-Buruj",
    "At-Tariq",
    "Al-A'la",
    "Al-Ghashiyah",
    "Al-Fajr",
    "Al-Balad",
    "Ash-Shams",
    "Al-Layl",
    "Ad-Duhaa",
    "Ash-Sharh",
    "At-Tin",
    "Al-'Alaq",
    "Al-Qadr",
    "Al-Bayyinah",
    "Az-Zalzalah",
    "Al-'Adiyat",
    "Al-Qari'ah",
    "At-Takathur",
    "Al-'Asr",
    "Al-Humazah",
    "Al-Fil",
    "Quraysh",
    "Al-Ma'un",
    "Al-Kawthar",
    "Al-Kafirun",
    "An-Nasr",
    "Al-Masad",
    "Al-Ikhlas",
    "Al-Falaq",
    "An-Nas",
  ];

  bool _scrolled = false;

  String _toArabicDigits(int number) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number.toString().split('').map((e) => digits[int.parse(e)]).join('');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final ThemeColors c = app.colors;

    final normQuery = Normalizer.normalizeArabic(_query);

    final List<int> items = [
      for (int i = 0; i < 114; i++)
        if (_query.isEmpty ||
            Normalizer.normalizeArabic(_names[i]).contains(normQuery) ||
            _namesEn[i].toLowerCase().contains(_query.toLowerCase()) ||
            '${i + 1}'.contains(_query))
          i,
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.75, // Lock size to prevent expansion on scroll
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrolled && ctrl.hasClients && _query.isEmpty) {
            _scrolled = true;
            double offset = (widget.current - 1) * 48.0;
            if (offset > ctrl.position.maxScrollExtent)
              offset = ctrl.position.maxScrollExtent;
            ctrl.jumpTo(offset);
          }
        });

        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Directionality(
            textDirection: app.isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  app.isArabic ? 'اختر السورة' : 'Select Surah',
                  style: TextStyle(
                    color: c.gold,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),

                // ── Search field ─────────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: TextStyle(
                      color: app.isDarkMode ? Colors.white : Colors.black,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: app.isArabic ? 'بحث…' : 'Search...',
                      hintStyle: TextStyle(color: c.muted),
                      prefixIcon: Icon(Icons.search, color: c.gold, size: 18),
                      filled: true,
                      fillColor: c.border,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // ── Surah list ───────────────────────────────────────────────────────
                Expanded(
                  child: ListView.builder(
                    controller: ctrl,
                    physics: const BouncingScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final int idx = items[i];
                      final int sNum = idx + 1;
                      final bool sel = widget.current == sNum;

                      final String displayName = app.isArabic
                          ? _names[idx]
                          : "${_namesEn[idx]} - ${_names[idx]}";

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? c.gold.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: sel
                                ? c.gold.withValues(alpha: 0.5)
                                : c.border.withValues(alpha: 0.5),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          leading: app.isArabic
                              ? (sel ? Icon(Icons.check_circle_rounded, color: c.gold, size: 24) : const SizedBox(width: 24))
                              : Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: sel ? c.gold : c.surfaceHigh,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    app.isArabic ? _toArabicDigits(sNum) : '$sNum',
                                    style: TextStyle(
                                      color: sel ? Colors.white : c.muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                          title: Text(
                            displayName,
                            textAlign: app.isArabic ? TextAlign.right : TextAlign.left,
                            style: TextStyle(
                              color: sel ? c.gold : c.text,
                              fontSize: 20,
                              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: app.isArabic
                              ? Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: sel ? c.gold : c.surfaceHigh,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    app.isArabic ? _toArabicDigits(sNum) : '$sNum',
                                    style: TextStyle(
                                      color: sel ? Colors.white : c.muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : (sel ? Icon(Icons.check_circle_rounded, color: c.gold, size: 24) : const SizedBox(width: 24)),
                          onTap: () => widget.onPick(sNum),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
