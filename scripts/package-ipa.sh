#!/usr/bin/env bash
# Package the built app as an ad-hoc signed IPA for TrollStore, then run the
# section 7 verification gate over the bundle that will actually be installed.
#
# Signing is last and uses an ad-hoc identity: no certificate, no profile, no team.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCTS="$ROOT/build/dd/Build/Products/Release-iphoneos"

echo "== products =="
ls -la "$PRODUCTS" || true

APP="$(find "$PRODUCTS" -maxdepth 1 -name '*.app' -print | head -1)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "error: no .app found under $PRODUCTS" >&2
    exit 1
fi
echo "App: $APP"
echo "Executable: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>&1 || true)"
du -sh "$APP"

rm -rf "$ROOT/Payload" "$ROOT/Azahar.ipa"
mkdir -p "$ROOT/Payload"
BUNDLE="$ROOT/Payload/$(basename "$APP")"

echo "== copy =="
ditto "$APP" "$BUNDLE"

echo "== sign =="
xattr -cr "$BUNDLE"
codesign --force --sign - --timestamp=none --verbose=2 "$BUNDLE"
# --deep so the embedded back-deployment library is checked too.
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

echo "== zip =="
( cd "$ROOT" && zip -qry Azahar.ipa Payload )
ls -lh "$ROOT/Azahar.ipa"

echo "== verify =="
bash "$ROOT/scripts/verify-binaries.sh" "$BUNDLE"
