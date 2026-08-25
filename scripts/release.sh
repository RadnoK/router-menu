#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: ./scripts/release.sh <version>   (e.g. 0.1.0)" >&2
  exit 1
fi

APP_NAME="ZTE Menu"
DIST="dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/ZteMenu-$VERSION.zip"
TEAM_ID="7S3F9767BM"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-zte-menu-notary}"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/.local/sparkle/bin}"
APPCAST_DIR="$DIST/appcast"

# SHA-1 hash instead of a name — locally the keychain has two certificates
# with an identical name. In CI the hash is supplied by the workflow after
# importing the .p12.
export SIGN_IDENTITY="${SIGN_IDENTITY:-78189AA14E80C16A00C743B32112F7B6D663D714}"

echo "==> Build + Developer ID signature"
./scripts/build-app.sh

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
