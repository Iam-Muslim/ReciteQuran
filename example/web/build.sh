#!/bin/bash
set -e

# 1. Install Flutter if not present (for Cloudflare Pages runner)
if ! command -v flutter &> /dev/null; then
    echo "=== Installing Flutter SDK on Cloudflare Runner ==="
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 $HOME/flutter
    export PATH="$PATH:$HOME/flutter/bin"
    flutter --version
fi

# 2. Build Flutter Web
echo "=== [1/3] Building Flutter Web ==="
mkdir -p assets/model
touch assets/model/zipformer_p_arabic_v3.int8.onnx
flutter pub get
flutter build web --release --base-href "/recite/"

# 3. Copy Flutter App to Landing Page Public Folder
echo "=== [2/3] Copying Flutter App into React Landing Page ==="
mkdir -p landing_page/public/recite
cp -R build/web/* landing_page/public/recite/
rm -f landing_page/public/recite/build.sh

# 4. Copy Cloudflare Functions into place
echo "=== Copying Cloudflare Functions ==="
mkdir -p landing_page/functions
cp web/download-model.js landing_page/functions/download-model.js

mkdir -p functions
cp web/download-model.js functions/download-model.js

# 5. Build React Landing Page
echo "=== [3/3] Building React Landing Page ==="
cd landing_page
npm ci
npm run build
echo "=== Build Complete! Output is in landing_page/dist ==="
