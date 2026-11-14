#!/usr/bin/env bash
# Fetch the pinned Azahar release into vendor/azahar.
#
# Azahar is a dependency, never a fork: this script only checks out a release
# tag and its submodules. Nothing in vendor/ is edited by this project, and
# nothing in vendor/ is committed (see .gitignore).
#
# Bump the tag by changing AZAHAR_TAG below (and re-run). The resolved commit
# is written to vendor/azahar/COMMIT for the record.

set -euo pipefail

AZAHAR_TAG="${AZAHAR_TAG:-2127.0-rc3}"
AZAHAR_URL="https://github.com/azahar-emu/azahar.git"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/vendor/azahar"

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
