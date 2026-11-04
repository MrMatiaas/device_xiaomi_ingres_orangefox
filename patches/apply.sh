#!/bin/bash
# Apply ingres source patches to an OrangeFox fox_14.1 tree.
# Usage (from the source root, e.g. ~/fox_14.1):
#   bash device/xiaomi/ingres/patches/apply.sh
# Safe to re-run: already-applied patches are skipped.
set -e
PATCHES="$(cd "$(dirname "$0")" && pwd)"
TOP="${TOP:-$PWD}"

for dir in bootable/recovery external/se_omapi; do
    for p in "$PATCHES/$dir"/*.patch; do
        [ -e "$p" ] || continue
        name="$dir/$(basename "$p")"
        if git -C "$TOP/$dir" apply --check -R "$p" 2>/dev/null; then
            echo "already applied: $name"
        elif git -C "$TOP/$dir" apply "$p"; then
            echo "applied:         $name"
        else
            echo "FAILED:          $name" >&2
            exit 1
        fi
    done
done
