#!/usr/bin/env python3
"""
Sync Android to Web Automation Script for ReciteQuran
Author: Antigravity AI Assistant

Usage:
    python sync_android_to_web.py [PATH_TO_ANDROID_PROJECT]

Example:
    python sync_android_to_web.py "D:/there is no god unless ALLAH/Playstore/ReciteQuran"
"""

import os
import sys
import shutil
import re
import subprocess
from pathlib import Path

# Color helpers
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def log(msg, color=Colors.OKBLUE):
    print(f"{color}[SYNC] {msg}{Colors.ENDC}")

def log_success(msg):
    print(f"{Colors.OKGREEN}[OK] {msg}{Colors.ENDC}")

def log_warn(msg):
    print(f"{Colors.WARNING}[WARN] {msg}{Colors.ENDC}")

def log_err(msg):
    print(f"{Colors.FAIL}[ERROR] {msg}{Colors.ENDC}")

def find_android_dir(provided_path=None):
    if provided_path and os.path.exists(provided_path):
        return Path(provided_path).resolve()
    
    candidates = [
        Path("../ReciteQuran").resolve(),
        Path("D:/there is no god unless ALLAH/Playstore/ReciteQuran").resolve(),
        Path("../../ReciteQuran").resolve(),
    ]
    for c in candidates:
        if c.exists() and (c / "lib").exists():
            return c
    return None

def main():
    script_dir = Path(__file__).resolve().parent
    android_arg = sys.argv[1] if len(sys.argv) > 1 else None
    android_dir = find_android_dir(android_arg)

    if not android_dir or not android_dir.exists():
        log_err(f"Could not locate Android project root. Please provide the path as an argument.")
        sys.exit(1)

    log(f"Source Android Project: {android_dir}", Colors.HEADER)
    log(f"Target Web Project:     {script_dir}", Colors.HEADER)

    # 1. Pure Dart files to copy directly
    direct_copy_files = [
        "lib/tracking/word/dictation_matcher.dart",
        "lib/tracking/word/phoneme_matrix.dart",
        "lib/tracking/word/quran_normalizer.dart",
        "lib/tracking/tajweed/tajweed_rules.dart",
        "lib/tracking/tajweed/error_explainer.dart",
        "lib/tracking/ayah_search/fuzzy_search.dart",
        "lib/utils/debug_logger.dart",
        "lib/data/quran_data.dart",
    ]

    for rel in direct_copy_files:
        src = android_dir / rel
        dst = script_dir / rel
        if src.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            log_success(f"Copied {rel}")
        else:
            log_warn(f"Source file not found: {src}")

    # 2. voice_search_controller.dart (Fix package import to relative import)
    src_vsc = android_dir / "lib/tracking/ayah_search/voice_search_controller.dart"
    dst_vsc = script_dir / "lib/tracking/ayah_search/voice_search_controller.dart"
    if src_vsc.exists():
        content = src_vsc.read_text(encoding="utf-8")
        content = re.sub(r"import\s+'package:[^/]+/tracking/word/quran_normalizer\.dart';", "import '../word/quran_normalizer.dart';", content)
        dst_vsc.parent.mkdir(parents=True, exist_ok=True)
        dst_vsc.write_text(content, encoding="utf-8")
        log_success("Copied and adapted lib/tracking/ayah_search/voice_search_controller.dart")

    # 3. phonetic_search.dart (Strip dart:io, adapt isolate to compute)
    src_ph = android_dir / "lib/tracking/ayah_search/phonetic_search.dart"
    dst_ph = script_dir / "lib/tracking/ayah_search/phonetic_search.dart"
    if src_ph.exists():
        content = src_ph.read_text(encoding="utf-8")
        # Remove import 'dart:io'; and import 'dart:isolate';
        content = re.sub(r"import\s+'dart:io';\s*", "", content)
        content = re.sub(r"import\s+'dart:isolate';\s*", "", content)
        if "package:flutter/foundation.dart" not in content:
            content = "import 'package:flutter/foundation.dart';\n" + content
        # Remove forceLoadLocalForTest
        content = re.sub(r"/// For testing without Flutter bindings[\s\S]*?void forceLoadLocalForTest[\s\S]*?\n  }\n", "", content)
        # Adapt Isolate.run to compute
        content = re.sub(
            r"await\s+Isolate\.run\(\(\)\s*=>\s*_runSearchIsolated\((.*?)\)\);",
            r"await compute(_runSearchIsolated, \1);",
            content
        )
        dst_ph.parent.mkdir(parents=True, exist_ok=True)
        dst_ph.write_text(content, encoding="utf-8")
        log_success("Processed and adapted lib/tracking/ayah_search/phonetic_search.dart")

    # 4. Model and Asset Sync
    assets_to_sync = [
        "assets/model/ordered_quran_phonemes.json",
        "assets/model/ph_index.npy",
        "assets/model/ref_norm_ph.txt",
        "assets/model/tokens.txt",
        "assets/fonts/HafsSmart_08.ttf",
    ]

    for rel in assets_to_sync:
        src = android_dir / rel
        dst = script_dir / rel
        if src.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            log_success(f"Synced asset: {rel}")

    # 5. Detect ONNX model name in Android project
    android_model_dir = android_dir / "assets/model"
    onnx_files = list(android_model_dir.glob("*.onnx"))
    if onnx_files:
        model_file = onnx_files[0]
        model_name = model_file.name
        log(f"Detected ONNX model in Android: {model_name}")

        # Copy ONNX model to Web assets for local testing
        dst_model = script_dir / f"assets/model/{model_name}"
        shutil.copy2(model_file, dst_model)
        log_success(f"Copied ONNX model: {model_name}")

        # Update sherpa_engine.dart
        sherpa_engine_path = script_dir / "lib/engine/sherpa_engine.dart"
        if sherpa_engine_path.exists():
            eng = sherpa_engine_path.read_text(encoding="utf-8")
            eng = re.sub(r"_writeSherpaAssetToVFS\('.*\.onnx'\.toJS", f"_writeSherpaAssetToVFS('{model_name}'.toJS", eng)
            sherpa_engine_path.write_text(eng, encoding="utf-8")
            log_success(f"Updated lib/engine/sherpa_engine.dart with {model_name}")

        # Update web/sherpa-onnx-asr.js
        sherpa_js_path = script_dir / "web/sherpa-onnx-asr.js"
        if sherpa_js_path.exists():
            sjs = sherpa_js_path.read_text(encoding="utf-8")
            sjs = re.sub(r"onlineZipformer2CtcModelConfig\.model\s*=\s*'\./.*\.onnx';", f"onlineZipformer2CtcModelConfig.model = './{model_name}';", sjs)
            sherpa_js_path.write_text(sjs, encoding="utf-8")
            log_success(f"Updated web/sherpa-onnx-asr.js with {model_name}")

        # Update build.sh
        build_sh_path = script_dir / "build.sh"
        if build_sh_path.exists():
            bsh = build_sh_path.read_text(encoding="utf-8")
            bsh = re.sub(r"rm -f build/web/assets/assets/model/.*\.onnx", f"rm -f build/web/assets/assets/model/{model_name}", bsh)
            build_sh_path.write_text(bsh, encoding="utf-8")
            log_success(f"Updated build.sh with {model_name}")

    # 6. Run Flutter Analyze to verify health
    log("Running flutter analyze...", Colors.HEADER)
    try:
        res = subprocess.run(["flutter", "analyze"], cwd=script_dir, capture_output=True, text=True, shell=True)
        print(res.stdout)
        if res.returncode == 0:
            log_success("All files synchronized and validated with 0 errors!")
        else:
            log_warn("flutter analyze returned warnings or issues. Please review above output.")
    except Exception as e:
        log_warn(f"Could not run flutter analyze automatically: {e}")

if __name__ == "__main__":
    main()
