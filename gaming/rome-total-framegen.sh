#!/usr/bin/env bash
# rome-total-framegen.sh — Frame Generation & Hardware Offload Launcher for Total War: ROME REMASTERED
# Orchestrates GPU offload, opt-in CPU pinning, and Lossless Scaling companion.

set -euo pipefail

STEAM_ROOT="$HOME/.local/share/Steam"
ROME_APPID="885970"
LS_APPID="993090"
LS_DIR="$STEAM_ROOT/steamapps/common/Lossless Scaling"
PROTON_EXP="$STEAM_ROOT/steamapps/common/Proton - Experimental"

show_help() {
    cat <<'HELP'
Usage: rome-total-framegen.sh [options] [target_fps]

Total War: ROME REMASTERED — Frame Generation & Hardware Offload Launcher

Options:
  --ls                 Enable Lossless Scaling companion (default: disabled)
  --fps <target_fps>   Target frame rate (default: 100)
  --pin <cores>        Opt-in CPU affinity/topology pinning (e.g. 0-7; default: native)
  --freq <kHz>         Opt-in CPU max frequency boost (default: unchanged)
  --dry-run            Validate settings and print execution plan without running
  -h, --help           Show this help message and exit
HELP
}

TARGET_FPS=100
USE_LS=0
CPU_PIN=""
BOOST_FREQ=""
DRY_RUN=0

# Step 0: Validate CLI arguments before any system or hardware modification
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help|help)
            show_help
            exit 0
            ;;
        --ls)
            USE_LS=1
            shift
            ;;
        --fps)
            [ $# -ge 2 ] || { echo "rome-total-framegen: --fps requires a numeric argument" >&2; exit 2; }
            TARGET_FPS="$2"
            shift 2
            ;;
        --pin)
            [ $# -ge 2 ] || { echo "rome-total-framegen: --pin requires core specification (e.g. 0-7)" >&2; exit 2; }
            CPU_PIN="$2"
            shift 2
            ;;
        --freq)
            [ $# -ge 2 ] || { echo "rome-total-framegen: --freq requires frequency in kHz" >&2; exit 2; }
            BOOST_FREQ="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        [0-9]*)
            TARGET_FPS="$1"
            shift
            ;;
        *)
            echo "rome-total-framegen: unknown argument '$1'" >&2
            show_help >&2
            exit 2
            ;;
    esac
done

if ! [[ "$TARGET_FPS" =~ ^[0-9]+$ ]]; then
    echo "rome-total-framegen: target FPS must be a positive integer" >&2
    exit 2
fi

if [ -n "$CPU_PIN" ] && ! [[ "$CPU_PIN" =~ ^[0-9,-]+$ ]]; then
    echo "rome-total-framegen: invalid CPU pin syntax '$CPU_PIN'" >&2
    exit 2
fi

if [ -n "$BOOST_FREQ" ] && ! [[ "$BOOST_FREQ" =~ ^[0-9]+$ ]]; then
    echo "rome-total-framegen: frequency must be an integer in kHz" >&2
    exit 2
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "rome-total-framegen: dry run execution plan"
    echo "  Target FPS:    $TARGET_FPS"
    echo "  Lossless FG:   $([ "$USE_LS" -eq 1 ] && echo "enabled" || echo "disabled")"
    echo "  CPU Pinning:   ${CPU_PIN:-native}"
    echo "  Freq Boost:    ${BOOST_FREQ:-none}"
    exit 0
fi

echo "================================================================================"
echo " Total War: ROME REMASTERED — Frame Generation & Hardware Offload Launcher "
echo "================================================================================"

# Step 1: Environment & GPU Render Offload
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export DXVK_FILTER_DEVICE_NAME="NVIDIA"
export VKD3D_FILTER_DEVICE_NAME="NVIDIA"

# ponytail: CPU core pinning and frequency elevation are opt-in to avoid breaking generic systems
if [ -n "$CPU_PIN" ]; then
    export WINE_CPU_TOPOLOGY="$CPU_PIN"
fi

if [ -n "$BOOST_FREQ" ]; then
    freq_rc=0
    if [ -w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq ]; then
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
            echo "$BOOST_FREQ" > "$f" 2>/dev/null || freq_rc=$?
        done
    elif command -v sudo >/dev/null 2>&1; then
        sudo bash -c 'for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo "$1" > "$f" 2>/dev/null || f_rc=$?; done' _ "$BOOST_FREQ" 2>/dev/null || freq_rc=$?
    fi
fi

# Shader Caching
export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
export __GL_SHADER_DISK_CACHE_SIZE=10737418240

LS_PID=""

cleanup() {
    echo ""
    echo "==> Cleaning up background companion processes..."
    if [ -n "$LS_PID" ] && kill -0 "$LS_PID" 2>/dev/null; then
        echo "  Stopping Lossless Scaling companion (PID: $LS_PID)..."
        local kill_rc=0
        kill "$LS_PID" 2>/dev/null || kill_rc=$?
    fi
}
trap cleanup EXIT INT TERM

# ── Step 2: Launch Lossless Scaling Companion ────────────────────────────────
launch_lossless_scaling() {
    if [ -f "$LS_DIR/LosslessScaling.exe" ] && [ -d "$PROTON_EXP" ]; then
        echo "==> Starting Lossless Scaling companion in background..."
        STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
        STEAM_COMPAT_DATA_PATH="$STEAM_ROOT/steamapps/compatdata/$LS_APPID" \
        "$PROTON_EXP/proton" run "$LS_DIR/LosslessScaling.exe" >/dev/null 2>&1 &
        LS_PID=$!
        echo "    Lossless Scaling running (PID: $LS_PID)."
        echo "    Tip: Default scaling/framegen trigger hotkey is Ctrl+Alt+S."
    else
        echo "==> [NOTICE] Lossless Scaling binary not found at default path. Skipping companion."
    fi
}

# ── Step 3: Game Launch & Process Supervision ────────────────────────────────
launch_game() {
    local target_fps=${1:-100}
    local use_ls=${2:-0}
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local ls_controller="$script_dir/lossless-scaling.sh"
    local game_launcher="$STEAM_ROOT/steamapps/common/Total War ROME REMASTERED/Total War ROME REMASTERED.sh"

    if [ "$use_ls" -eq 1 ]; then
        echo "==> Configuring Lossless Scaling for ${target_fps} FPS target..."
        if [ -x "$ls_controller" ]; then
            "$ls_controller" tune "$target_fps" 2
        fi
        launch_lossless_scaling
    else
        echo "==> Native Linux rendering active (Lossless Scaling companion skipped to prevent cross-process IOMMU DMA conflicts)."
    fi

    local run_cmd=()
    if [ -n "$CPU_PIN" ] && command -v taskset >/dev/null 2>&1; then
        run_cmd+=(taskset -c "$CPU_PIN")
        echo "==> Launching Total War: ROME REMASTERED under CPU affinity ($CPU_PIN)..."
    else
        echo "==> Launching Total War: ROME REMASTERED..."
    fi

    if [ -x "$game_launcher" ]; then
        "${run_cmd[@]}" /usr/local/bin/prime-run mangohud "$game_launcher"
    else
        echo "    Native script not directly executable; dispatching via Steam URI..."
        DISPLAY="${DISPLAY:-:1}" steam "steam://rungameid/$ROME_APPID" >/dev/null 2>&1 &
        sleep 4
        while pgrep -f "Total War ROME" >/dev/null 2>&1; do
            sleep 2
        done
    fi
    echo "==> Game session ended."
    return 0
}

launch_game "$TARGET_FPS" "$USE_LS"
