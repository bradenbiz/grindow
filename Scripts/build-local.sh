#!/bin/sh
# Preserve the certificate-backed app identity across all local updates.
set -eu
cd "$(dirname "$0")/.."
signing_name='Grindow Local Development'
if ! security find-identity -v -p codesigning | grep -F "\"$signing_name\"" >/dev/null; then
    printf '%s\n' 'Missing local signing identity. Run sh Scripts/setup-local-signing.sh first.' >&2
    exit 1
fi
derived_data="${GRINDOW_DERIVED_DATA:-${TMPDIR:-/tmp}/grindow-signed-build}"
xcodebuild -project Grindow.xcodeproj -scheme Grindow -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived_data" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$signing_name" \
    CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= build
codesign --verify --deep --strict "$derived_data/Build/Products/Debug/Grindow.app"
mkdir -p build
ditto "$derived_data/Build/Products/Debug/Grindow.app" build/Grindow.app
codesign --verify --deep --strict build/Grindow.app
codesign -d -r- build/Grindow.app
