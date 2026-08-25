#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ZTE Menu"
BUNDLE_ID="io.8lines.router-menu"
EXECUTABLE="zte-menu"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> swift build -c release (universal: arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$EXECUTABLE"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Binary not found: $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling bundle $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$EXECUTABLE"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Localizations (en, pl)"
for LPROJ in Resources/*.lproj; do
  cp -R "$LPROJ" "$APP/Contents/Resources/"
done

echo "==> App icon"
./scripts/make-icon.sh
cp "$DIST/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Sparkle.framework"
BUILD_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
SPARKLE_FW="$BUILD_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FW" ]]; then
  echo "Sparkle.framework not found in $BUILD_DIR" >&2
  exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
# -R preserves the symlinks of the versioned framework layout
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"

# The binary links against @rpath — point it at Frameworks inside the bundle
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "$APP/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true

# SIGN_IDENTITY enables Developer ID signing (release); ad-hoc by default (local)
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

FW="$APP/Contents/Frameworks/Sparkle.framework"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "==> Ad-hoc signing"
  codesign --force --deep --sign - "$APP" || echo "Warning: codesign failed (the app still runs locally)"
else
  # Sign inside out — nested code must be signed before its parent, or
  # notarization rejects the package.
  echo "==> Developer ID signature: $SIGN_IDENTITY"
  SIGN=(codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY")

  "${SIGN[@]}" "$FW/Versions/B/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
  "${SIGN[@]}" "$FW/Versions/B/Updater.app"
  "${SIGN[@]}" "$FW/Versions/B/Autoupdate"
  "${SIGN[@]}" "$FW/Versions/B"
  "${SIGN[@]}" "$FW"

  "${SIGN[@]}" --entitlements "Resources/entitlements.plist" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

echo "==> Launch smoke test"
# Nothing else in this pipeline ever runs the assembled app, so a bundle that
# fatal-errors at startup (e.g. a missing SwiftPM resource bundle) used to ship
# silently: the app is LSUIElement, so a dead process looks like "no icon yet".
SMOKE_LOG="$(mktemp -t zte-menu-smoke)"
set +e
"$APP/Contents/MacOS/$EXECUTABLE" >"$SMOKE_LOG" 2>&1 &
SMOKE_PID=$!
sleep 3
kill -0 "$SMOKE_PID" 2>/dev/null
SMOKE_ALIVE=$?
set -e

if [[ "$SMOKE_ALIVE" -ne 0 ]]; then
  wait "$SMOKE_PID" 2>/dev/null || true
  {
    echo "Launch smoke test FAILED: $EXECUTABLE exited within 3 seconds."
    echo "The assembled app crashes on launch and must not be shipped."
    echo "--- output ---"
    cat "$SMOKE_LOG"
    echo "--------------"
    # stderr is often empty here: dispatch assertions and Swift runtime traps
    # log only to the crash report, so surface the newest one.
    sleep 5
    CRASH="$(ls -t "$HOME/Library/Logs/DiagnosticReports/$EXECUTABLE"*.ips 2>/dev/null | head -1)"
    if [[ -n "$CRASH" ]]; then
      echo "--- crash report: $CRASH ---"
      cat "$CRASH"
    else
      echo "(no crash report appeared within 5s)"
    fi
  } >&2
  rm -f "$SMOKE_LOG"
  exit 1
fi

kill "$SMOKE_PID" 2>/dev/null || true
wait "$SMOKE_PID" 2>/dev/null || true
rm -f "$SMOKE_LOG"
echo "    App survived launch (still running after 3s)"

echo "==> Done: $APP"
