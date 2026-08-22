#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ZTE Menu"
BUNDLE_ID="io.8lines.zte-menu"
EXECUTABLE="zte-menu"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$EXECUTABLE"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Nie znaleziono binarki: $BIN_PATH" >&2
  exit 1
fi

echo "==> Składanie bundla $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$EXECUTABLE"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Ikona aplikacji"
./scripts/make-icon.sh
cp "$DIST/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# SIGN_IDENTITY pozwala podpisać Developer ID (release); domyślnie ad-hoc (lokalnie)
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "==> Ad-hoc signing"
  codesign --force --deep --sign - "$APP" || echo "Uwaga: codesign nieudany (można uruchomić i tak lokalnie)"
else
  # Hardened runtime + timestamp są wymagane przez notaryzację
  echo "==> Podpis Developer ID: $SIGN_IDENTITY"
  codesign --force --options runtime --timestamp \
    --entitlements "Resources/entitlements.plist" \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

echo "==> Gotowe: $APP"
