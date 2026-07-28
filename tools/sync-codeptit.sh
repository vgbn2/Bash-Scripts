#!/usr/bin/env bash
# One-way host -> child synchronization for the complete CodePTIT workspace.

set -euo pipefail

SOURCE_DIR="${CODEPTIT_SOURCE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/}"
TARGET_HOST="${CODEPTIT_SYNC_HOST:-}"
TARGET_DIR="${CODEPTIT_SYNC_DIR:-}"
BWLIMIT="${CODEPTIT_SYNC_BWLIMIT:-5000}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/codeptit-sync"
LOG_FILE="$STATE_DIR/latest.log"
LOCK_FILE="$STATE_DIR/sync.lock"
DRY_RUN=0

usage() {
    cat <<'HELP'
Usage: sync-codeptit.sh [--dry-run] [--help]

Sync the complete CodePTIT folder from this host to the child machine.

Environment overrides:
  CODEPTIT_SYNC_HOST=user@host       Required remote SSH target
  CODEPTIT_SYNC_DIR=/remote/path     Required remote destination
  CODEPTIT_SYNC_BWLIMIT=5000         KiB/s; default is about 5 MB/s

The script does not delete files on the child. SSH key authentication is
required for unattended scheduled runs.
HELP
}

for argument in "$@"; do
    case "$argument" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $argument" >&2; usage >&2; exit 2 ;;
    esac
done

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Source directory is missing: $SOURCE_DIR" >&2
    exit 1
fi
if [ -z "$TARGET_HOST" ] || [ -z "$TARGET_DIR" ]; then
    echo "Set CODEPTIT_SYNC_HOST and CODEPTIT_SYNC_DIR before syncing." >&2
    usage >&2
    exit 2
fi
if ! [[ "$BWLIMIT" =~ ^[1-9][0-9]*$ ]]; then
    echo "CODEPTIT_SYNC_BWLIMIT must be a positive KiB/s value." >&2
    exit 2
fi
if ! command -v rsync >/dev/null 2>&1; then
    echo "rsync is not installed." >&2
    exit 127
fi

mkdir -p "$STATE_DIR"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "A CodePTIT sync is already running." >&2
    exit 75
fi

rsync_args=(
    -avh
    --itemize-changes
    --partial
    --bwlimit="$BWLIMIT"
    --timeout=60
    -e "ssh -o BatchMode=yes -o ConnectTimeout=15"
)
if [ "$DRY_RUN" -eq 1 ]; then
    rsync_args+=(--dry-run)
fi

{
    printf '\n=== CodePTIT sync: %s ===\n' "$(date --iso-8601=seconds)"
    printf 'Source: %s\nTarget: %s:%s\nBandwidth: %s KiB/s\n' \
        "$SOURCE_DIR" "$TARGET_HOST" "$TARGET_DIR" "$BWLIMIT"
    rsync "${rsync_args[@]}" "$SOURCE_DIR" "$TARGET_HOST:$TARGET_DIR"
    echo "Sync completed."
} 2>&1 | tee -a "$LOG_FILE"
