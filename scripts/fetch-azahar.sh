#!/usr/bin/env bash
# Fetch the pinned Azahar release into vendor/azahar.
#
# Azahar is a dependency, never a fork: this script only checks out a release
# tag and its submodules. Nothing in vendor/ is edited by this project, and
# nothing in vendor/ is committed (see .gitignore).
#
# It also fetches MoltenVK. Azahar links MoltenVK only into its own Qt/SDL
# builds -- its CMakeLists.txt guards that with
# `if (ENABLE_VULKAN AND NOT ENABLE_LIBRETRO)` -- because a libretro core expects
# the frontend to own the Vulkan instance, device and swapchain. So for this
# app, the Vulkan implementation is ours to provide. 1.3.0's ios-arm64 static
# slice is built for iOS 13.0, below this project's 14.0 floor.
#
# Bump the tag by changing AZAHAR_TAG below (and re-run). The resolved commit is
# written to vendor/azahar/COMMIT for the record.

set -euo pipefail

AZAHAR_TAG="${AZAHAR_TAG:-2127.0-rc3}"
AZAHAR_URL="https://github.com/azahar-emu/azahar.git"
MOLTENVK_VERSION="${MOLTENVK_VERSION:-1.3.0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/vendor/azahar"
MOLTENVK="$ROOT/vendor/moltenvk/libMoltenVK.a"

if [[ ! -f "$MOLTENVK" ]]; then
    mkdir -p "$ROOT/vendor/moltenvk"
    echo "Fetching MoltenVK $MOLTENVK_VERSION ..."
    archive="$(mktemp)"
    curl -fL --retry 3 -o "$archive" \
        "https://github.com/KhronosGroup/MoltenVK/releases/download/v${MOLTENVK_VERSION}/MoltenVK-all.tar"
    work="$(mktemp -d)"
    tar -xf "$archive" -C "$work" \
        MoltenVK/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a
    cp "$work/MoltenVK/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a" \
        "$MOLTENVK"
    rm -rf "$work" "$archive"
    echo "MoltenVK ios-arm64 slice: $MOLTENVK"
fi

if [[ -d "$DEST/.git" ]]; then
    current="$(git -C "$DEST" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "vendor/azahar already present at $current; leaving it alone."
    echo "Remove vendor/azahar to re-fetch."
    exit 0
fi

mkdir -p "$ROOT/vendor"
echo "Fetching Azahar $AZAHAR_TAG ..."
git clone --depth 1 --branch "$AZAHAR_TAG" --recurse-submodules "$AZAHAR_URL" "$DEST"

COMMIT="$(git -C "$DEST" rev-parse HEAD)"
echo "$AZAHAR_TAG $COMMIT" > "$DEST/COMMIT"
echo "Azahar $AZAHAR_TAG at $COMMIT"
