#!/usr/bin/env bash
# Preview or explicitly archive old screenshots/downloads and run cleanup.

set -euo pipefail

HDD_BASE="${HDD_BASE:-}"
SCREENSHOTS_SOURCE="${SCREENSHOTS_SOURCE:-$HOME/Pictures/Screenshots}"
DOWNLOADS_SOURCE="${DOWNLOADS_SOURCE:-$HOME/Downloads}"
SCREENSHOTS_DAYS="${SCREENSHOTS_DAYS:-7}"
DOWNLOADS_DAYS="${DOWNLOADS_DAYS:-14}"

usage() {
    cat <<'HELP'
Usage: archive_screenshots.sh <command> [--yes]

Commands:
  preview          Show files eligible for archival without changing anything.
  archive --yes    Move eligible files to the configured archive disk.
  cleanup --yes    Remove unused Flatpak runtimes, old journal data, and APT cache.
  all --yes        Archive eligible files, then run cleanup.

Environment:
  HDD_BASE             Required mounted archive-disk path for preview/archive.
  SCREENSHOTS_SOURCE   Default: ~/Pictures/Screenshots
  DOWNLOADS_SOURCE     Default: ~/Downloads
  SCREENSHOTS_DAYS     Default: 7
  DOWNLOADS_DAYS       Default: 14

Archived files retain their relative directory layout. Existing destination
files are never overwritten. The archive disk must be on a filesystem other
than the root filesystem unless ARCHIVE_ALLOW_ROOT_FS=1 is explicitly set.
HELP
}

require_confirmation() {
    if [ "${1:-}" != "--yes" ]; then
        echo "This action changes files or system caches." >&2
        echo "Re-run the selected command with --yes." >&2
        return 2
    fi
}

valid_days() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

paths_overlap() {
    local first=$1 second=$2

    [ "$first" = "$second" ] ||
        [[ "$first/" == "$second/"* ]] ||
        [[ "$second/" == "$first/"* ]]
}

validate_source_target_pair() {
    local source=$1 target=$2 source_label=$3 target_label=$4
    local source_real target_real

    [ -d "$source" ] || return 0
    source_real=$(readlink -f -- "$source") || {
        echo "Could not resolve $source_label source: $source" >&2
        return 1
    }
    target_real=$(readlink -f -- "$target") || {
        echo "Could not resolve $target_label target: $target" >&2
        return 1
    }

    if paths_overlap "$source_real" "$target_real"; then
        printf 'Refusing overlapping archive paths: %s source and %s target.\n' \
            "$source_label" "$target_label" >&2
        printf 'Source: %s\nTarget: %s\n' "$source_real" "$target_real" >&2
        return 1
    fi
}

validate_archive_layout() {
    local screenshots_target=$1 downloads_target=$2

    validate_source_target_pair "$SCREENSHOTS_SOURCE" "$screenshots_target" \
        screenshots screenshots
    validate_source_target_pair "$SCREENSHOTS_SOURCE" "$downloads_target" \
        screenshots downloads
    validate_source_target_pair "$DOWNLOADS_SOURCE" "$screenshots_target" \
        downloads screenshots
    validate_source_target_pair "$DOWNLOADS_SOURCE" "$downloads_target" \
        downloads downloads
}

validate_archive_base() {
    local mount_target

    if [ -z "$HDD_BASE" ]; then
        echo "Set HDD_BASE to the mounted archive disk." >&2
        return 2
    fi
    if [ ! -d "$HDD_BASE" ]; then
        echo "Archive base does not exist: $HDD_BASE" >&2
        return 1
    fi
    if ! command -v findmnt >/dev/null 2>&1; then
        echo "findmnt is required to validate the archive filesystem." >&2
        return 127
    fi

    mount_target=$(findmnt -n -o TARGET --target "$HDD_BASE" 2>/dev/null || true)
    if [ -z "$mount_target" ]; then
        echo "Could not identify the filesystem for: $HDD_BASE" >&2
        return 1
    fi
    if [ "$mount_target" = "/" ] && [ "${ARCHIVE_ALLOW_ROOT_FS:-0}" != "1" ]; then
        echo "Refusing to archive onto the root filesystem: $HDD_BASE" >&2
        echo "Mount the archive disk, or explicitly set ARCHIVE_ALLOW_ROOT_FS=1." >&2
        return 1
    fi

    printf 'Archive filesystem: %s\n' "$mount_target"
}

print_candidate() {
    local source=$1 target=$2 file=$3
    local relative=${file#"$source"/}

    printf '  %s -> %s/%s\n' "$file" "$target" "$relative"
}

scan_screenshots() {
    local target=$1
    local file
    local count=0

    printf '\nScreenshots older than %s days\n' "$SCREENSHOTS_DAYS"
    if [ ! -d "$SCREENSHOTS_SOURCE" ]; then
        printf '  Source directory is absent: %s\n' "$SCREENSHOTS_SOURCE"
        return
    fi

    while IFS= read -r -d '' file; do
        print_candidate "$SCREENSHOTS_SOURCE" "$target" "$file"
        count=$((count + 1))
    done < <(
        find "$SCREENSHOTS_SOURCE" -xdev -type f \
            \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
            -mtime "+$SCREENSHOTS_DAYS" -print0
    )
    printf '  Candidates: %s\n' "$count"
}

scan_downloads() {
    local target=$1
    local file
    local count=0

    printf '\nDownloads older than %s days\n' "$DOWNLOADS_DAYS"
    if [ ! -d "$DOWNLOADS_SOURCE" ]; then
        printf '  Source directory is absent: %s\n' "$DOWNLOADS_SOURCE"
        return
    fi

    while IFS= read -r -d '' file; do
        print_candidate "$DOWNLOADS_SOURCE" "$target" "$file"
        count=$((count + 1))
    done < <(
        find "$DOWNLOADS_SOURCE" -xdev -type f -mtime "+$DOWNLOADS_DAYS" -print0
    )
    printf '  Candidates: %s\n' "$count"
}

preview_archive() {
    local screenshots_target downloads_target

    valid_days "$SCREENSHOTS_DAYS" && valid_days "$DOWNLOADS_DAYS" || {
        echo "Archive age settings must be non-negative whole days." >&2
        return 2
    }
    validate_archive_base
    screenshots_target="$HDD_BASE/ScreenshotsBackup"
    downloads_target="$HDD_BASE/DownloadsArchive"
    validate_archive_layout "$screenshots_target" "$downloads_target"
    scan_screenshots "$screenshots_target"
    scan_downloads "$downloads_target"
}

move_candidates() {
    local source=$1 target=$2 kind=$3 days=$4
    local file relative destination
    local moved=0
    local skipped=0
    local -a find_args

    if [ ! -d "$source" ]; then
        printf 'Skipped %s archive: source directory is absent: %s\n' \
            "$kind" "$source"
        return 0
    fi
    find_args=("$source" -xdev -type f)
    if [ "$kind" = "screenshots" ]; then
        find_args+=(\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \))
    fi
    find_args+=(-mtime "+$days" -print0)

    while IFS= read -r -d '' file; do
        relative=${file#"$source"/}
        destination="$target/$relative"
        if [ -e "$destination" ] || [ -L "$destination" ]; then
            printf 'Skipped existing destination: %s\n' "$destination" >&2
            skipped=$((skipped + 1))
            continue
        fi
        mkdir -p -- "$(dirname -- "$destination")"
        mv -- "$file" "$destination"
        printf 'Archived: %s -> %s\n' "$file" "$destination"
        moved=$((moved + 1))
    done < <(find "${find_args[@]}")

    printf '%s archive result: moved=%s skipped=%s\n' "$kind" "$moved" "$skipped"
}

archive_files() {
    local screenshots_target downloads_target

    preview_archive
    screenshots_target="$HDD_BASE/ScreenshotsBackup"
    downloads_target="$HDD_BASE/DownloadsArchive"
    mkdir -p -- "$screenshots_target" "$downloads_target"

    move_candidates "$SCREENSHOTS_SOURCE" "$screenshots_target" \
        screenshots "$SCREENSHOTS_DAYS"
    move_candidates "$DOWNLOADS_SOURCE" "$downloads_target" \
        downloads "$DOWNLOADS_DAYS"
}

cleanup_system() {
    if command -v flatpak >/dev/null 2>&1; then
        flatpak uninstall --unused -y
    else
        echo "Skipping Flatpak cleanup: flatpak is unavailable."
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        echo "sudo is required for journal and APT cleanup." >&2
        return 127
    fi
    sudo journalctl --vacuum-time=3d
    sudo apt-get autoclean -y
}

command_name=${1:-preview}
confirmation=${2:-}

case "$command_name" in
    preview) preview_archive ;;
    archive)
        require_confirmation "$confirmation"
        archive_files
        ;;
    cleanup)
        require_confirmation "$confirmation"
        cleanup_system
        ;;
    all)
        require_confirmation "$confirmation"
        archive_files
        cleanup_system
        ;;
    help|-h|--help) usage ;;
    *)
        echo "Unknown archive command: $command_name" >&2
        usage >&2
        exit 2
        ;;
esac
