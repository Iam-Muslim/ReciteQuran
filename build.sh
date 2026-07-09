#!/bin/bash
set -e

echo "=== Downloading Flutter ==="
git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter
export PATH="$PATH:`pwd`/_flutter/bin"

echo "=== Building Flutter Web (WASM) ==="
flutter pub get
flutter pub run flutter_launcher_icons
flutter build web --wasm --base-href "/recite/"

echo "=== Preparing Landing Page ==="
rm -f build/web/assets/assets/model/quran_phoneme_zipformer.int8.onnx
mkdir -p landing_page/public/recite
cp -R build/web/* landing_page/public/recite/

echo "=== Building React App ==="
cd landing_page
npm ci
npm run build
