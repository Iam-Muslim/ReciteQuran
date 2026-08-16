> *"And We have certainly made the Quran easy for remembrance, so is there any who will remember?"* — Al-Qamar 54:17

  # ما أَسأَلُكُم عَلَيهِ مِن أَجرٍ إِن أَجرِيَ إِلّا عَلىٰ رَبِّ العالَمينَ
before using any single character of codes here , you agree to this :
**For The Sake Of Allah only** if you used this app or the source code in any other work you aren't allowed to get from it any money or make profit from it and you have to mention that this app is for the sake of Allah only .
 (never sell or gain money from any work has any of this project )
 
(1) you may use and redistribute it ONLY in applications that are FREE to end users

(2) you are NOT allowed to sell it, place it behind a paid subscription or paywall, monetize it with ads, or earn any revenue from an app or service that uses this model or its outputs or this app or this codes or logics;

(3) these terms pass on to anyone you share it with.

---

## What Is This Project?

**ReciteQuran** is a Flutter Web Application (with a React Landing Page) that listens to a user reciting the Holy Quran, word by word, and highlights each word as **correct (green)**, **wrong (red)**, or **has a Tajweed error (yellow)**.

It runs **entirely inside the browser on your device via WebAssembly**, with no internet connection needed for audio processing. An Arabic ASR (Automatic Speech Recognition) model runs live, converting your voice into phonetic Arabic text in real-time.

---

## Table of Contents

1. [Elhamdule Allah](#elhamdule-allah)
2. [Monorepo Structure](#monorepo-structure)
3. [How the Architecture Works](#how-the-architecture-works)
4. [The Tajweed Pipeline](#the-tajweed-pipeline--post-ayah)
5. [Voice Navigation — "Recite to Find"](#voice-navigation--recite-to-find)
6. [CI/CD Deployment](#cicd-deployment)

---

## Monorepo Structure

This project is a Monorepo containing two tightly integrated web applications:

```
ReciteQuran/
├── lib/                   # The Core Flutter Web App (Dart)
├── web/                   # Flutter Web output configurations
├── assets/                # Audio models, Quran JSON data, fonts
├── pubspec.yaml           # Flutter dependencies
└── landing_page/          # The React Marketing Site (Vite + Tailwind)
```

- **`landing_page/`**: A beautiful React + Vite frontend that serves as the root domain (e.g. `recitequran.pages.dev`). It features translations, responsive UI, and links users to the actual application.
- **`lib/`**: The Flutter Web app that houses the ASR engine and real-time word tracking. It is served at `/recite` (e.g. `recitequran.pages.dev/recite`).

---

## How the Architecture Works

Think of it like an assembly line running inside the browser:

```
Microphone (Browser API)
    ↓
AudioProcessor (VAD — silence detection + chunking)
    ↓
SherpaEngine (WebAssembly — ONNX model inference via JS Interop)
    ↓
HighlightingController (word-matching brain)
    ↓
PhonemeAlignment (per-ayah DP Levenshtein alignment)
    ↓
UI (TrackingScreen → VerseRow → word highlighting)
```

### Phase 1: Real-Time Green/Red Highlighting

As you speak each word, the `PhonemeAlignmentWeb` uses a **streaming Levenshtein DP** to find where in the reference phoneme list your voice currently is. Because the ASR (Sherpa-ONNX ZipFormer) outputs raw length-encoded characters (like `ااااا`), the algorithm uses a "Zero Cost" bit-shifted lookup table to flawlessly evaluate phonetic equivalents in `O(1)` time without freezing the UI thread. 

When it passes a word boundary, the word turns:
- **Green** → you said it correctly
- **Red** → you skipped or mispronounced it

### Phase 2: Post-Ayah Tajweed Check (Yellow)

When you finish the last word of an Ayah, the app runs a global alignment. The model uses repeated characters to denote the length of sounds (like `نننن` for a 2-beat Ghunnah). The `ErrorExplainer` maps these repeating characters to precise timestamp durations and evaluates them against classes like `MaddRule` and `Ghonnah`. Green words with Tajweed/Tashkeel errors are then turned **yellow**.

---

## Voice Navigation — "Recite to Find"

This feature lets the user **press record** and recite any verse. The app will then automatically navigate to that Surah and Ayah.

Instead of rigid N-grams, the app uses a custom Dynamic Programming (Levenshtein distance) algorithm over the entire Quran phonetic string (`ph_index.txt`). It allows up to a 10% error margin to handle noisy environments, and instantly uses a binary array (`ph_index.npy`) to reveal the exact Surah and Ayah index.

---

## CI/CD Deployment

This repository is configured with a powerful, automated GitHub Actions pipeline (`.github/workflows/cloudflare_pages.yml`) designed for **Cloudflare Pages**.

When you push to the `main` branch, the CI/CD pipeline automatically:
1. Installs Flutter and builds the WebAssembly (`--wasm`) application.
2. Injects the compiled Flutter app into `landing_page/public/recite`.
3. Installs Node.js and builds the React landing page via Vite.
4. Uploads the final combined output directly to Cloudflare Pages.

This guarantees your marketing page and your core application are always perfectly in-sync in production!

---

## Reference Repositories
Elhamdule Allah
This project is built on research and code from the following open-source projects:

| Project | What was ported/adapted |
|---|---|
| [Quran-streaming-model](https://huggingface.co/Muno459/zipformer_p-quran) | Muno459 |
| [quran-transcript](https://github.com/OmarMuhammedAli/quran-transcript) | obadx |
| [qua_sdk](https://huggingface.co/spaces/hetchyy/quranic-universal-aligner) | Hetchy |

# هذا من فضل ربي - ربنا تقبل منا انك انت السميع العليم
