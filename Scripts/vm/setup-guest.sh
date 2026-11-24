#!/bin/sh
# Runs inside the macOS test VM, once (grindow-vm setup sends it). Safe to run again.
# - a signing identity in its own keychain, so every CI build gets the same designated
#   requirement and the Accessibility grant survives reinstalls (see Scripts/LOCAL-SIGNING.md)
# - the Command Line Tools, for `swift` (spaces.swift) and `swift test`
# - Mission Control settings that make Space checks deterministic
set -eu
umask 077
name='Grindow Local Development'
kc="$HOME/Library/Keychains/grindow-vm.keychain-db"
# This keychain holds only a self-signed cert that means nothing outside the VM,
# so its password is not a secret.
kcpass=grindow-vm

if [ ! -f "$kc" ]; then
    security create-keychain -p "$kcpass" "$kc"
    security set-keychain-settings "$kc"            # no auto-lock
    # Add it to the search list, keeping the existing keychains.
    eval "security list-keychains -d user -s \"$kc\" $(security list-keychains -d user | tr '\n' ' ')"
fi
security unlock-keychain -p "$kcpass" "$kc"

if ! security find-certificate -c "$name" "$kc" >/dev/null 2>&1; then
    t=$(mktemp -d)
    trap 'rm -rf "$t"' EXIT
    cat > "$t/c.cnf" <<'EOF'
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
        -config "$t/c.cnf" -keyout "$t/k.pem" -out "$t/c.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -name "$name" -inkey "$t/k.pem" -in "$t/c.pem" \
        -out "$t/i.p12" -passout pass:p12
    security import "$t/i.p12" -k "$kc" -P p12 -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k "$kcpass" "$kc" >/dev/null
fi
echo "signing identity: $(security find-certificate -c "$name" -Z "$kc" | awk '/SHA-1/ {print $3}')"

if ! xcode-select -p >/dev/null 2>&1; then
    echo 'installing the Command Line Tools (several minutes)'
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    label=$(softwareupdate -l 2>/dev/null | sed -n 's/^\* Label: \(Command Line Tools.*\)$/\1/p' | tail -1)
    [ -n "$label" ] || { echo 'no Command Line Tools in softwareupdate -l' >&2; exit 1; }
    sudo softwareupdate -i "$label" --agree-to-license
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
fi
echo "toolchain: $(swift --version 2>&1 | head -1)"

# Spaces stay in the order the test makes them, and Ctrl-1..9 jump to desktops.
defaults write com.apple.dock mru-spaces -bool false
# macOS's three-finger swipes off, as Grindow asks users to do; otherwise it
# skips every swipe (NativeTrackpadGestures) to avoid a double switch.
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 0
killall Dock 2>/dev/null || true
mkdir -p "$HOME/.grindow-vm"
echo 'guest ready'
