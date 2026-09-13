#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: ./scripts/release.sh <version>   (e.g. 0.1.0)" >&2
  exit 1
fi

APP_NAME="Router Menu"
DIST="dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/RouterMenu-$VERSION.zip"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-zte-menu-notary}"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/.local/sparkle/bin}"
APPCAST_DIR="$DIST/appcast"

# The SHA-1 hash, not the name — a keychain can hold several certificates
# sharing one name, and codesign refuses an ambiguous match. Resolved from
# whatever Developer ID this machine holds, so the script needs no edit to
# run on someone else's Mac. CI supplies SIGN_IDENTITY after importing its
# .p12; set it by hand to pick a specific certificate.
# bash 3.2 (the macOS system shell) has no mapfile, so collect by hand.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  FOUND="$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" || true)"
  COUNT="$(printf '%s' "$FOUND" | grep -c . || true)"
  if [[ "$COUNT" -eq 0 ]]; then
    echo "No 'Developer ID Application' certificate in the keychain." >&2
    echo "Install one, or set SIGN_IDENTITY to its SHA-1 hash." >&2
    exit 1
  elif [[ "$COUNT" -gt 1 ]]; then
    echo "Several Developer ID certificates found:" >&2
    echo "$FOUND" >&2
    echo "Set SIGN_IDENTITY to the hash of the one to use." >&2
    exit 1
  fi
  SIGN_IDENTITY="$(printf '%s' "$FOUND" | awk '{print $2}')"
fi
export SIGN_IDENTITY

# project.yml drives the generated Info.plists, so the tag and the manifest
# must agree before anything is built.
YML_VERSION="$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml \
  | head -1 | sed -E 's/.*"(.*)".*/\1/')"
if [[ "$YML_VERSION" != "$VERSION" ]]; then
  echo "Version mismatch: asked for $VERSION, project.yml says $YML_VERSION." >&2
  echo "Update MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml." >&2
  exit 1
fi

echo "==> Build + Developer ID signature"
./scripts/build-app.sh

# Notarization staples the outer bundle, but the service rejects a package
# whose nested code is unsigned or signed with the wrong identity — and a
# widget that fails Gatekeeper simply never loads, with no visible error.
APPEX="$APP/Contents/PlugIns/RouterMenuWidget.appex"
if [[ ! -d "$APPEX" ]]; then
  echo "No widget extension in the bundle — nothing would appear in Notification Center." >&2
  exit 1
fi
codesign --verify --strict --verbose=2 "$APPEX"

echo "==> Packaging $ZIP"
rm -f "$ZIP"
# ditto, not zip — preserves the bundle's metadata and signature
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Notarization (this may take a few minutes)"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$APP"

echo "==> Repackaging after stapling"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Gatekeeper verification"
spctl -a -vvv -t install "$APP"
# The staple covers nested code too; checking the appex separately is what
# catches an extension that was signed but never notarized.
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Appcast for Sparkle"
# generate_appcast reads the whole directory and signs with the EdDSA key from
# the keychain. It must run after stapling, so it covers the ZIP with the
# notarization ticket.
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  echo "generate_appcast not found in $SPARKLE_BIN" >&2
  echo "Download it from https://github.com/sparkle-project/Sparkle/releases and set SPARKLE_BIN" >&2
  exit 1
fi
mkdir -p "$APPCAST_DIR"
cp "$ZIP" "$APPCAST_DIR/"
URL_PREFIX="https://github.com/RadnoK/router-menu/releases/download/v$VERSION/"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  # CI: key from the secret via stdin, the runner's keychain doesn't have it
  echo "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" \
    --ed-key-file - --download-url-prefix "$URL_PREFIX" "$APPCAST_DIR"
else
  # Locally: the private key lives in the keychain
  "$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$URL_PREFIX" "$APPCAST_DIR"
fi

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo
echo "==> Done"
echo "    file:    $ZIP"
echo "    sha256:  $SHA"
echo "    appcast: $APPCAST_DIR/appcast.xml"
echo
echo "Next:"
echo "  1. gh release create v$VERSION \"$ZIP\" --title \"Router Menu $VERSION\" --generate-notes"
echo "  2. publish $APPCAST_DIR/appcast.xml on the gh-pages branch"
echo "  3. update version/sha256 in Casks/router-menu.rb in the tap"
