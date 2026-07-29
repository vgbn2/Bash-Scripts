#!/usr/bin/env bash
# Mirror this canonical source folder to a dedicated home-level directory.

set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MIRROR_DIR="${BASH_MIRROR_DIR:-$HOME/bash}"
apply=0
confirmed=0
RSYNC_FILTERS=(
    --exclude=/.git/
    --exclude=/.agents/
    --exclude=/.codex/
)

usage() {
    cat <<'HELP'
Usage: sync-to-home.sh [--apply --yes]

Without arguments, preview the canonical-source mirror. Applying uses
rsync --delete and therefore requires both --apply and --yes.

Environment:
  BASH_MIRROR_DIR    Mirror destination (default: ~/bash)

The destination must be a dedicated directory. The script rejects /, the home
directory, the source directory, and any source/destination ancestor overlap.
Repository and agent metadata (.git, .agents, and .codex) are excluded and
protected from deletion.
HELP
}

canonical_destination() {
    local destination=$1
    local parent name

    if [ -e "$destination" ] || [ -L "$destination" ]; then
        readlink -f -- "$destination"
        return
    fi

    parent=$(dirname -- "$destination")
    name=$(basename -- "$destination")
    parent=$(readlink -f -- "$parent") || {
        echo "Mirror parent does not exist: $parent" >&2
        return 1
    }
    printf '%s/%s\n' "${parent%/}" "$name"
}

validate_destination() {
    local source_real mirror_real home_real

    source_real=$(readlink -f -- "$SOURCE_DIR")
    mirror_real=$(canonical_destination "$MIRROR_DIR")
    home_real=$(readlink -f -- "$HOME")

    case "$mirror_real" in
        /|"$home_real")
            echo "Refusing broad mirror destination: $mirror_real" >&2
            return 1
            ;;
    esac
    if [ "$mirror_real" = "$source_real" ] ||
        [[ "$mirror_real/" == "$source_real/"* ]] ||
        [[ "$source_real/" == "$mirror_real/"* ]]; then
        echo "Source and mirror directories must not overlap." >&2
        echo "Source: $source_real" >&2
        echo "Mirror: $mirror_real" >&2
        return 1
    fi

    MIRROR_DIR=$mirror_real
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --apply) apply=1 ;;
        --yes) confirmed=1 ;;
        help|-h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

validate_destination

if [ "$apply" -eq 0 ]; then
    echo "Preview only. Apply with: tools/sync-to-home.sh --apply --yes"
    rsync -a --delete --dry-run --itemize-changes \
        "${RSYNC_FILTERS[@]}" "$SOURCE_DIR/" "$MIRROR_DIR/"
    exit 0
fi
if [ "$confirmed" -ne 1 ]; then
    echo "Mirror apply can delete stale files from: $MIRROR_DIR" >&2
    echo "Re-run with both --apply and --yes." >&2
    exit 2
fi

mkdir -p -- "$MIRROR_DIR"
rsync -a --delete --itemize-changes \
    "${RSYNC_FILTERS[@]}" "$SOURCE_DIR/" "$MIRROR_DIR/"
echo "Mirror updated: $MIRROR_DIR"
