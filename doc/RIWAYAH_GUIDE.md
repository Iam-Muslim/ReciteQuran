# 📜 Multi-Riwayah & Multi-Qira'at Guide (الروايات والقراءات العشر)

A comprehensive architectural and developer reference for building multi-Riwayah Quran applications supporting all **10 Mutawatir Qira'at**, **20 Canonical Rawis**, and **6 Counting Madhhabs** using **`package:recite_quran`**.

---

## 📑 Table of Contents

1. [Introduction: Qira'at in Digital Quran Apps](#1-introduction-qiraat-in-digital-quran-apps)
2. [The 6 Canonical Verse-Counting Traditions (مذاهب عد الآي)](#2-the-6-canonical-verse-counting-traditions-مذاهب-عد-الآي)
3. [The 10 Mutawatir Qira'at & 20 Canonical Rawis](#3-the-10-mutawatir-qiraat--20-canonical-rawis)
4. [The Cross-Riwayah Verse Mapping Challenge](#4-the-cross-riwayah-verse-mapping-challenge)
5. [The `QiraatAyahMapper` Architecture](#5-the-qiraatayahmapper-architecture)
6. [Native Datasets vs Universal Cross-Riwayah Tracking](#6-native-datasets-vs-universal-cross-riwayah-tracking)
7. [Configuring `QuranRepository` for Any Riwayah](#7-configuring-quranrepository-for-any-riwayah)
8. [Complete Flutter Riwayah-Selector Example](#8-complete-flutter-riwayah-selector-example)
9. [Production Best Practices](#9-production-best-practices)

---

## 1. Introduction: Qira'at in Digital Quran Apps

The Holy Quran was revealed in seven ahruf (*سبعة أحرف*) and transmitted via successive mutawatir chains (*القراءات العشر المتواترة*). Millions of Muslims worldwide recite using traditions other than Hafs 'an 'Asim:
- **Warsh 'an Nafi' (ورش عن نافع):** Prevalent across North and West Africa (Morocco, Algeria, Mauritania, Senegal).
- **Qalun 'an Nafi' (قالون عن نافع):** Prevalent in Libya and parts of Tunisia.
- **Al-Duri 'an Abi 'Amr (الدوري عن أبي عمرو):** Prevalent in Sudan and East Africa.
- **Shu'bah 'an 'Asim (شعبة عن عاصم):** Historically prominent across many Islamic regions.

**`recite_quran`** is architected to provide first-class, cross-tradition recitation tracking for all 20 canonical Rawis without forcing users into Hafs conventions.

---

## 2. The 6 Canonical Verse-Counting Traditions (مذاهب عد الآي)

Different regions of the early Islamic world had authoritative traditions for where verses begin and end. This means the **total number of Ayahs in the Quran varies by counting tradition**:

```dart
enum QuranCountingSystem {
  kufi('kufi', 'الكوفي', 6236),              // Most common worldwide (Hafs, Shu'bah)
  madaniLast('madani-last', 'المدني الأخير', 6214), // Nafi' (Warsh, Qalun)
  madaniFirst('madani-first', 'المدني الأول', 6214), // Abu Ja'far
  makki('makki', 'المكي', 6219),              // Ibn Kathir (Al-Bazzi, Qunbul)
  basri('basri', 'البصري', 6204),              // Abu 'Amr, Ya'qub
  dimashqi('dimashqi', 'الدمشقي', 6226);       // Ibn 'Amir (Hisham, Ibn Dhakwan)
}
```

---

## 3. The 10 Mutawatir Qira'at & 20 Canonical Rawis

The engine provides strongly typed enums for all **10 Qira'at** (`QuranQiraa`) and **20 Rawis** (`QuranRiwayah`) in [`lib/data/qiraat_ayah_mapper.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/data/qiraat_ayah_mapper.dart):

| # | Imam of Qira'ah | Canonical Rawis (الرواة) | Counting Tradition | Total Ayahs |
| :-: | :--- | :--- | :--- | :-: |
| **1** | **Nafi' al-Madani (نافع)** | **Qalun (قالون)**<br>**Warsh (ورش)** | Madani Last (المدني الأخير) | **6,214** |
| **2** | **Ibn Kathir al-Makki (ابن كثير)** | **Al-Bazzi (البزي)**<br>**Qunbul (قنبل)** | Makki (المكي) | **6,219** |
| **3** | **Abu 'Amr al-Basri (أبو عمرو)** | **Al-Duri (الدوري)**<br>**Al-Susi (السوسي)** | Basri (البصري) | **6,204** |
| **4** | **Ibn 'Amir ad-Dimashqi (ابن عامر)** | **Hisham (هشام)**<br>**Ibn Dhakwan (ابن ذكوان)** | Dimashqi (الدمشقي) | **6,226** |
| **5** | **'Asim al-Kufi (عاصم)** | **Shu'bah (شعبة)**<br>**Hafs (حفص)** | Kufi (الكوفي) | **6,236** |
| **6** | **Hamza al-Kufi (حمزة)** | **Khalaf (خلف)**<br>**Khallad (خلاد)** | Kufi (الكوفي) | **6,236** |
| **7** | **Al-Kisa'i al-Kufi (الكسائي)** | **Abu al-Harith (أبو الحارث)**<br>**Al-Duri (الدوري عن الكسائي)** | Kufi (الكوفي) | **6,236** |
| **8** | **Abu Ja'far al-Madani (أبو جعفر)** | **Ibn Wardan (ابن وردان)**<br>**Ibn Jammaz (ابن جماز)** | Madani First (المدني الأول) | **6,214** |
| **9** | **Ya'qub al-Basri (يعقوب)** | **Ruways (رويس)**<br>**Rawh (روح)** | Basri (البصري) | **6,204** |
| **10**| **Khalaf al-'Ashir (خلف العاشر)** | **Ishaq (إسحاق)**<br>**Idris (إدريس)** | Kufi (الكوفي) | **6,236** |

---

## 4. The Cross-Riwayah Verse Mapping Challenge

Why do we need a mapping layer?

### Example 1: Surat Al-Fatihah (7 Ayahs in all traditions)
- **In Hafs (Kufi):**
  - Ayah 1: *بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ* (Basmalah is an Ayah)
  - Ayahs 2–6: *الْحَمْدُ لِلَّهِ... اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ*
  - Ayah 7: *صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ* (One complete Ayah)
- **In Warsh (Madani Last):**
  - Basmalah is NOT counted as an Ayah.
  - Ayah 1: *الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ*
  - Ayah 6: *صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ*
  - Ayah 7: *غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ*

### Example 2: Disjointed Letters (*Al-Baqarah*)
- **In Kufi:** *الم* is Ayah 1. *ذَٰلِكَ الْكِتَابُ...* is Ayah 2.
- **In Madani Last (Warsh):** *الم ذَٰلِكَ الْكِتَابُ لَا رَيْبَ ۛ فِيهِ ۛ هُدًى لِّلْمُتَّقِينَ* is combined into **Ayah 1**!

If an app tracking Warsh directly looks up Hafs verse indices, **the highlights will be shifted by 1 or 2 Ayahs across the entire Surah**.

---

## 5. The `QiraatAyahMapper` Architecture

`QiraatAyahMapper` ([`lib/data/qiraat_ayah_mapper.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/data/qiraat_ayah_mapper.dart)) solves this deterministically using the canonical **[Quranpedia Qira'at Ayah Map](https://github.com/quranpedia/qiraat-ayah-map)** dataset:

```
Reciter utters Warsh [Surah 2, Ayah 1]
                     │
                     ▼
┌──────────────────────────────────────────────┐
│             QiraatAyahMapper                 │
│  Translates Warsh (2:1) ──► Hafs (2:1 & 2:2) │
└────────────────────┬─────────────────────────┘
                     │
                     ▼
Target phonetic words loaded from reference index
```

### Loading the Mapper
The mapper can be loaded from bundled assets or on-demand:

```dart
// 1. Load for Warsh:
final mapper = await QiraatAyahMapper.loadForRiwayah(
  QuranRiwayah.warsh,
  autoDownload: true, // Downloads mapping JSON if not bundled locally
);

// 2. Query mappings:
final hafsVerse = mapper.mapToHafs(surah: 2, ayah: 1);
print('Warsh 2:1 maps to Hafs: ${hafsVerse?.hafsAyah}');

// 3. Reverse lookup (from Hafs to Warsh):
final warshVerse = mapper.mapFromHafs(surah: 2, hafsAyah: 2);
print('Hafs 2:2 corresponds to Warsh Ayah: ${warshVerse?.riwayahAyah}');
```

---

## 6. Native Datasets vs Universal Cross-Riwayah Tracking

`recite_quran` operates at two levels of Riwayah support:

### Level 1: Native Phoneme Datasets
- **Supported for:** **Hafs 'an 'Asim** and **Warsh 'an Nafi'**.
- **Features:** Sound-level phoneme transcriptions (`textPhoneme`), native tajweed rules, exact Madd markers, and vocalization differences (e.g. *يُؤْمِنُونَ* vs *يُومِنُونَ*, *مَالِكِ* vs *مَلِكِ*).
- **Tajweed Verification:** Active and calibrated for both Hafs and Warsh.

### Level 2: Universal Cross-Riwayah Tracking
- **Supported for:** **All 20 Mutawatir Rawis** across all 6 counting schools.
- **Features:** Uses `QiraatAyahMapper` to project any rawi's verse indices onto the underlying alignment engine. Provides seamless word-following, auto-scrolling, and memorization verification across any Riwayah without requiring 20 separate 100MB phoneme files.

---

## 7. Configuring `QuranRepository` for Any Riwayah

```dart
import 'package:recite_quran/recite_quran.dart';

// 1. Initialize metadata service
final metadataService = QuranMetadataService(
  phonemeFilePath: 'assets/model/ordered_quran_phonemes.json',
);
await metadataService.loadData();

// 2. Load the Ayah mapper for target Riwayah
final ayahMapper = await QiraatAyahMapper.loadForRiwayah(
  QuranRiwayah.warsh,
);

// 3. Construct QuranRepository with active Riwayah & mapper
final repository = QuranRepository(
  metadataService,
  riwayah: QuranRiwayah.warsh,
  ayahMapper: ayahMapper,
);

// 4. Initialize ReciteQuran tracker
final tracker = ReciteQuran(
  repository: repository,
  config: const TrackerConfig(
    matchingStrictness: MatchingStrictness.normal,
    enableEarlyMatching: true,
  ),
);
await tracker.initialize();
```

---

## 8. Complete Flutter Riwayah-Selector Example

Here is a working Flutter screen that lets users switch between Riwayat dynamically:

```dart
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

class RiwayahSelectorScreen extends StatefulWidget {
  const RiwayahSelectorScreen({super.key});

  @override
  State<RiwayahSelectorScreen> createState() => _RiwayahSelectorScreenState();
}

class _RiwayahSelectorScreenState extends State<RiwayahSelectorScreen> {
  QuranRiwayah _selectedRiwayah = QuranRiwayah.hafs;
  QiraatAyahMapper? _activeMapper;
  bool _isLoading = false;

  Future<void> _changeRiwayah(QuranRiwayah riwayah) async {
    setState(() => _isLoading = true);

    try {
      QiraatAyahMapper? mapper;
      if (riwayah.countingSystem != QuranCountingSystem.kufi) {
        mapper = await QiraatAyahMapper.loadForRiwayah(riwayah, autoDownload: true);
      }

      setState(() {
        _selectedRiwayah = riwayah;
        _activeMapper = mapper;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to ${riwayah.nameAr} (${riwayah.countingSystem.arabicName})')),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading riwayah: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Qira\'at & Riwayat Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Active: ${_selectedRiwayah.nameAr} (${_selectedRiwayah.nameEn})\n'
                    'Counting System: ${_selectedRiwayah.countingSystem.arabicName} (${_selectedRiwayah.countingSystem.totalAyahs} Ayahs)',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(),
                ...QuranRiwayah.values.map((r) => ListTile(
                      title: Text(r.nameAr),
                      subtitle: Text('${r.nameEn} • ${r.qiraa.nameAr}'),
                      trailing: _selectedRiwayah == r ? const Icon(Icons.check, color: Colors.green) : null,
                      onTap: () => _changeRiwayah(r),
                    )),
              ],
            ),
    );
  }
}
```

---

## 9. Production Best Practices

1. **Cache Mappings Locally:** When using on-demand mapping download (`autoDownload: true`), files are automatically saved to the application documents directory (`recite_quran_assets/`) and reused offline on subsequent launches.
2. **Handle Kufi Pass-Through:** For Kufi Riwayat (Hafs, Shu'bah, Hamza, Al-Kisa'i, Khalaf al-Ashir), verse indices match Hafs 1:1, so `QiraatAyahMapper` returns instantly without downloading external mapping tables.
3. **Display Counting Tradition in UI:** Educate users by displaying the counting school name (e.g. *المدني الأخير* for Warsh) next to the Ayah numbers.
