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

# The frontend translation unit: the amiibo reader has no libretro entry point,
# so App/CoreExtras/AmiiboLink.cpp is compiled against the core's headers and
# merged into the archive beside it. It is compiled with the flags CMake used for
# the core itself (taken from the core target's flags.make) rather than with a
# second, hand-written set, so the sysroot, the deployment target, the standard
# and the include paths cannot drift from the core it links against.
SHIM_SRC="$ROOT/App/CoreExtras/AmiiboLink.cpp"
SHIM_OBJ="$ROOT/build/core-extras/AmiiboLink.cpp.o"
mkdir -p "$(dirname "$SHIM_OBJ")"

FLAGS_FILE="$(find "$BUILD" -path '*CMakeFiles/core.dir/flags.make' -print -quit)"
if [[ -z "$FLAGS_FILE" ]]; then
    FLAGS_FILE="$(find "$BUILD" -path '*/CMakeFiles/*core*.dir/flags.make' -print -quit)"
fi
if [[ -z "$FLAGS_FILE" ]]; then
    echo "error: no flags.make found for the core target" >&2
    exit 1
fi

CXX="$(sed -n 's/^CMAKE_CXX_COMPILER:[A-Za-z]*=//p' "$BUILD/CMakeCache.txt" | head -1)"
if [[ -z "$CXX" ]]; then
    CXX="$(xcrun --find clang++)"
fi
CXX_DEFINES="$(sed -n 's/^CXX_DEFINES = //p' "$FLAGS_FILE")"
CXX_INCLUDES="$(sed -n 's/^CXX_INCLUDES = //p' "$FLAGS_FILE")"
CXX_FLAGS="$(sed -n 's/^CXX_FLAGS = //p' "$FLAGS_FILE")"

echo "Compiling frontend shim with $(basename "$(dirname "$(dirname "$FLAGS_FILE")")") flags ..."
eval "\"$CXX\" $CXX_DEFINES $CXX_INCLUDES $CXX_FLAGS -c \"$SHIM_SRC\" -o \"$SHIM_OBJ\""
if ! nm -g "$SHIM_OBJ" 2>/dev/null | grep -q '_AZCoreAmiiboLoad'; then
    echo "error: $SHIM_OBJ does not define the amiibo entry points" >&2
    exit 1
fi

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

# The frontend shim is an input of its own: it is built above, outside $BUILD,
# precisely so the object patterns above cannot pick it up twice.
echo "$SHIM_OBJ" >> "$LIST"

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

# A cheap sanity check that this is the real library. Both probes read the whole
# stream: with pipefail, stopping a producer early (grep -q) reports SIGPIPE as a
# step failure. The app's link step is the real test either way.
VK_SYMBOLS="$( { strings -a "$OUT/libMoltenVK.a" 2>/dev/null || true; } | grep -c 'vkCreateInstance' || true )"
if [ "${VK_SYMBOLS:-0}" -eq 0 ]; then
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

ENTRY_SYMBOLS="$( { nm -g "$VERIFY/$ENTRY" 2>/dev/null || true; } )"
if ! printf '%s' "$ENTRY_SYMBOLS" | grep -q '_retro_init'; then
    echo "error: $ENTRY does not export retro_init" >&2
    printf '%s\n' "$ENTRY_SYMBOLS" | head -40 >&2
    rm -rf "$VERIFY"
    exit 1
fi

# Same check for the frontend shim: the app calls these three symbols, so a merge
# that dropped the member would fail at link, not at run.
SHIM_MEMBER="$(basename "$SHIM_OBJ")"
if ! ( cd "$VERIFY" && ar -x "$OUT/libazahar_core.a" "$SHIM_MEMBER" ); then
    echo "error: $SHIM_MEMBER is missing from the merged archive" >&2
    rm -rf "$VERIFY"
    exit 1
fi
SHIM_SYMBOLS="$( { nm -g "$VERIFY/$SHIM_MEMBER" 2>/dev/null || true; } )"
if ! printf '%s' "$SHIM_SYMBOLS" | grep -q '_AZCoreAmiiboLoad'; then
    echo "error: $SHIM_MEMBER does not export AZCoreAmiiboLoad" >&2
    printf '%s\n' "$SHIM_SYMBOLS" | head -40 >&2
    rm -rf "$VERIFY"
    exit 1
fi
rm -rf "$VERIFY"

ls -lh "$OUT"/*.a
echo "Core archive ready."
