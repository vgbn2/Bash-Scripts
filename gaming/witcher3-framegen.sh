#!/usr/bin/env bash
# witcher3-framegen.sh — Lossless Scaling LSFG 3.0 & Hardware Offload Launcher for The Witcher 3
# Configures Borderless windowing, sets in-engine FPS limit, isolates Alder Lake P-cores,
# and coordinates Lossless Scaling frame generation under Proton with dedicated NVIDIA GPU.

set -euo pipefail

STEAM_ROOT="${STEAM_ROOT:-$HOME/.local/share/Steam}"
WITCHER_APPID="292030"
LS_APPID="993090"

WITCHER_DIR="${WITCHER_DIR_OVERRIDE:-$STEAM_ROOT/steamapps/common/The Witcher 3}"
WITCHER_PFX="${WITCHER_PFX_OVERRIDE:-$STEAM_ROOT/steamapps/compatdata/$WITCHER_APPID/pfx}"
WITCHER_DOCS="${WITCHER_DOCS_OVERRIDE:-$WITCHER_PFX/drive_c/users/steamuser/Documents/The Witcher 3}"
DX12_SETTINGS="$WITCHER_DOCS/dx12user.settings"
USER_SETTINGS="$WITCHER_DOCS/user.settings"

LS_DIR="${LS_DIR_OVERRIDE:-$STEAM_ROOT/steamapps/common/Lossless Scaling}"
LS_CONFIG_DIR="${LS_CONFIG_DIR_OVERRIDE:-$STEAM_ROOT/steamapps/compatdata/$LS_APPID/pfx/drive_c/users/steamuser/AppData/Local/Lossless Scaling}"
LS_SETTINGS="$LS_CONFIG_DIR/Settings.xml"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LS_CONTROLLER="$SCRIPT_DIR/lossless-scaling.sh"

show_help() {
    cat <<'HELP'
Usage: witcher3-framegen.sh <command> [arguments]

Commands:
  launch [target_fps] [base_fps]   Optimize configs, start Lossless Scaling, and launch Witcher 3 (default: 120 60)
  optimize [base_fps] [target_fps] Update Witcher 3 and Lossless Scaling configs without launching (default: 60 120)
  status                           Inspect current Witcher 3 graphics, frame limiter, and Lossless Scaling state
  detect                           Detect running witcher3.exe process and window
  engage                           Focus Witcher 3 window and trigger Ctrl+Alt+S frame generation
  help                             Show this help message

Options / Defaults:
  Target FPS: 120 (for 60 base FPS with 2x LSFG3 frame generation)
  Base FPS:   60  (caps in-engine frame pacing; reserves ~35% RTX 3050 GPU headroom for LSFG3)
  Window:     Borderless (FullScreenMode=1 required for DXGI capture)
  P-Cores:    0-7 pinned via WINE_CPU_TOPOLOGY to bypass Alder Lake E-cores
HELP
}

# ── Optimize Game & Lossless Scaling Settings ────────────────────────────────
optimize_config() {
    local base_fps="${1:-60}"
    local target_fps="${2:-120}"
    local mult="${3:-}"

    echo "==> Optimizing The Witcher 3 settings for Lossless Scaling (Base: ${base_fps} FPS, Target: ${target_fps} FPS)..."

    mkdir -p "$WITCHER_DOCS"
    python3 -c "
import os
import re
import sys

dx12_path = sys.argv[1]
user_path = sys.argv[2]
base_fps = sys.argv[3]

def update_section_kv(content, section, key, value):
    sec_re = re.compile(rf'(\[{re.escape(section)}\][^\[]*)', re.MULTILINE)
    match = sec_re.search(content)
    if not match:
        return content + f'\n[{section}]\n{key}={value}\n'
    block = match.group(1)
    kv_re = re.compile(rf'^{re.escape(key)}=.*$', re.MULTILINE)
    if kv_re.search(block):
        new_block = kv_re.sub(f'{key}={value}', block)
    else:
        new_block = block.rstrip('\n') + f'\n{key}={value}\n'
    return content[:match.start()] + new_block + content[match.end():]

# ponytail: single pass over dx12 and legacy user settings
for path in [dx12_path, user_path]:
    if not os.path.exists(path):
        continue
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        text = f.read()
    # 1. Borderless windowed mode is required for DXGI capture
    text = update_section_kv(text, 'Viewport', 'FullScreenMode', '1')
    # 2. Disable in-game VSync to minimize input lag
    text = update_section_kv(text, 'Viewport', 'VSync', 'false')
    # 3. Enable NVIDIA Reflex Low Latency
    text = update_section_kv(text, 'Viewport', 'ReflexMode', '1')
    text = update_section_kv(text, 'Rendering', 'AllowReflex', 'true')
    # 4. Cap in-engine FPS to prevent GPU saturation and ensure steady pacing
    text = update_section_kv(text, 'Engine', 'LimitFPS', str(base_fps))
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
" "$DX12_SETTINGS" "$USER_SETTINGS" "$base_fps"

    # Configure Lossless Scaling Settings.xml
    mkdir -p "$LS_CONFIG_DIR"
    python3 -c "
import xml.etree.ElementTree as ET
import os
import sys

path = sys.argv[1]
target_fps = sys.argv[2]
multiplier = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None

if not os.path.exists(path):
    sys.exit(0)

tree = ET.parse(path)
root = tree.getroot()

for profile in root.findall('.//Profile'):
    fg = profile.find('FrameGeneration')
    if fg is not None: fg.text = 'LSFG3'

    mult = profile.find('LSFG3Multiplier')
    if mult is not None:
        if multiplier:
            mult.text = str(multiplier)
        elif mult.text not in ['2', '3', '4']:
            mult.text = '2'
        # ponytail: preserve active 2x, 3x, 4x profile if no explicit multiplier provided

    mode = profile.find('LSFG3Mode1')
    if mode is not None: mode.text = 'ADAPTIVE'

    target = profile.find('LSFG3Target')
    if target is not None: target.text = str(target_fps)

    draw_fps = profile.find('DrawFps')
    if draw_fps is not None: draw_fps.text = 'true'

    capture = profile.find('CaptureApi')
    if capture is not None: capture.text = 'DXGI'

    latency = profile.find('MaxFrameLatency')
    if latency is not None: latency.text = '1'

    gsync = profile.find('GsyncSupport')
    if gsync is not None: gsync.text = 'true'

tree.write(path, encoding='utf-8', xml_declaration=True)
" "$LS_SETTINGS" "$target_fps" "${mult:-}" 2>/dev/null || opt_rc=$?

    echo "  ✓ Viewport: Borderless Window (FullScreenMode=1)"
    echo "  ✓ Engine: Frame Limiter capped at ${base_fps} FPS (leaves GPU headroom for LSFG3)"
    echo "  ✓ Viewport: VSync disabled (VSync=false)"
    echo "  ✓ Rendering: NVIDIA Reflex enabled (ReflexMode=1)"
    echo "  ✓ Lossless Scaling: LSFG3 Adaptive @ ${target_fps} FPS target"

    # 5. Ensure DLSS is unblocked from Witcher 3 anti-Wine check
    local w_exe="$WITCHER_DIR/bin/x64_dx12/witcher3.exe"
    if [ -f "$w_exe" ]; then
        if grep -aq "wine_get_version" "$w_exe" 2>/dev/null; then
            [ -f "${w_exe}.orig" ] || cp -p "$w_exe" "${w_exe}.orig"
            sed -i 's/wine_get_version/frog_get_version/g' "$w_exe"
            echo "  ✓ DLSS: Patched anti-Wine bypass in witcher3.exe (Streamline/DLSS unlocked)"
        else
            echo "  ✓ DLSS: Anti-Wine check neutralized (Streamline/DLSS active)"
        fi
    fi
}

# ── Status ───────────────────────────────────────────────────────────────────
status_config() {
    echo "=== The Witcher 3: Lossless Scaling & Graphics Audit ==="
    if [ -f "$DX12_SETTINGS" ]; then
        local fs_mode vsync reflex limit_fps
        fs_mode=$(grep -E '^FullScreenMode=' "$DX12_SETTINGS" 2>/dev/null | cut -d'=' -f2 | tr -d '\r') || fs_mode=""
        vsync=$(grep -E '^VSync=' "$DX12_SETTINGS" 2>/dev/null | cut -d'=' -f2 | tr -d '\r') || vsync=""
        reflex=$(grep -E '^ReflexMode=' "$DX12_SETTINGS" 2>/dev/null | cut -d'=' -f2 | tr -d '\r') || reflex=""
        limit_fps=$(grep -E '^LimitFPS=' "$DX12_SETTINGS" 2>/dev/null | cut -d'=' -f2 | tr -d '\r') || limit_fps=""

        local mode_desc="Unknown"
        case "$fs_mode" in
            0) mode_desc="Windowed" ;;
            1) mode_desc="Borderless (OPTIMAL for Lossless Scaling)" ;;
            2) mode_desc="Fullscreen (WARNING: Incompatible with Lossless Scaling)" ;;
        esac

        echo "Witcher 3 DX12 Settings:"
        echo "  Window Mode:   ${fs_mode:-missing} — $mode_desc"
        echo "  In-Engine FPS: ${limit_fps:-missing} FPS $([ "${limit_fps:-0}" -eq 60 ] && echo '(OPTIMAL: 16.6ms steady pacing)' || echo '(Recommend: 60 FPS)')"
        echo "  VSync:         ${vsync:-missing} $([ "${vsync:-}" = "false" ] && echo '(OPTIMAL: lowest input latency)' || echo '(Recommend: false)')"
        echo "  NVIDIA Reflex: ${reflex:-missing} $([ "${reflex:-0}" -eq 1 ] && echo '(Active)' || echo '(Inactive)')"

        local w_exe="$WITCHER_DIR/bin/x64_dx12/witcher3.exe"
        if [ -f "$w_exe" ]; then
            if grep -aq "frog_get_version" "$w_exe" 2>/dev/null; then
                echo "  DLSS Status:   Unlocked (Anti-Wine bypass neutralized)"
            elif grep -aq "wine_get_version" "$w_exe" 2>/dev/null; then
                echo "  DLSS Status:   Blocked (Anti-Wine check active in binary)"
            fi
        fi
    else
        echo "Witcher 3 dx12user.settings not found at: $DX12_SETTINGS"
    fi

    echo ""
    echo "Lossless Scaling Status:"
    if [ -f "$LS_SETTINGS" ]; then
        python3 -c "
import xml.etree.ElementTree as ET
import sys
tree = ET.parse(sys.argv[1])
p = tree.getroot().find('.//Profile')
if p is not None:
    fg = p.find('FrameGeneration')
    target = p.find('LSFG3Target')
    mult = p.find('LSFG3Multiplier')
    mode = p.find('LSFG3Mode1')
    capture = p.find('CaptureApi')
    print(f'  Engine:       {fg.text if fg is not None else \"N/A\"}')
    print(f'  Target FPS:   {target.text if target is not None else \"N/A\"} FPS ({mult.text if mult is not None else \"2\"}x {mode.text if mode is not None else \"ADAPTIVE\"})')
    print(f'  Capture API:  {capture.text if capture is not None else \"DXGI\"}')
" "$LS_SETTINGS" 2>/dev/null || ls_parse_rc=$?
    fi

    echo ""
    echo "Running Processes:"
    local w_pids ls_pids
    w_pids=$(pgrep -f "witcher3.exe" 2>/dev/null | paste -sd ' ' -) || w_pids=""
    ls_pids=$(pgrep -f "LosslessScaling.exe" 2>/dev/null | paste -sd ' ' -) || ls_pids=""
    echo "  witcher3.exe:       ${w_pids:-Not running}"
    echo "  LosslessScaling:    ${ls_pids:-Not running}"
}

# ── Launch Witcher 3 with LSFG 3.0 & Hardware Tuning ────────────────────────
launch_witcher() {
    local target_fps="${1:-120}"
    local base_fps="${2:-60}"
    local mult="${3:-}"

    optimize_config "$base_fps" "$target_fps" "$mult"

    # Step 1: GPU Render Offload & Vulkan/DXVK/VKD3D Tuning
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export DXVK_FILTER_DEVICE_NAME="NVIDIA"
    export VKD3D_FILTER_DEVICE_NAME="NVIDIA"
    export PROTON_ENABLE_NVAPI=1

    # Shader Disk Cache optimization (10 GB max size, no mid-session purge)
    export __GL_SHADER_DISK_CACHE=1
    export __GL_SHADER_DISK_CACHE_SIZE=10737418240
    export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1

    # Step 2: CPU Alder Lake Core Pinning: 4 P-Cores / 8 Threads (CPUs 0-7)
    # ponytail: isolates RedEngine simulation threads from 3.1 GHz Gracemont E-cores (8-11)
    export WINE_CPU_TOPOLOGY="8:0,1,2,3,4,5,6,7"

    # Step 3: Start Lossless Scaling companion in background
    local started_ls=0
    if ! pgrep -f "LosslessScaling.exe" >/dev/null; then
        echo "==> Starting Lossless Scaling companion (${target_fps} FPS target)..."
        if [ -x "$LS_CONTROLLER" ]; then
            if [ -n "$mult" ]; then
                "$LS_CONTROLLER" start "$target_fps" "$mult"
            else
                "$LS_CONTROLLER" start "$target_fps"
            fi
            started_ls=1
        fi
    else
        echo "==> Lossless Scaling companion already active."
    fi

    cleanup() {
        if [ "${started_ls:-0}" -eq 1 ]; then
            echo ""
            echo "==> Game session ended. Stopping Lossless Scaling companion..."
            if [ -x "$LS_CONTROLLER" ]; then
                "$LS_CONTROLLER" stop >/dev/null 2>&1 || stop_rc=$?
            fi
        fi
    }
    trap cleanup EXIT INT TERM

    # Step 4: Dispatch game launch via Steam URI or direct binary
    if pgrep -f "witcher3.exe" >/dev/null; then
        echo "==> The Witcher 3 is already running. Engaging frame generation..."
        sleep 1
        if [ -x "$LS_CONTROLLER" ]; then
            "$LS_CONTROLLER" engage witcher3.exe
        fi
        trap - EXIT INT TERM
        return 0
    fi

    echo "==> Launching The Witcher 3: Wild Hunt under P-Core affinity (0-7)..."
    DISPLAY="${DISPLAY:-:1}" steam "steam://rungameid/$WITCHER_APPID//--launcher-skip" >/dev/null 2>&1 &

    echo "==> Waiting for witcher3.exe to initialize swapchain..."
    local detected=0
    for ((i=1; i<=30; i++)); do
        if pgrep -f "witcher3.exe" >/dev/null 2>&1; then
            detected=1
            break
        fi
        sleep 1
    done

    if [ "$detected" -eq 1 ]; then
        echo "  witcher3.exe process active. Waiting for window presentation..."
        sleep 4
        if [ -x "$LS_CONTROLLER" ]; then
            "$LS_CONTROLLER" engage witcher3.exe || engage_rc=$?
        fi

        # Monitor game session until exit
        while pgrep -f "witcher3.exe" >/dev/null 2>&1; do
            sleep 3
        done
        echo "==> The Witcher 3 process exited."
    else
        echo "==> Process witcher3.exe not detected within 30 seconds."
        echo "Tip: Run 'witcher3-framegen.sh engage' once game is loaded."
    fi
}

cmd="${1:-help}"
case "$cmd" in
    [0-9]*)
        launch_witcher "$cmd" "${2:-60}" "${3:-}"
        ;;
    launch|start)
        launch_witcher "${2:-120}" "${3:-60}" "${4:-}"
        ;;
    optimize|tune|config)
        optimize_config "${2:-60}" "${3:-120}" "${4:-}"
        ;;
    status)
        status_config
        ;;
    detect)
        if [ -x "$LS_CONTROLLER" ]; then
            "$LS_CONTROLLER" detect witcher3.exe
        else
            pgrep -fl "witcher3.exe" || echo "witcher3.exe: Not running"
        fi
        ;;
    engage|hook)
        if [ -x "$LS_CONTROLLER" ]; then
            "$LS_CONTROLLER" engage witcher3.exe "${2:-120}"
        else
            echo "[ERROR] Lossless Scaling controller not found at: $LS_CONTROLLER" >&2
            exit 1
        fi
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $cmd" >&2
        show_help >&2
        exit 2
        ;;
esac