#!/bin/bash

# ==============================================================================
# CONFIGURATION - HARD DRIVE PATHS
# ==============================================================================
HDD_BASE="${HDD_BASE:-}"
if [ -z "$HDD_BASE" ]; then
    echo "Set HDD_BASE to the mounted archive disk before running this script." >&2
    exit 2
fi
SCREENSHOTS_TARGET="$HDD_BASE/ScreenshotsBackup"
DOWNLOADS_TARGET="$HDD_BASE/DownloadsArchive"

# Ensure HDD archive folders exist
mkdir -p "$SCREENSHOTS_TARGET"
mkdir -p "$DOWNLOADS_TARGET"

# ==============================================================================
# PART 1: DATA MIGRATION (NVMe TO HDD)
# ==============================================================================

# Move screenshots older than 7 days
find "$HOME/Pictures/Screenshots" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -mtime +7 -exec mv {} "$SCREENSHOTS_TARGET/" \;

# Move download files untouched for more than 14 days
find "$HOME/Downloads" -type f -mtime +14 -exec mv {} "$DOWNLOADS_TARGET/" \;

# ==============================================================================
# PART 2: SYSTEM MAINTENANCE & CACHE CLEANING
# ==============================================================================

# 1. Clean out dead Flatpak components and unused runtimes
flatpak uninstall --unused -y

# 2. Vacuum systemd journal logs, keeping only the last 3 days of data
sudo journalctl --vacuum-time=3d

# 3. Clean out old downloaded APT package installers
sudo apt-get autoclean -y

exit 0
