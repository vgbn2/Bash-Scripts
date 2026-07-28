#!/usr/bin/env bash
# Mirror this source folder to a home-level bash directory.
# Without --apply, this only previews changes.

set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MIRROR_DIR="${BASH_MIRROR_DIR:-$HOME/bash}"

if [ "${1:-}" != "--apply" ]; then
    echo "Preview only. Run with --apply to update the mirror."
    rsync -a --delete --dry-run --itemize-changes "$SOURCE_DIR/" "$MIRROR_DIR/"
    exit 0
fi

rsync -a --delete --itemize-changes "$SOURCE_DIR/" "$MIRROR_DIR/"
echo "Mirror updated: $MIRROR_DIR"
