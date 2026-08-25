#!/usr/bin/env bash
# Creates the signing keystore used by the APK build, and prints the four
# GitHub secrets to paste into the repository.
#
# Run this once. Keep the generated .keystore file — if it is lost, future
# builds can no longer install over an already-installed copy of the app.
set -euo pipefail

OUT="${1:-glory-bees-orders-release.keystore}"
ALIAS="${ALIAS:-glorybees}"

if [[ -e "$OUT" ]]; then
  echo "Refusing to overwrite existing keystore: $OUT" >&2
  exit 1
fi

read -rsp "Choose a keystore password (remember it): " STORE_PASSWORD
echo

keytool -genkeypair \
  -keystore "$OUT" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "$STORE_PASSWORD" \
  -keypass "$STORE_PASSWORD" \
  -dname "CN=Glory Bees Sewing Center, OU=Orders App, O=Glory Bees, C=US"

echo
echo "Keystore written to: $OUT"
echo "Add these under GitHub → Settings → Secrets and variables → Actions:"
echo
echo "  KEY_ALIAS        $ALIAS"
echo "  KEY_PASSWORD     (the password you just chose)"
echo "  STORE_PASSWORD   (the same password)"
echo "  KEYSTORE_BASE64  the single line below"
echo
base64 -w0 "$OUT" 2>/dev/null || base64 "$OUT" | tr -d '\n'
echo
