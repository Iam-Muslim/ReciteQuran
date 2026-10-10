# 🛠️ Troubleshooting & Frequently Asked Questions (FAQ)

A comprehensive debugging and optimization guide for addressing common issues when integrating **`package:recite_quran`**.

---

## 📑 Table of Contents

1. [Audio & Microphone Issues](#1-audio--microphone-issues)
   - [Microphone is silent or fails to record on Android](#microphone-is-silent-or-fails-to-record-on-android)
   - [Microphone drops audio when Bluetooth AirPods connect](#microphone-drops-audio-when-bluetooth-airpods-connect)
   - [Hams letters (`هـ`, `ح`) and quiet breath consonants are missed](#hams-letters-and-quiet-breath-consonants-are-missed)
2. [Tracking & Alignment Issues](#2-tracking--alignment-issues)
   - [Highlighting feels slightly delayed or sluggish at word ends](#highlighting-feels-slightly-delayed-or-sluggish-at-word-ends)
   - [User skipped words or an Ayah, but the cursor did not follow](#user-skipped-words-or-an-ayah-but-the-cursor-did-not-follow)
   - [Cursor jumped erratically during repeated verses (Surah Ar-Rahman)](#cursor-jumped-erratically-during-repeated-verses-surah-ar-rahman)
   - [Why does Auto Re-anchor not work in Tajweed Mode?](#why-does-auto-re-anchor-not-work-in-tajweed-mode)
3. [Tajweed Verification Issues](#3-tajweed-verification-issues)
   - [Madd is constantly flagged as underheld (نقص في المد)](#madd-is-constantly-flagged-as-underheld)
   - [Legitimate stops at verse ends (*المد العارض للسكون*) flagged as errors](#legitimate-stops-at-verse-ends-flagged-as-errors)
4. [Voice Search & Navigation Issues](#4-voice-search--navigation-issues)
   - [First search takes 1-2 seconds on low-end devices](#first-search-takes-1-2-seconds-on-low-end-devices)
   - [Reciting *A'udhu Billah* or *Bismillah* confuses search results](#reciting-audhu-billah-or-bismillah-confuses-search-results)
5. [Memory, Isolates & Performance](#5-memory-isolates--performance)
   - [High CPU / Battery drain during extended recitation](#high-cpu--battery-drain-during-extended-recitation)
   - [UI jank or frame drops during fast recitation](#ui-jank-or-frame-drops-during-fast-recitation)

---

## 1. Audio & Microphone Issues

### Microphone is silent or fails to record on Android
**Cause:** Android 13+ requires explicit runtime permission checks before initiating recording streams. On Android 14, if recording while the screen is locked or in the background, a foreground service type `microphone` is required.
**Solution:**
1. Call `await audioProcessor.hasPermission()` before starting the stream.
2. In `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.RECORD_AUDIO" />
   ```

### Microphone drops audio when Bluetooth AirPods connect
**Cause:** iOS switches the audio route to Bluetooth SCO (which defaults to low-fidelity 8kHz mono telephone quality) unless wideband speech is configured.
**Solution:** `AudioProcessor` automatically handles sample rate alignment. If overriding audio sessions manually, ensure `AVAudioSessionCategoryOptions.allowBluetoothA2DP` is specified.

### Hams letters and quiet breath consonants are missed
**Cause:** Standard mobile hardware audio filters (Acoustic Echo Cancellation and Noise Suppression) misinterpret breath friction as background air conditioning or room hiss and mute it.
**Solution:** Use `AudioProcessor`, which explicitly disables `echoCancel: false`, `noiseSuppress: false`, and `autoGain: false`.

---

## 2. Tracking & Alignment Issues

### Highlighting feels slightly delayed or sluggish at word ends
**Cause:** `enableEarlyMatching` is turned off. Without early matching, the engine waits for the reciter to pronounce the trailing short vowel (*Harakah*) and acoustic pause before committing the word.
**Solution:** Ensure `enableEarlyMatching: true` in your `TrackerConfig`:
```dart
config: const TrackerConfig(
  enableEarlyMatching: true, // Commits word on root letters
)
```

### User skipped words or an Ayah, but the cursor did not follow
**Cause:** Either `enableAutoReanchor` is `false` (default for precision/exam safety), or the reciter has only spoken a couple of short phonemes that have not reached the stall threshold.
**Solution:** Set `enableAutoReanchor: true` in `TrackerConfig` and ensure `isTajweed: false`:
```dart
config: const TrackerConfig(
  enableAutoReanchor: true,
  reanchorStallThreshold: 24, // Recovers within 3-4 skipped words
)
```

### Cursor jumped erratically during repeated verses (Surah Ar-Rahman)
**Cause:** Using an outdated sequencer without the **Anti-Ambiguity Guard**.
**Solution:** In `recite_quran` v1.0.4+, the sequencer implements the Anti-Ambiguity Guard: if candidate jump targets have near-identical edit distances ($\Delta\text{dist} < 3$), the jump is automatically suppressed until following unique verse tokens arrive.

### Why is `enableAutoReanchor` false by default, and should I enable it in my app?
**Author's Context:**
The package author originally defaulted `enableAutoReanchor` to `false` out of conservative caution—wishing to avoid unexpected jumps during strict memorization exams or edge-case recitation stumbles before testing across huge user cohorts.

**Strong Recommendation:**
**YES! For any Quran reader, Tilawah, or consumer Mus'haf app, you are strongly encouraged to enable it (`enableAutoReanchor: true`).**
The engine includes state-of-the-art protections against false jumps:
- **Anti-Ambiguity Guard ($\Delta\text{dist} < 3$):** If the user recites repeated verses (such as *فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ* in Surah Ar-Rahman), the engine detects ambiguous candidates and suppresses the jump until unique verse text is recited.
- **Multi-Stage Window Probing:** Evaluates the entire unconsumed speech buffer across verse boundaries.
- **Stall Threshold:** Jumps only trigger after 24 unconsumed phonemes ($\approx 3\text{--}5$ words), preventing transient microphone noise from triggering jumps.

### Why does Auto Re-anchor not work in Tajweed Mode?
**Explanation:** This is by scholarly design (*أمانة شرعية*). Tajweed mode is an educational evaluation session. If a student skips an Ayah, the skipped words must be flagged in **Red** as an omission rather than silently forgiving the skip. Auto re-anchor is exclusive to Dictation Mode (`isTajweed: false`).

---

## 3. Tajweed Verification Issues

### Madd is constantly flagged as underheld (نقص في المد)
**Cause:** The reciter recites at a fast conversational tempo (*Hadr*), but the engine is calibrated to slow, deliberate recitation (*Tahqiq*).
**Solution:** Match the speed tier in `TrackerConfig` to the user's reading pace:
```dart
// For Taraweeh or fast revision:
config: TrackerConfig.fast(
  speed: RecitationSpeed.fast, // 100ms per Harakah
)
```

### Legitimate stops at verse ends flagged as errors
**Explanation:** In Tajweed, stopping at a verse boundary (*Waqf*) permits reciting *Al-Madd Al-Aared Lissukun* in 2, 4, or 6 Harakat (*Qasr, Tawassut, or Tool*).
**Solution:** The engine automatically validates all three lengths as valid (`TajweedDurationStatus.valid`) when the reciter stops at the verse boundary.

---

## 4. Voice Search & Navigation Issues

### First search takes 1-2 seconds on low-end devices
**Cause:** Building the Myers 64-bit bit-parallel bitmasks across all 6,236 Ayahs on first query.
**Solution:** Call `preloadIndex()` during app splash or startup:
```dart
// Run during app initialization:
await voiceSearchController.preloadIndex();
```
Subsequent searches will execute in $< 5\text{ ms}$.

### Reciting *A'udhu Billah* or *Bismillah* confuses search results
**Explanation:** `VoiceSearchController` automatically detects and strips Isti'adha (*أعوذ بالله من الشيطان الرجيم*) and Basmalah prefixes, searching only the core verse text.

---

## 5. Memory, Isolates & Performance

### High CPU / Battery drain during extended recitation
**Cause:** Re-instantiating `ReciteQuran` or the background isolate every time the user turns a page or switches a Surah.
**Solution:** **Never destroy and recreate the engine per chapter!** Instantiate `ReciteQuran` once for the lifetime of the reader session, and simply call `tracker.setTargetSurah(newSurah)` when changing chapters.

### UI jank or frame drops during fast recitation
**Cause:** Rebuilding the entire Mus'haf widget tree on every emitted token.
**Solution:**
1. Wrap individual word widgets in `RepaintBoundary`.
2. Rebuild only the active line or Ayah rather than the entire chapter.
3. Test in Flutter `--release` mode (Dart AOT delivers up to 3x faster execution than debug mode).
