#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Resources/AppIcon.appiconset"
OUT="dist/AppIcon.icns"
WORK="dist/AppIcon.iconset"

if [[ ! -d "$SRC" ]]; then
  echo "Icon directory not found: $SRC" >&2
  exit 1
fi

echo "==> Preparing the iconset"
rm -rf "$WORK"
mkdir -p "$WORK"

# iconutil requires names icon_<size>@2x.png; appiconset uses -2x.png
for png in "$SRC"/icon_*.png; do
  name="$(basename "$png")"
  cp "$png" "$WORK/${name/-2x.png/@2x.png}"
done

echo "==> iconutil -c icns"
mkdir -p dist
iconutil -c icns "$WORK" -o "$OUT"
rm -rf "$WORK"

echo "==> Done: $OUT"
