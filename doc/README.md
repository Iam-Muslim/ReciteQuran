# 📚 ReciteQuran — Technical Documentation Hub

Welcome to the official developer and AI engineering documentation suite for **`package:recite_quran`**.

Whether you are building a **hands-free Quran reader**, a **Tarteel AI memorization companion**, an **automated Tajweed tutor**, or a **"Shazam for the Quran" voice search tool**, these guides provide deep architectural specifications and ready-to-use Flutter code.

---

## 🗺️ Learning Pathways

###   Track 1: Fast MVP (Hands-Free Dictation & Auto-Scroll)
1. Read [**Dictation Integration Guide**](DICTATION_SYSTEM_GUIDE.md) to understand Early Matching and Auto Re-anchoring (`enableAutoReanchor: true` is strongly recommended for reader apps!).
2. Follow [**Interactive Mus'haf UI & Layout Guide**](MUSHAF_UI_GUIDE.md) to render Uthmanic fonts and auto-scrolling lines.
3. Check [**Production Audio Pipeline Guide**](AUDIO_PIPELINE_GUIDE.md) for microphone capture.

###      Track 2: Advanced Tajweed & Islamic Education
1. Read [**Tajweed Verification Guide**](TAJWEED_GUIDE.md) to master acoustic matrices, Madd rules, Ghunnah, and Shaddah.
2. Read [**Multi-Riwayah Guide**](RIWAYAH_GUIDE.md) to handle 20 Mutawatir Rawis and 6 counting traditions.
3. Review [**API Quick Reference**](API_REFERENCE.md) for `ErrorExplainer` and `TajweedErrorSheet`.

### 🎙️ Track 3: Voice Navigation ("Recite to Navigate")
1. Read [**Voice Search Guide**](VOICE_SEARCH_GUIDE.md) to implement real-time Myers 64-bit Bit-Parallel search across all 6,236 Ayahs.
2. Use the pre-built search modal widget to auto-navigate the Mus'haf as soon as a verse is uniquely identified.

### 🧠 Track 4: Tarteel AI Memorization & Hifdh Testing
1. Read [**Memorization & Mistake Detection Guide**](MEMORIZATION_MODE_GUIDE.md) to implement blind recitation with hidden words and progressive reveal.
2. Use `LcsOmissionDetector` to automatically pinpoint forgotten words with $O(N)$ dynamic programming.

---

## 📑 Complete Guide Index

| Guide | Description | Target Capabilities |
| :--- | :--- | :--- |
| 📖 [**DICTATION_SYSTEM_GUIDE.md**](DICTATION_SYSTEM_GUIDE.md) | Dictation & Hands-Free Reading | Early Matching, Auto Re-anchoring, 24 vs 30 phoneme threshold |
|      [**TAJWEED_GUIDE.md**](TAJWEED_GUIDE.md) | Tajweed Verification Engine | Madd rules, Ghunnah, Shaddah, speed calibration, `ErrorExplainer` |
| 🎙️ [**VOICE_SEARCH_GUIDE.md**](VOICE_SEARCH_GUIDE.md) | "Recite to Navigate" | Myers bit-parallel search across all 6,236 Ayahs in $<5\text{ms}$ |
| 🧠 [**MEMORIZATION_MODE_GUIDE.md**](MEMORIZATION_MODE_GUIDE.md) | Hifdh Testing & Mistake Detection | Blind recitation, hidden words, `LcsOmissionDetector` |
| 🎧 [**AUDIO_PIPELINE_GUIDE.md**](AUDIO_PIPELINE_GUIDE.md) | Production Audio Architecture | 16kHz Float32 streaming, bypassing DSP filters, interruptions |
| 📜 [**MUSHAF_UI_GUIDE.md**](MUSHAF_UI_GUIDE.md) | Mus'haf UI & Typography | 15-line Madani layout, Uthmanic fonts, line centering, page turns |
|     [**RIWAYAH_GUIDE.md**](RIWAYAH_GUIDE.md) | Multi-Riwayah & Multi-Qira'at | 10 Qira'at, 20 Rawis, 6 counting traditions, `QiraatAyahMapper` |
| 📦 [**MODEL_DOWNLOAD_GUIDE.md**](MODEL_DOWNLOAD_GUIDE.md) | Neural Model Deployment | On-demand 69MB download vs manual bundling, offline caching |
| 📱 [**APP_INTEGRATION_GUIDE.md**](APP_INTEGRATION_GUIDE.md) | Full App Integration Architecture | State management (Riverpod/Bloc), lifecycle, 1-file minimal app |
| ⚡ [**API_REFERENCE.md**](API_REFERENCE.md) | API Quick Reference & Cheat Sheet | High-density method signatures, streams, configs, models |
| 🛠️ [**TROUBLESHOOTING_FAQ.md**](TROUBLESHOOTING_FAQ.md) | Debugging & Troubleshooting FAQ | Real-world gotchas, acoustic filters, memory optimization |
