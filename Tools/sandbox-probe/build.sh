#!/bin/sh
# Builds sbtest on the device (needs clang + the iOS 6.1 SDK from Theos, and ldid).
SDK="${SDK:-$THEOS/sdks/iPhoneOS6.1.sdk}"
set -e
clang -arch armv7 -isysroot "$SDK" -miphoneos-version-min=6.0 -O1 -Wall sbtest.c -o sbtest
ldid -S sbtest
chmod 755 sbtest
echo "built ./sbtest  (run as mobile:  ./sbtest [python3 [extra-dir ...]])"
