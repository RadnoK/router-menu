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

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo
echo "==> Gotowe"
echo "    plik:   $ZIP"
echo "    sha256: $SHA"
echo
echo "Następnie:"
echo "  gh release create v$VERSION \"$ZIP\" --title \"ZTE Menu $VERSION\" --generate-notes"
echo "  oraz zaktualizuj version/sha256 w Casks/zte-menu.rb w tapie"
