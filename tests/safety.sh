#!/usr/bin/env bash
# Behavioral safety checks using only temporary files and mocked host commands.

set -euo pipefail

TOOL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

expect_status() {
    local expected=$1
    shift
    local actual=0

    "$@" >/dev/null 2>&1 || actual=$?
    [ "$actual" -eq "$expected" ] ||
        fail "expected status $expected, got $actual: $*"
}

test_archive_guards() {
    local source_screens="$TEMP_DIR/source/screens"
    local source_downloads="$TEMP_DIR/source/downloads"
    local archive_base="$TEMP_DIR/archive"
    local absent_archive="$TEMP_DIR/absent-archive"
    local absent_downloads="$TEMP_DIR/absent-downloads"
    local overlap_empty="$TEMP_DIR/overlap-empty"
    local same_base="$TEMP_DIR/overlap-same"
    local target_inside_root="$TEMP_DIR/overlap-target-inside"
    local source_inside_root="$TEMP_DIR/overlap-source-inside"

    mkdir -p "$source_screens/nested" "$source_downloads/docs" "$archive_base"
    printf 'image\n' >"$source_screens/nested/old.png"
    printf 'download\n' >"$source_downloads/docs/old.txt"
    touch -d '30 days ago' \
        "$source_screens/nested/old.png" \
        "$source_downloads/docs/old.txt"

    HDD_BASE="$archive_base" \
        SCREENSHOTS_SOURCE="$source_screens" \
        DOWNLOADS_SOURCE="$source_downloads" \
        SCREENSHOTS_DAYS=7 DOWNLOADS_DAYS=14 \
        ARCHIVE_ALLOW_ROOT_FS=1 \
        "$TOOL_ROOT/maintenance/archive_screenshots.sh" preview \
        >"$TEMP_DIR/archive-preview.log"

    grep -Fq 'Candidates: 1' "$TEMP_DIR/archive-preview.log" ||
        fail "archive preview did not report candidates"
    test -f "$source_screens/nested/old.png" ||
        fail "preview moved a screenshot"

    expect_status 2 env HDD_BASE="$archive_base" \
        "$TOOL_ROOT/maintenance/archive_screenshots.sh" archive
    test -f "$source_screens/nested/old.png" ||
        fail "unguarded archive moved a screenshot"

    HDD_BASE="$archive_base" \
        SCREENSHOTS_SOURCE="$source_screens" \
        DOWNLOADS_SOURCE="$source_downloads" \
        SCREENSHOTS_DAYS=7 DOWNLOADS_DAYS=14 \
        ARCHIVE_ALLOW_ROOT_FS=1 \
        "$TOOL_ROOT/maintenance/archive_screenshots.sh" archive --yes \
        >"$TEMP_DIR/archive-apply.log"

    test -f "$archive_base/ScreenshotsBackup/nested/old.png" ||
        fail "screenshot relative path was not preserved"
    test -f "$archive_base/DownloadsArchive/docs/old.txt" ||
        fail "download relative path was not preserved"
    test ! -e "$source_screens/nested/old.png" ||
        fail "archived screenshot remained at source"

    printf 'replacement\n' >"$source_screens/nested/old.png"
    touch -d '30 days ago' "$source_screens/nested/old.png"
    HDD_BASE="$archive_base" \
        SCREENSHOTS_SOURCE="$source_screens" \
        DOWNLOADS_SOURCE="$source_downloads" \
        SCREENSHOTS_DAYS=7 DOWNLOADS_DAYS=14 \
        ARCHIVE_ALLOW_ROOT_FS=1 \
        "$TOOL_ROOT/maintenance/archive_screenshots.sh" archive --yes \
        >"$TEMP_DIR/archive-collision.log" 2>&1
    test -f "$source_screens/nested/old.png" ||
        fail "archive overwrote an existing destination"
    grep -Fq 'image' "$archive_base/ScreenshotsBackup/nested/old.png" ||
        fail "existing archive content changed after collision"

    mkdir -p "$absent_archive" "$absent_downloads/docs"
    printf 'download\n' >"$absent_downloads/docs/old.txt"
    touch -d '30 days ago' "$absent_downloads/docs/old.txt"
    HDD_BASE="$absent_archive" \
        SCREENSHOTS_SOURCE="$TEMP_DIR/absent-screenshots" \
        DOWNLOADS_SOURCE="$absent_downloads" \
        SCREENSHOTS_DAYS=7 DOWNLOADS_DAYS=14 \
        ARCHIVE_ALLOW_ROOT_FS=1 \
        "$TOOL_ROOT/maintenance/archive_screenshots.sh" archive --yes \
        >"$TEMP_DIR/archive-absent-source.log"
    test -f "$absent_archive/DownloadsArchive/docs/old.txt" ||
        fail "absent screenshot source prevented download archival"
    grep -Fq 'Skipped screenshots archive: source directory is absent:' \
        "$TEMP_DIR/archive-absent-source.log" ||
        fail "absent archive source was not reported as skipped"

    mkdir -p "$overlap_empty" "$same_base/DownloadsArchive"
    printf 'same\n' >"$same_base/DownloadsArchive/old.txt"
    touch -d '30 days ago' "$same_base/DownloadsArchive/old.txt"
    expect_status 1 env HDD_BASE="$same_base" \
        SCREENSHOTS_SOURCE="$overlap_empty" \
        DOWNLOADS_SOURCE="$same_base/DownloadsArchive" \
        ARCHIVE_ALLOW_ROOT_FS=1 \
        "$TOOL_ROOT/maintenance/archive_screenshots.sh" archive --yes
    test -f "$same_base/DownloadsArchive/old.txt" ||
        fail "equal archive source and target moved a file"

    mkdir -p "$target_inside_root/source/archive" \
        "$target_inside_root/empty-screens"
    printf 'nested-target\n' >"$target_inside_root/source/old.txt"
    touch -d '30 days ago' "$target_inside_root/source/old.txt"
    expect_status 1 env HDD_BASE="$target_inside_root/source/archive" \
        SCREENSHOTS_SOURCE="$target_inside_root/empty-screens" \
        DOWNLOADS_SOURCE="$target_inside_root/source" \
        ARCHIVE_ALLOW_ROOT_FS=1 \
        "$TOOL_ROOT/maintenance/archive_screenshots.sh" archive --yes
    test -f "$target_inside_root/source/old.txt" ||
        fail "target-inside-source archive moved a file"

    mkdir -p "$source_inside_root/archive/DownloadsArchive/incoming" \
        "$source_inside_root/empty-screens"
    printf 'nested-source\n' \
        >"$source_inside_root/archive/DownloadsArchive/incoming/old.txt"
    touch -d '30 days ago' \
        "$source_inside_root/archive/DownloadsArchive/incoming/old.txt"
    expect_status 1 env HDD_BASE="$source_inside_root/archive" \
        SCREENSHOTS_SOURCE="$source_inside_root/empty-screens" \
        DOWNLOADS_SOURCE="$source_inside_root/archive/DownloadsArchive/incoming" \
        ARCHIVE_ALLOW_ROOT_FS=1 \
        "$TOOL_ROOT/maintenance/archive_screenshots.sh" archive --yes
    test -f "$source_inside_root/archive/DownloadsArchive/incoming/old.txt" ||
        fail "source-inside-target archive moved a file"
}

make_gpu_mocks() {
    local fake_bin="$TEMP_DIR/gpu-bin"

    mkdir -p "$fake_bin"
    cat >"$fake_bin/lsmod" <<'SCRIPT'
#!/usr/bin/env bash
echo 'nvidia 123 0'
SCRIPT
    cat >"$fake_bin/dpkg-query" <<'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
    cat >"$fake_bin/nvidia-smi" <<'SCRIPT'
#!/usr/bin/env bash
if [ "${FAKE_NVIDIA_FAIL:-0}" = 1 ]; then
    echo 'mock nvidia failure' >&2
    exit 1
fi
echo '555.1, Mock GPU, 55, 30 %'
SCRIPT
    cat >"$fake_bin/vulkaninfo" <<'SCRIPT'
#!/usr/bin/env bash
if [ "${FAKE_VULKAN_FAIL:-0}" = 1 ]; then
    echo 'mock Vulkan failure' >&2
    exit 1
fi
echo "deviceName = ${FAKE_RENDERER:-Mock GPU}"
SCRIPT
    cat >"$fake_bin/notify-send" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    chmod +x "$fake_bin"/*
    printf '%s\n' "$fake_bin"
}

test_gpu_truthful_status() {
    local fake_bin
    fake_bin=$(make_gpu_mocks)

    PATH="$fake_bin:$PATH" \
        GPU_HEALTH_LOG="$TEMP_DIR/gpu-ok.log" \
        "$TOOL_ROOT/hardware/check_gpu.sh" >/dev/null
    grep -Fq 'Status: OK' "$TEMP_DIR/gpu-ok.log" ||
        fail "healthy GPU mock was not reported OK"

    expect_status 1 env PATH="$fake_bin:$PATH" \
        FAKE_RENDERER=llvmpipe \
        GPU_HEALTH_LOG="$TEMP_DIR/gpu-llvmpipe.log" \
        "$TOOL_ROOT/hardware/check_gpu.sh"
    grep -Fq 'Status: CRITICAL' "$TEMP_DIR/gpu-llvmpipe.log" ||
        fail "llvmpipe was not reported critical"

    expect_status 1 env PATH="$fake_bin:$PATH" \
        FAKE_NVIDIA_FAIL=1 \
        GPU_HEALTH_LOG="$TEMP_DIR/gpu-nvidia-fail.log" \
        "$TOOL_ROOT/hardware/check_gpu.sh"
    grep -Fq 'nvidia-smi failed' "$TEMP_DIR/gpu-nvidia-fail.log" ||
        fail "nvidia-smi failure was hidden"

    expect_status 2 env PATH="$fake_bin:$PATH" \
        FAKE_VULKAN_FAIL=1 \
        GPU_HEALTH_LOG="$TEMP_DIR/gpu-vulkan-fail.log" \
        "$TOOL_ROOT/hardware/check_gpu.sh"
    grep -Fq 'Status: INCOMPLETE' "$TEMP_DIR/gpu-vulkan-fail.log" ||
        fail "missing Vulkan telemetry was reported as healthy"
}

make_thermal_mocks() {
    local fake_bin="$TEMP_DIR/thermal-bin"

    mkdir -p "$fake_bin"
    cat >"$fake_bin/nvidia-smi" <<'SCRIPT'
#!/usr/bin/env bash
if [ "${FAKE_NO_TEMPS:-0}" = 1 ]; then
    exit 1
fi
echo 70
SCRIPT
    cat >"$fake_bin/sensors" <<'SCRIPT'
#!/usr/bin/env bash
if [ "${FAKE_NO_TEMPS:-0}" = 1 ]; then
    exit 1
fi
echo 'Package id 0:  +85.0°C'
SCRIPT
    cat >"$fake_bin/notify-send" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    chmod +x "$fake_bin"/*
    printf '%s\n' "$fake_bin"
}

test_thermal_selection() {
    local fake_bin
    local status=0
    fake_bin=$(make_thermal_mocks)

    PATH="$fake_bin:$PATH" THERMAL_ALERT_COOLDOWN=300 \
        "$TOOL_ROOT/hardware/thermal_alert.sh" \
        --once --threshold 80 >"$TEMP_DIR/thermal-hot.log" 2>&1 ||
        status=$?
    [ "$status" -eq 1 ] || fail "hot thermal snapshot did not return status 1"
    grep -Fq 'temperature=85C source=cpu' "$TEMP_DIR/thermal-hot.log" ||
        fail "thermal watcher did not choose the hotter CPU reading"

    expect_status 2 env PATH="$fake_bin:$PATH" FAKE_NO_TEMPS=1 \
        "$TOOL_ROOT/hardware/thermal_alert.sh" --once --threshold 80
    expect_status 2 "$TOOL_ROOT/hardware/thermal_alert.sh" \
        --once --threshold invalid
}

test_system_action_guards() {
    expect_status 2 "$TOOL_ROOT/system/system" archive archive
    expect_status 2 "$TOOL_ROOT/system/system" archive cleanup
    expect_status 2 "$TOOL_ROOT/system/system" setup all
    expect_status 2 "$TOOL_ROOT/system/system" repair thermal
    expect_status 2 "$TOOL_ROOT/system/system" repair gpu
    expect_status 2 "$TOOL_ROOT/system/system" repair desktop
    expect_status 2 "$TOOL_ROOT/maintenance/system-repair" gpu
}

test_gaming_repair_propagation() {
    local fake_bin="$TEMP_DIR/repair-bin"

    mkdir -p "$fake_bin"
    cat >"$fake_bin/system-repair" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$FAKE_REPAIR_ARGS"
SCRIPT
    chmod +x "$fake_bin/system-repair"

    PATH="$fake_bin:$PATH" FAKE_REPAIR_ARGS="$TEMP_DIR/repair-args.log" \
        "$TOOL_ROOT/gaming/gaming" repair-flatpak-gpu --yes
    grep -Fxq 'gpu --yes' "$TEMP_DIR/repair-args.log" ||
        fail "gaming repair did not propagate canonical confirmation"
}

test_mirror_guards() {
    local mirror="$TEMP_DIR/mirror"
    local fake_home="$TEMP_DIR/fake-home"

    mkdir -p "$fake_home"
    expect_status 2 env BASH_MIRROR_DIR="$mirror" \
        "$TOOL_ROOT/tools/sync-to-home.sh" --apply
    test ! -e "$mirror" || fail "unguarded mirror apply created a destination"

    expect_status 1 env HOME="$fake_home" BASH_MIRROR_DIR="$fake_home" \
        "$TOOL_ROOT/tools/sync-to-home.sh"

    BASH_MIRROR_DIR="$mirror" \
        "$TOOL_ROOT/tools/sync-to-home.sh" --apply --yes \
        >"$TEMP_DIR/mirror-apply.log"
    test -x "$mirror/system/system" ||
        fail "safe temporary mirror did not copy the system entry point"

    printf 'stale\n' >"$mirror/stale-local-file"
    mkdir -p "$mirror/.git" "$mirror/.agents" "$mirror/.codex"
    printf 'protected\n' >"$mirror/.git/sentinel"
    printf 'protected\n' >"$mirror/.agents/sentinel"
    printf 'protected\n' >"$mirror/.codex/sentinel"
    BASH_MIRROR_DIR="$mirror" \
        "$TOOL_ROOT/tools/sync-to-home.sh" --apply --yes \
        >/dev/null
    test ! -e "$mirror/stale-local-file" ||
        fail "mirror apply did not remove stale destination content"
    test -f "$mirror/.git/sentinel" ||
        fail "mirror apply changed protected Git metadata"
    test -f "$mirror/.agents/sentinel" ||
        fail "mirror apply changed protected agent metadata"
    test -f "$mirror/.codex/sentinel" ||
        fail "mirror apply changed protected Codex metadata"
}

test_archive_guards
test_gpu_truthful_status
test_thermal_selection
test_system_action_guards
test_gaming_repair_propagation
test_mirror_guards
echo "Safety checks passed."
