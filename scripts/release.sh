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

# generate_appcast describes ONLY the archives present in the directory, and
# CI starts from an empty checkout — so without this the appcast is rewritten
# with a single item and every other release disappears from it. That went
# unnoticed while each release was a stable one replacing the previous stable
# entry; a beta replacing the stable entry left users with no update at all.
# Re-download the published archives so the generated feed keeps its history.
echo "==> Fetching published releases for the appcast"
# Hard-fail rather than `|| true`: a feed that lists only the new version
# strands every existing install on "no update available", and that is far
# worse than a failed release. CI supplies GH_TOKEN for this.
if ! PREVIOUS_TAGS="$(gh release list --limit 30 --json tagName -q '.[].tagName' \
     | grep -v "^v$VERSION$")"; then
  echo "Could not list previous releases — refusing to publish an appcast" >&2
  echo "that would drop every other version. Is GH_TOKEN set?" >&2
  exit 1
fi
for TAG in $PREVIOUS_TAGS; do
  gh release download "$TAG" --dir "$APPCAST_DIR" --pattern 'RouterMenu-*.zip' \
    --clobber 2>/dev/null || echo "    (no archive on $TAG, skipping)"
done

# A pre-release and the release it became share a CFBundleVersion, and
# generate_appcast refuses a directory holding two archives with the same
# bundle version. The final release supersedes its own betas, so drop them.
BASE="${VERSION%%-*}"
if [[ "$VERSION" != *-* ]]; then
  rm -f "$APPCAST_DIR/RouterMenu-$BASE-"*.zip 2>/dev/null || true
fi

# A hyphen in the version marks a pre-release (0.7.0-beta.1). Those are
# published on Sparkle's "beta" channel, which only users who opted into it in
# Settings are offered; a channel-less item is what everybody receives. This is
# what keeps a test build from being pushed to every existing install.
cp "$ZIP" "$APPCAST_DIR/"
# Every archive lives under its own tag, so a single --download-url-prefix
# cannot address them all. `--link-prefix-format` is not available here, so the
# per-item URLs are rewritten after generation instead.
URL_PREFIX="https://github.com/RadnoK/router-menu/releases/download/v$VERSION/"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  # CI: key from the secret via stdin, the runner's keychain doesn't have it
  echo "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" \
    --ed-key-file - --download-url-prefix "$URL_PREFIX" \
    --maximum-versions 0 "$APPCAST_DIR"
else
  # Locally: the private key lives in the keychain
  "$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$URL_PREFIX" \
    --maximum-versions 0 "$APPCAST_DIR"
fi

# Two fixes generate_appcast cannot express, both per-item:
#  * it applies ONE --download-url-prefix to every entry, which 404s for older
#    versions that live under their own tag;
#  * --channel tags the whole directory, so it marked the stable releases as
#    beta too — which would hide them from everyone on the stable channel.
python3 - "$APPCAST_DIR/appcast.xml" <<'PYEOF'
import re, sys

path = sys.argv[1]
with open(path) as handle:
    feed = handle.read()

def version_of(item):
    found = re.search(r"<sparkle:shortVersionString>([^<]+)", item)
    return found.group(1) if found else None

def fix_item(match):
    item = match.group(0)
    version = version_of(item)
    if not version:
        return item

    # Every archive lives under its own tag.
    item = re.sub(
        r'(url=")[^"]*/(RouterMenu-[^"/]+\.zip)',
        lambda m: (f'{m.group(1)}https://github.com/RadnoK/router-menu/'
                   f'releases/download/v{version}/{m.group(2)}'),
        item)

    # A hyphen marks a pre-release; only those carry a channel. An item with
    # no channel is the one every user is offered.
    item = re.sub(r"\s*<sparkle:channel>[^<]*</sparkle:channel>", "", item)
    if "-" in version:
        item = item.replace(
            "</item>",
            "    <sparkle:channel>beta</sparkle:channel>\n        </item>")
    return item

feed = re.sub(r"<item>.*?</item>", fix_item, feed, flags=re.S)

with open(path, "w") as handle:
    handle.write(feed)
print("    per-tag download URLs; beta channel on pre-releases only")
PYEOF

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
