#!/usr/bin/env bash
# Cron-friendly NVIDIA and Vulkan health check with truthful exit status.

set -u

export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

LOG_FILE="${GPU_HEALTH_LOG:-$HOME/.local/state/system-toolkit/gpu-health.log}"
status=0

usage() {
    cat <<'HELP'
Usage: check_gpu.sh

Checks the NVIDIA module, nvidia-smi telemetry, and Vulkan renderer. Results
are appended to GPU_HEALTH_LOG (default:
~/.local/state/system-toolkit/gpu-health.log).

Exit status:
  0  healthy
  1  critical GPU or software-rendering failure
  2  incomplete check because an optional diagnostic is unavailable
HELP
}

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

notify() {
    local urgency=$1 title=$2 message=$3

    command -v notify-send >/dev/null 2>&1 || return
    notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
}

mark_warning() {
    [ "$status" -eq 0 ] && status=2
}

mark_critical() {
    status=1
}

check_module() {
    if ! command -v lsmod >/dev/null 2>&1; then
        log "WARNING: lsmod is unavailable; kernel-module check skipped."
        mark_warning
    elif ! lsmod | grep -q '^nvidia '; then
        log "CRITICAL: NVIDIA kernel module is not loaded."
        notify critical "GPU warning" "NVIDIA kernel module is not loaded."
        mark_critical
    else
        log "NVIDIA kernel module: loaded"
    fi

    if command -v dpkg-query >/dev/null 2>&1 &&
        dpkg-query -W -f='${binary:Package}\n' 'nvidia-driver-*-open' \
            2>/dev/null | grep -q '^nvidia-driver-.*-open'; then
        log "NVIDIA kernel-module flavor: open"
    fi
}

check_nvidia_telemetry() {
    local telemetry

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        log "CRITICAL: nvidia-smi is unavailable."
        notify critical "GPU warning" "nvidia-smi is unavailable."
        mark_critical
        return
    fi

    if telemetry=$(nvidia-smi \
        --query-gpu=driver_version,name,temperature.gpu,fan.speed \
        --format=csv,noheader 2>&1); then
        log "NVIDIA telemetry: $telemetry"
    else
        log "CRITICAL: nvidia-smi failed: $telemetry"
        notify critical "GPU warning" "NVIDIA telemetry query failed."
        mark_critical
    fi
}

check_vulkan() {
    local summary renderer

    if ! command -v vulkaninfo >/dev/null 2>&1; then
        log "WARNING: vulkaninfo is unavailable; Vulkan check skipped."
        mark_warning
        return
    fi

    if ! summary=$(vulkaninfo --summary 2>&1); then
        log "WARNING: vulkaninfo failed: $summary"
        mark_warning
        return
    fi
    renderer=$(printf '%s\n' "$summary" |
        awk -F '=' '/deviceName/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}')
    if printf '%s\n' "$summary" | grep -qi 'llvmpipe'; then
        log "CRITICAL: Vulkan reports llvmpipe CPU software rendering."
        notify critical "GPU critical" "Vulkan reports llvmpipe software rendering."
        mark_critical
    elif [ -z "$renderer" ]; then
        log "WARNING: Vulkan renderer was not present in the summary."
        mark_warning
    else
        log "Vulkan renderer: $renderer"
    fi
}

case "${1:-}" in
    help|-h|--help) usage; exit 0 ;;
    "") ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
esac

mkdir -p -- "$(dirname -- "$LOG_FILE")"
log "=== GPU health check: $(date --iso-8601=seconds) ==="
check_module
check_nvidia_telemetry
check_vulkan

case "$status" in
    0) log "Status: OK" ;;
    1) log "Status: CRITICAL" ;;
    2) log "Status: INCOMPLETE" ;;
esac
exit "$status"
