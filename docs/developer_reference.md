# Developer Quick Reference

A fast reference for contributors. For deep explanations, see the other docs.

---

## File Map (What Does What)

| File | One-line role |
|---|---|
| `main.dart` | App root + `_Orchestrator` (owns engine, audio, controller) |
| `audio/audio_processor.dart` | Mic → VAD → 160ms chunks |
| `engine/sherpa_engine.dart` | ONNX model inference (in Isolate) |
| `data/quran_data.dart` | Parse JSON → `QuranVerse` model |
| `state/app_state.dart` | Global settings singleton |
| `tracking/highlighting_controller.dart` | Routes ASR → tracker → UI state |
| `tracking/phonetic_word_tracker.dart` | Streaming Levenshtein DP per-ayah |
| `tracking/quran_normalizer.dart` | Strip harakat, normalize alef variants |
| `tracking/voice_search_controller.dart` | Recite → find Ayah globally |
| `tracking/matchers/phoneme_chunker.dart` | Split phoneme string → groups |
| `tracking/matchers/anchor.dart` | TF-IDF N-gram search |
| `tracking/matchers/error_explainer.dart` | Post-Ayah Tajweed/Tashkeel classification |
| `tracking/matchers/tajweed_rules.dart` | Tajweed Rule engine architecture |

---

## Adding a New Surah

The app loads ALL 6,236 Ayahs at startup from `ordered_quran_phonemes.json`. No per-surah work needed.


---

## Running in Debug Mode

```bash
flutter run
```

Debug prints are prefixed:
- `[ASR]` — Sherpa inference results
- `[Streaming DP]` — Real-time word matching
- `[Tajweed]` — Post-Ayah Tajweed phase
- `[ErrorExplainer]` — Detailed alignment output
- `[VoiceSearch]` — Voice navigation feature
- `[AUDIO]` — VAD events

---

## Key Constants to Know

| Constant | File | Value | Why |
|---|---|---|---|
| `chunkMs` | `audio_processor.dart` | 160ms | Min chunk for ZipFormer model |
| `maxSilenceMs` | `audio_processor.dart` | 800ms | Pause before phrase ends |
| `_windowRadius` | `phonetic_word_tracker.dart` | 25 chars | DP window size |

---

## Word Color Meaning

| Color | Status | Set By |
|---|---|---|
| White | Pending (not yet reached) | Default |
| 🟢 Green | `WordMatchStatus.correct` | Real-time DP |
| 🔴 Red | `WordMatchStatus.wrong` or `.skipped` | Real-time DP |
| 🟡 Yellow | Correct but has Tajweed/Tashkeel error | Post-Ayah `ErrorExplainer` (Tajweed mode only) |

Yellow replaces Green. Red words are NOT checked for Tajweed (they were already wrong).

---

## Architecture Constraints (Don't Break These)

1. **No Tajweed checks in real-time.** `PhoneticWordTracker.feed()` only does green/red. All Tajweed is post-Ayah only.

2. **SherpaEngine runs in an Isolate.** Never call Sherpa methods from the Isolate except through `_sendPort`. Never call Flutter APIs from the Isolate.

3. **VoiceSearchController is fully isolated.** It does not modify any highlighting state. Only calls `setTargetSurah` and `setManualAyah` at the end.

4. **Do not re-add inline Tajweed checking to `PhoneticWordTracker`.** Previous versions had this and it caused false positives from CTC stutter.
