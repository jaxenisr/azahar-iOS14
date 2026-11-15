#!/usr/bin/env bash
# Section 7 verification gate. Fails the build if anything in the bundle could
# stop it launching on iOS 14.7.1.
#
#   - every Mach-O must be arm64 only (no arm64e, no x86_64, no simulator slice)
#   - every Mach-O must declare a minimum OS of 14.0 or lower
#   - no Mach-O may contain LC_DYLD_CHAINED_FIXUPS
#   - no dylib or framework may be shipped, except Apple's Swift-concurrency
#     back-deployment library that the toolchain embeds for targets below iOS 15.
#     That one is allowed only at its exact path, and the per-binary checks below
#     still have to clear it: it is arm64 and its minimum OS is far below 14.0, so
#     it cannot raise the launch floor.
#
# Usage: scripts/verify-binaries.sh Payload/Azahar.app

set -uo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "error: usage: $0 <path to .app>" >&2
    exit 2
fi

# The single exception, by exact bundle-relative path.
ALLOWED_DYLIB="Frameworks/libswift_Concurrency.dylib"

fail=0
checked=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "== dylibs / frameworks in bundle =="
while IFS= read -r -d '' f; do
    rel="${f#"$APP"/}"
    if [[ "$rel" == "$ALLOWED_DYLIB" ]]; then
        echo "OK: $rel  (Apple Swift concurrency back-deployment, checked below)"
        continue
    fi
    echo "FAIL: bundled $rel"
    fail=1
done < <(find "$APP" \( -name '*.dylib' -o -name '*.framework' \) -print0)
if [[ "$fail" -eq 0 ]]; then
    echo "(nothing else bundled)"
fi

echo
echo "== per-binary checks =="
while IFS= read -r -d '' f; do
    file "$f" | grep -q 'Mach-O' || continue
    checked=$((checked + 1))
    rel="${f#"$APP"/}"

    archs="$(lipo -archs "$f" 2>/dev/null || echo unknown)"
    if [[ "$archs" != "arm64" ]]; then
        echo "FAIL arch   $rel  ($archs)"
        fail=1
    fi

    otool -l "$f" > "$tmp/loadcommands" 2>/dev/null

    # Minimum OS: LC_BUILD_VERSION minos, else legacy LC_VERSION_MIN_IPHONEOS.
    minos="$(awk '
        /LC_BUILD_VERSION/ { build=1; next }
        build && /minos/ { print $2; build=0; next }
        /LC_VERSION_MIN_IPHONEOS/ { legacy=1; next }
        legacy && /version/ { print $2; legacy=0; next }
    ' "$tmp/loadcommands" | head -1)"

    if [[ -z "$minos" ]]; then
        echo "FAIL minos  $rel  (no minimum OS load command)"
        fail=1
    else
        highest="$(printf '%s\n14.0\n' "$minos" | sort -V | tail -1)"
        if [[ "$highest" != "14.0" ]]; then
            echo "FAIL minos  $rel  ($minos > 14.0)"
            fail=1
        fi
    fi

    if grep -q 'LC_DYLD_CHAINED_FIXUPS' "$tmp/loadcommands"; then
        echo "FAIL fixups $rel  (LC_DYLD_CHAINED_FIXUPS present)"
        fail=1
    fi

    if command -v dyld_info >/dev/null 2>&1; then
        if dyld_info -fixups "$f" 2>/dev/null | grep -qiE '^[[:space:]]*(0x)?[0-9a-f]+[[:space:]]+0x'; then
            echo "FAIL dyld   $rel  (dyld_info reports fixup chains)"
            fail=1
        fi
    fi

    printf 'ok   %-40s arm64  minos=%s\n' "$rel" "${minos:-?}"
done < <(find "$APP" -type f -print0)

echo
echo "checked $checked Mach-O file(s)"
if [[ "$fail" -ne 0 ]]; then
    echo "VERIFICATION FAILED"
    exit 1
fi
echo "VERIFICATION PASSED"
