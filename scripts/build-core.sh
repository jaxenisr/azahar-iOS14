#!/usr/bin/env bash
# Build Azahar's libretro core for iOS 14 arm64, then flatten everything the app
# needs into one static archive: vendor-out/libazahar_core.a
#
# Why a static archive: iOS cannot load dylibs, so the core is linked into the
# app binary. Azahar's CMake only produces a shared core, so instead of editing
# their build files we let it compile with their own flags and then merge the
# resulting objects and static dependencies into a single archive. vendor/azahar
# stays byte-identical to the release tag.
#
# MoltenVK stays a separate archive. libtool folds an input archive in as a
# single member when it is handed one, and the linker cannot resolve symbols out
# of a nested archive, so the app links it directly with -lMoltenVK.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AZ="$ROOT/vendor/azahar"
BUILD="$ROOT/build/core"
OUT="$ROOT/vendor-out"
ENTRY="citra_libretro.cpp.o"

if [[ ! -d "$AZ" ]]; then
    echo "error: vendor/azahar missing; run scripts/fetch-azahar.sh first" >&2
    exit 1
fi

mkdir -p "$OUT"

# Flags mirror Azahar's own iOS libretro CI job (which proves this compiles),
# with the deployment target pinned to 14.0 as required by section 7.
cmake -S "$AZ" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_LIBRETRO=ON \
    -DIOS=ON \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_C_FLAGS=-DIOS \
    -DCMAKE_CXX_FLAGS=-DIOS \
    -DCITRA_USE_PRECOMPILED_HEADERS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_OPT=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_QT=OFF \
    -DENABLE_SDL2=OFF

cmake --build "$BUILD" --target citra_libretro --config Release -j "$(sysctl -n hw.ncpu)"

# Objects of the libretro entry point and its object libraries, plus every static
# archive Azahar and its dependency libraries produced (core, video_core,
# audio_core, fmt, sirit, dds-ktx, ...).
#
# The libretro targets live in a subdirectory, so their objects sit under
# build/core/src/citra_libretro/CMakeFiles/<target>.dir/ rather than at the top
# level; gather them by target instead of by a fixed path.
echo "Collecting objects and archives ..."
LIST="$(mktemp)"
{
    find "$BUILD" -path '*CMakeFiles/citra_libretro*.dir/*' -name '*.o' -print
    # Static archives from Azahar and its dependencies, minus the libretro ones:
    # that code is already present as the objects collected above, and merging
    # both would duplicate members.
    find "$BUILD" -name '*.a' \
        -not -name '*citra_libretro*' \
        -not -path '*CMakeFiles/CMakeScratch*' \
        -not -path '*CMakeFiles/CMakeTmp*' \
        -not -path '*CMakeFiles/CMakeFiles*' -print
} | sort -u > "$LIST"

count="$(wc -l < "$LIST" | tr -d ' ')"
echo "Merging $count inputs into $OUT/libazahar_core.a"

if ! grep -q "/${ENTRY}\$" "$LIST"; then
    echo "error: the libretro entry point object was not collected" >&2
    grep -i 'citra_libretro' "$LIST" | head -20 >&2 || true
    exit 1
fi

rm -f "$OUT/libazahar_core.a"
LIBTOOL_LOG="$ROOT/build/libtool.log"
if ! libtool -static -o "$OUT/libazahar_core.a" $(cat "$LIST") > "$LIBTOOL_LOG" 2>&1; then
    echo "error: libtool failed to merge objects" >&2
    tail -20 "$LIBTOOL_LOG" >&2
    exit 1
fi
tail -5 "$LIBTOOL_LOG" || true
echo "members: $(ar -t "$OUT/libazahar_core.a" | wc -l | tr -d ' ')"

# MoltenVK. Azahar links it only for its own Qt/SDL builds, not for libretro
# targets, so the frontend supplies the Vulkan implementation.
MOLTENVK="$(find "$ROOT/vendor" -path '*ios-arm64*' -name 'libMoltenVK.a' -print 2>/dev/null | sort | head -1 || true)"
if [ -z "$MOLTENVK" ]; then
    MOLTENVK="$(find "$ROOT/vendor" -name 'libMoltenVK.a' -print 2>/dev/null | sort | head -1 || true)"
fi
if [ -z "$MOLTENVK" ]; then
    echo "error: libMoltenVK.a not found; Vulkan would fail to link" >&2
    exit 1
fi
cp "$MOLTENVK" "$OUT/libMoltenVK.a"
echo "MoltenVK: $OUT/libMoltenVK.a"

# nm output for Mach-O is not always available in this container, and the app's
# link step is the real test; this only catches an obviously wrong file.
if ! { nm -g "$OUT/libMoltenVK.a" 2>/dev/null || strings -a "$OUT/libMoltenVK.a"; } \
    | grep -q 'vkCreateInstance'; then
    echo "error: $OUT/libMoltenVK.a does not mention vkCreateInstance" >&2
    exit 1
fi

# Verify the libretro entry point in its own member. Scanning the whole archive is
# unreliable at this size: nm stops partway through the members and reports
# nothing useful.
VERIFY="$(mktemp -d)"
if ! ( cd "$VERIFY" && ar -x "$OUT/libazahar_core.a" "$ENTRY" ); then
    echo "error: $ENTRY is missing from the merged archive" >&2
    rm -rf "$VERIFY"
    exit 1
fi

if ! nm -g "$VERIFY/$ENTRY" | grep -q '_retro_init'; then
    echo "error: $ENTRY does not export retro_init" >&2
    nm -g "$VERIFY/$ENTRY" | head -40 >&2 || true
    rm -rf "$VERIFY"
    exit 1
fi
rm -rf "$VERIFY"

ls -lh "$OUT"/*.a
echo "Core archive ready."
