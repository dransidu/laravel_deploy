#!/usr/bin/env bash
# =============================================================
# 04_ssl.sh — Paste Cloudflare Origin Certificate + Private Key
# Requires: APP_NAME, SSL_DIR_CERT, SSL_DIR_KEY,
#           ORIGIN_CERT_PATH, ORIGIN_KEY_PATH
# =============================================================

echo ""
echo "=== SSL — Cloudflare Origin Certificate ==="

mkdir -p "${SSL_DIR_CERT}" "${SSL_DIR_KEY}"
chmod 700 "${SSL_DIR_KEY}"

# ---------------------------------------------------------------
# Certificate
# ---------------------------------------------------------------
echo ""
echo "PASTE your Cloudflare Origin CERTIFICATE below (multi-line)."
echo "When you are done, type  ENDCERT  on its own line and press Enter."
echo ""

CERT_TMP="$(mktemp)"

while IFS= read -r line </dev/tty; do
  [[ "$line" == "ENDCERT" ]] && break
  printf "%s\n" "$line" >> "$CERT_TMP"
done

if ! grep -q "BEGIN CERTIFICATE" "$CERT_TMP"; then
  echo "ERROR: Certificate paste looks invalid (missing BEGIN CERTIFICATE header)."
  rm -f "$CERT_TMP"
  exit 1
fi

# ---------------------------------------------------------------
# Private Key
# ---------------------------------------------------------------
echo ""
echo "PASTE your Cloudflare Origin PRIVATE KEY below (multi-line)."
echo "When you are done, type  ENDKEY  on its own line and press Enter."
echo ""

KEY_TMP="$(mktemp)"

while IFS= read -r line </dev/tty; do
  [[ "$line" == "ENDKEY" ]] && break
  printf "%s\n" "$line" >> "$KEY_TMP"
done

if ! grep -q "BEGIN" "$KEY_TMP"; then
  echo "ERROR: Private key paste looks invalid (missing BEGIN header)."
  rm -f "$CERT_TMP" "$KEY_TMP"
  exit 1
fi

# ---------------------------------------------------------------
# Install files with correct permissions
# ---------------------------------------------------------------
install -m 644 "$CERT_TMP" "$ORIGIN_CERT_PATH"
install -m 600 "$KEY_TMP"  "$ORIGIN_KEY_PATH"
rm -f "$CERT_TMP" "$KEY_TMP"

echo ""
echo "Saved certificate : ${ORIGIN_CERT_PATH}"
echo "Saved private key : ${ORIGIN_KEY_PATH}"
