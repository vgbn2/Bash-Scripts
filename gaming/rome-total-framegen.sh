#!/usr/bin/env bash
# rome-total-framegen.sh — Frame Generation & Hardware Offload Launcher for Total War: ROME REMASTERED
# Orchestrates NVIDIA RTX 3050 offload, P-core thread pinning, and Lossless Scaling companion.

set -euo pipefail

STEAM_ROOT="$HOME/.local/share/Steam"
ROME_APPID="885970"
LS_APPID="993090"
LS_DIR="$STEAM_ROOT/steamapps/common/Lossless Scaling"
LS_PFX="$STEAM_ROOT/steamapps/compatdata/$LS_APPID/pfx"
PROTON_EXP="$STEAM_ROOT/steamapps/common/Proton - Experimental"

echo "================================================================================"
echo "   Total War: ROME REMASTERED — Frame Generation & Hardware Offload Launcher    "
echo "================================================================================"

# ── Step 1: Environment & GPU Render Offload ─────────────────────────────────
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export DXVK_FILTER_DEVICE_NAME="NVIDIA"
export VKD3D_FILTER_DEVICE_NAME="NVIDIA"

# CPU Core Pinning: 4 P-Cores / 8 Threads (CPUs 0-7 @ 4.5 GHz)
export WINE_CPU_TOPOLOGY="8:0,1,2,3,4,5,6,7"

# Elevate single-core turbo ceiling to 4.2 GHz for RTS battle simulation
if [ -w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq ]; then
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo 4200000 > "$f"; done
elif command -v sudo >/dev/null 2>&1; then
    freq_rc=0
    sudo bash -c 'for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo 4200000 > "$f"; done' 2>/dev/null || freq_rc=$?
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

    echo "==> Launching Total War: ROME REMASTERED under P-Core affinity (0-7)..."
    if [ -x "$game_launcher" ]; then
        taskset -c 0-7 /usr/local/bin/prime-run mangohud "$game_launcher"
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

USE_LS=0
[[ "${1:-}" == "--ls" || "${2:-}" == "--ls" ]] && USE_LS=1
launch_game "${1:-100}" "$USE_LS"
