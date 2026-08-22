#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Użycie: ./scripts/release.sh <wersja>   (np. 0.1.0)" >&2
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

# Hash SHA-1 zamiast nazwy — w keychainie są dwa certyfikaty o identycznej nazwie
export SIGN_IDENTITY="78189AA14E80C16A00C743B32112F7B6D663D714"

echo "==> Build + podpis Developer ID"
./scripts/build-app.sh

echo "==> Pakowanie $ZIP"
rm -f "$ZIP"
# ditto, nie zip — zachowuje metadane bundla i podpis
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Notaryzacja (to może potrwać kilka minut)"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$APP"

echo "==> Ponowne pakowanie po staplingu"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Weryfikacja Gatekeepera"
spctl -a -vvv -t install "$APP"

echo "==> Appcast dla Sparkle"
# generate_appcast czyta cały katalog i podpisuje EdDSA kluczem z keychaina.
# Musi działać po staplingu, żeby objąć ZIP z biletem notaryzacji.
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  echo "Brak generate_appcast w $SPARKLE_BIN" >&2
  echo "Pobierz z https://github.com/sparkle-project/Sparkle/releases i ustaw SPARKLE_BIN" >&2
  exit 1
fi
mkdir -p "$APPCAST_DIR"
cp "$ZIP" "$APPCAST_DIR/"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/RadnoK/zte-menu/releases/download/v$VERSION/" \
  "$APPCAST_DIR"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo
echo "==> Gotowe"
echo "    plik:    $ZIP"
echo "    sha256:  $SHA"
echo "    appcast: $APPCAST_DIR/appcast.xml"
echo
echo "Następnie:"
echo "  1. gh release create v$VERSION \"$ZIP\" --title \"ZTE Menu $VERSION\" --generate-notes"
echo "  2. opublikuj $APPCAST_DIR/appcast.xml na gałęzi gh-pages"
echo "  3. zaktualizuj version/sha256 w Casks/zte-menu.rb w tapie"
