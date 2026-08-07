#!/bin/bash
# One-time setup: make a self-signed code-signing certificate so every build
# carries the same signature. Without it the app is ad-hoc signed, the
# signature changes each build, and the Keychain asks for your password again.
set -euo pipefail

CERT_NAME="${CERT_NAME:-HarvestButGood Dev}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    echo "Certificate \"$CERT_NAME\" already exists. Nothing to do."
    exit 0
fi

cat > "$WORK_DIR/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = $CERT_NAME

[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" \
    -config "$WORK_DIR/cert.cnf" 2>/dev/null

# Apple's importer only reads the old PKCS#12 encryption, and it rejects an
# empty password, so use SHA1/3DES with a throwaway one.
P12_PASSWORD="harvestbutgood"
# OpenSSL 3 hides the old ciphers behind -legacy; LibreSSL has no such flag.
LEGACY_FLAG=""
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    LEGACY_FLAG="-legacy"
fi
openssl pkcs12 -export -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" \
    -out "$WORK_DIR/cert.p12" -passout "pass:$P12_PASSWORD" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES ${LEGACY_FLAG:-}

security import "$WORK_DIR/cert.p12" -k ~/Library/Keychains/login.keychain-db \
    -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security

echo "Marking the certificate as trusted (needs your admin password once)…"
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain "$WORK_DIR/cert.pem"

echo
echo "Done. \"$CERT_NAME\" will now be used by Scripts/build-app.sh."
echo "The first launch after this still asks for the Keychain once — click"
echo "\"Always Allow\" and later builds will stay quiet."
