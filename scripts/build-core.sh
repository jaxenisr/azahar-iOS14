#!/usr/bin/env bash
# Build Azahar's libretro core for iOS 14 arm64, then flatten everything the app
# needs into one static archive: vendor-out/libazahar_core.a
#
# Why a static archive: iOS cannot load dylibs, so the core is linked into the
# app binary. Azahar's CMake only produces a shared core, so instead of editing
# their build files we let it compile with their own flags and then merge the
# resulting objects and static dependencies into a single archive. vendor/azahar
# stays byte-identical to the release tag.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AZ="$ROOT/vendor/azahar"
BUILD="$ROOT/build/core"
OUT="$ROOT/vendor-out"
LOG="$ROOT/build/core-build.log"

if [[ ! -d "$AZ" ]]; then
    echo "error: vendor/azahar missing; run scripts/fetch-azahar.sh first" >&2
    exit 1
fi

mkdir -p "$OUT" "$ROOT/build"
# Everything below is captured so the tail can be recorded if this fails.
exec > >(tee "$LOG") 2>&1

# Flags mirror Azahar's own iOS libretro CI job exactly (that job is the proof
# this compiles), with the deployment target pinned to 14.0 per section 7.
cmake -S "$AZ" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_LIBRETRO=ON \
    -DIOS=ON \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_C_FLAGS=-DIOS \
    -DCMAKE_CXX_FLAGS=-DIOS \
    -DCITRA_USE_PRECOMPILED_HEADERS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_OPT=OFF

cmake --build "$BUILD" --target citra_libretro --config Release -j "$(sysctl -n hw.ncpu)"

# Objects of the libretro entry point and its OBJECT library, plus every static
# archive Azahar and its dependency libraries produced (core, video_core,
# audio_core, fmt, sirit, dds-ktx, MoltenVK, ...).
echo "Collecting objects and archives ..."
LIST="$(mktemp)"
{
    find "$BUILD/CMakeFiles" -path '*citra_libretro*.dir*' -name '*.o' -print
    find "$BUILD" -name '*.a' \
        -not -path '*CMakeFiles/CMakeScratch*' \
        -not -path '*CMakeFiles/CMakeTmp*' \
        -not -path '*CMakeFiles/CMakeFiles*' -print
} | sort -u > "$LIST"

count="$(wc -l < "$LIST" | tr -d ' ')"
echo "Merging $count inputs into $OUT/libazahar_core.a"

rm -f "$OUT/libazahar_core.a"
if ! libtool -static -o "$OUT/libazahar_core.a" $(cat "$LIST"); then
    echo "error: libtool failed to merge objects" >&2
    exit 1
fi

if ! nm "$OUT/libazahar_core.a" 2>/dev/null | grep -q '_retro_init'; then
    echo "error: merged archive does not export retro_init" >&2
    exit 1
fi

ls -lh "$OUT/libazahar_core.a"
echo "Core archive ready."
