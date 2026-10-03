#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/grindow-burst.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun clang -DCGEventPost=grindow_test_event_post \
  -I Grindow/Vendor/Strafe \
  Tests/Native/BurstTests.c Grindow/Vendor/Strafe/CStrafe.c \
  Grindow/Vendor/Strafe/IOHIDPayload.c \
  -framework ApplicationServices -framework CoreFoundation \
  -o "$test_dir/burst-tests"
"$test_dir/burst-tests"
