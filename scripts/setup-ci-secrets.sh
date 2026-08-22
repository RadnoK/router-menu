#!/usr/bin/env bash
# Jednorazowa konfiguracja sekretów dla workflow Release.
#
# UWAGA: eksportuje materiał kryptograficzny z keychaina do sekretów GitHuba.
# Po tym kroku GitHub Actions może podpisywać kod jako Ty. Uruchamiaj tylko
# na repo, do którego masz pełne zaufanie co do listy współpracowników.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="RadnoK/zte-menu"
CERT_HASH="78189AA14E80C16A00C743B32112F7B6D663D714"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Sekrety zostaną zapisane w repo: $REPO"
read -r -p "Kontynuować? [t/N] " ans
[[ "$ans" == "t" ]] || { echo "Przerwano."; exit 1; }

# --- 1. Certyfikat Developer ID ---------------------------------------------
echo
echo "==> Eksport certyfikatu Developer ID"
echo "    Podaj hasło, którym zaszyfrowany zostanie plik .p12."
echo "    Zapamiętaj je — trafi do sekretu DEVELOPER_ID_P12_PASSWORD."
read -r -s -p "Hasło dla .p12: " P12_PASS; echo
[[ -n "$P12_PASS" ]] || { echo "Hasło nie może być puste." >&2; exit 1; }

# Keychain zapyta o zgodę na eksport klucza prywatnego.
security export -t identities -f pkcs12 -P "$P12_PASS" \
  -o "$WORK/cert.p12" -k login.keychain-db 2>/dev/null || {
    echo "Eksport nieudany. Alternatywa: Keychain Access > Moje certyfikaty >" >&2
    echo "prawy przycisk na 'Developer ID Application' > Eksportuj." >&2
    exit 1
  }

base64 -i "$WORK/cert.p12" | gh secret set DEVELOPER_ID_P12 --repo "$REPO"
printf '%s' "$P12_PASS" | gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$REPO"

# Hasło tymczasowego keychaina na runnerze — losowe, nigdzie indziej nieużywane
openssl rand -base64 24 | tr -d '\n' | gh secret set KEYCHAIN_PASSWORD --repo "$REPO"

# --- 2. Klucz prywatny Sparkle ----------------------------------------------
echo
echo "==> Eksport klucza EdDSA (Sparkle)"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/.local/sparkle/bin}"
"$SPARKLE_BIN/generate_keys" -x "$WORK/sparkle_key" > /dev/null

# Klucz z keychaina musi odpowiadać SUPublicEDKey w bundlu — inaczej
# aktualizacje podpisane w CI zostaną odrzucone przez zainstalowane kopie.
PLIST_PUB="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)"
KEYCHAIN_PUB="$("$SPARKLE_BIN/generate_keys" -p)"
if [[ "$PLIST_PUB" != "$KEYCHAIN_PUB" ]]; then
  echo "BŁĄD: klucz publiczny z keychaina nie zgadza się z Info.plist." >&2
  echo "  Info.plist: $PLIST_PUB" >&2
  echo "  keychain:   $KEYCHAIN_PUB" >&2
  exit 1
fi

# Plik zawiera komentarze; klucz to ostatnia niepusta linia.
grep -v '^#' "$WORK/sparkle_key" | grep -v '^$' | tail -1 \
  | gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO"

echo
echo "    ZRÓB KOPIĘ ZAPASOWĄ tego klucza w menedżerze haseł."
echo "    Bez niego nie wydasz aktualizacji dla zainstalowanych kopii:"
echo
grep -v '^#' "$WORK/sparkle_key" | grep -v '^$' | tail -1
echo

# --- 3. Poświadczenia notaryzacji -------------------------------------------
echo "==> Poświadczenia notaryzacji"
read -r -p "Apple ID: " APPLE_ID
read -r -s -p "Hasło app-specific: " APP_PASS; echo

printf '%s' "$APPLE_ID"   | gh secret set NOTARY_APPLE_ID --repo "$REPO"
printf '%s' "$APP_PASS"   | gh secret set NOTARY_PASSWORD --repo "$REPO"
printf '%s' "7S3F9767BM"  | gh secret set NOTARY_TEAM_ID  --repo "$REPO"

# --- 4. Token do tapa -------------------------------------------------------
echo
echo "==> Token do repozytorium tapa"
echo "    Wymagany fine-grained PAT z uprawnieniem Contents: write"
echo "    dla RadnoK/homebrew-tap (github.com/settings/tokens)."
read -r -s -p "Token: " TAP_TOKEN; echo
printf '%s' "$TAP_TOKEN" | gh secret set TAP_TOKEN --repo "$REPO"

echo
echo "==> Gotowe. Sekrety w repo:"
gh secret list --repo "$REPO"
