#!/usr/bin/env bash
set -euo pipefail
OUT="assets/icon/app_icon.png"
mkdir -p "$(dirname "$OUT")"
if command -v magick >/dev/null 2>&1; then
  magick -size 512x512 canvas:transparent "$OUT"
elif command -v convert >/dev/null 2>&1; then
  convert -size 512x512 xc:transparent "$OUT"
else
  echo "ImageMagick not found. Attempting to create PNG with Python + Pillow..."
  python3 - <<'PY'
from PIL import Image
img = Image.new('RGBA', (512,512), (0,0,0,0))
img.save('assets/icon/app_icon.png')
PY
fi

echo "Generated $OUT"
