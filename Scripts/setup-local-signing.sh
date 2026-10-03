#!/bin/sh
# Run once on this Mac. The private key stays in the user's login keychain.
set -eu
umask 077
signing_name='Grindow Local Development'
keychain=$(security default-keychain -d user | tr -d '"' | sed 's/^ *//')

if security find-certificate -c "$signing_name" "$keychain" >/dev/null 2>&1; then
    if security find-identity -v -p codesigning "$keychain" | grep -F "\"$signing_name\"" >/dev/null; then
        printf '%s\n' 'Grindow signing identity already exists; keeping it.'
        exit 0
    fi
    printf '%s\n' 'A Grindow certificate exists but is not a valid signing identity. Repair it in Keychain Access; do not replace it with a new certificate.' >&2
    exit 1
fi

signing_tmp=$(mktemp -d "${TMPDIR:-/tmp}/grindow-signing.XXXXXX")
trap 'rm -rf "$signing_tmp"' EXIT HUP INT TERM
cat > "$signing_tmp/certificate.cnf" <<'EOF'
[req]
prompt = no
distinguished_name = subject
x509_extensions = signing
[subject]
CN = Grindow Local Development
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
    -config "$signing_tmp/certificate.cnf" \
    -keyout "$signing_tmp/private-key.pem" -out "$signing_tmp/certificate.pem" 2> "$signing_tmp/openssl.log"
/usr/bin/openssl rand -base64 32 > "$signing_tmp/password"
/usr/bin/openssl pkcs12 -export -name "$signing_name" \
    -inkey "$signing_tmp/private-key.pem" -in "$signing_tmp/certificate.pem" \
    -out "$signing_tmp/identity.p12" -passout "file:$signing_tmp/password"
security import "$signing_tmp/identity.p12" -k "$keychain" \
    -P "$(cat "$signing_tmp/password")" -T /usr/bin/codesign
# Trust only this certificate for code signing, in the user's trust settings.
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$signing_tmp/certificate.pem"
security find-identity -v -p codesigning "$keychain" | grep -F "\"$signing_name\""
printf '%s\n' 'Local signing identity installed. Keep this certificate and private key for future builds.'
