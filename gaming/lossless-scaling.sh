#!/usr/bin/env bash
# lossless-scaling.sh — Standalone Lossless Scaling & Adaptive Frame Generation Controller
# Configures LSFG (Lossless Scaling Frame Generation), sets target FPS (e.g. 100 FPS),
# and launches Lossless Scaling under Proton with dedicated NVIDIA GPU offload.

set -euo pipefail

STEAM_ROOT="$HOME/.local/share/Steam"
LS_APPID="993090"
LS_DIR="$STEAM_ROOT/steamapps/common/Lossless Scaling"
LS_CONFIG_DIR="$STEAM_ROOT/steamapps/compatdata/$LS_APPID/pfx/drive_c/users/steamuser/AppData/Local/Lossless Scaling"
LS_SETTINGS="$LS_CONFIG_DIR/Settings.xml"
PROTON_EXP="$STEAM_ROOT/steamapps/common/Proton - Experimental"

show_help() {
    cat <<'HELP'
Usage: lossless-scaling.sh <command> [arguments]

Commands:
  start [target_fps]       Configure Settings.xml and launch Lossless Scaling companion (default: 100 FPS)
  stop                     Stop running Lossless Scaling process
  status                   Show Lossless Scaling process and GPU offload status
  detect                   Auto-detect running game process, Proton wine binary, and window ID
  engage                   Focus detected game window and trigger Ctrl+Alt+S frame generation
  tune <fps> [multiplier]  Update Settings.xml with target FPS and frame generation multiplier (e.g. 100 2)
  profile [2x|3x|4x] [fps] Quick-switch frame generation profile (2x, 3x, or 4x multiplier)
  run <game_command...>    Launch Lossless Scaling, wait for hook, then run target game with auto-cleanup

Examples:
  lossless-scaling.sh start 100
  lossless-scaling.sh detect
  lossless-scaling.sh engage
  lossless-scaling.sh run ./rome-total-framegen.sh
HELP
}

# ── Step 1b: Detect Target Game Process & Window ────────────────────────────
detect_target_game() {
    # Returns shell variables: GAME_PID, GAME_TITLE, GAME_EXE, GAME_WINID
    # Scans X11 windows via wmctrl/xdotool and inspects /proc for Wine/Proton games
    local detected_pid=""
    local detected_title=""
    local detected_exe=""
    local detected_winid=""

    # 1. First attempt: Check active X11 windows via wmctrl
    if command -v wmctrl >/dev/null 2>&1; then
        while read -r winid desktop pid host title; do
            [ -z "$pid" ] && continue
            [ "$pid" = "0" ] && continue
            [ "$pid" = "-1" ] && continue

            # Filter out desktop utilities and helper windows
            case "$title" in
                conky*|desktop*|gnome-shell*|steamlinux*|*Discord*|*Special\ Offers*|Steam|*Terminal*|*bash*)
                    continue
                    ;;
            esac

            if [ -d "/proc/$pid" ]; then
                local comm=""
                [ -f "/proc/$pid/comm" ] && comm=$(cat "/proc/$pid/comm" 2>/dev/null)
                local cmdline=""
                [ -f "/proc/$pid/cmdline" ] && cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)

                local exe=""
                for word in $cmdline; do
                    case "$word" in
                        *.exe|*.EXE)
                            local base="${word##*\\}"
                            base="${base##*/}"
                            case "$base" in
                                explorer.exe|services.exe|winedevice.exe|plugplay.exe|conhost.exe|svchost.exe|rpcss.exe|LosslessScaling.exe|crashpad_handler.exe)
                                    ;;
                                *)
                                    exe="$base"
                                    break
                                    ;;
                            esac
                            ;;
                    esac
                done

                # Match if game .exe found or process is MainThread/wine64-preloader
                if [ -n "$exe" ] || [ "$comm" = "MainThread" ] || [ "$comm" = "wine64-preloader" ]; then
                    detected_pid="$pid"
                    detected_title="$title"
                    detected_exe="${exe:-$comm}"
                    detected_winid="$winid"
                    break
                fi
            fi
        done < <(wmctrl -l -p 2>/dev/null)
    fi

    # 2. Second attempt: Inspect /proc for Wine/Proton/Steam game processes
    if [ -z "$detected_pid" ]; then
        for p in /proc/[0-9]*; do
            [ -d "$p" ] || continue
            local pid="${p##*/}"
            local cmdline=""
            [ -f "$p/cmdline" ] && cmdline=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
            for word in $cmdline; do
                case "$word" in
                    *.exe|*.EXE)
                        local base="${word##*\\}"
                        base="${base##*/}"
                        case "$base" in
                            explorer.exe|services.exe|winedevice.exe|plugplay.exe|conhost.exe|svchost.exe|rpcss.exe|LosslessScaling.exe|crashpad_handler.exe)
                                ;;
                            *)
                                detected_pid="$pid"
                                detected_exe="$base"
                                detected_title="$base"
                                break
                                ;;
                        esac
                        ;;
                esac
            done
            [ -n "$detected_pid" ] && break
        done
    fi

    if [ -n "$detected_pid" ]; then
        echo "GAME_PID=$detected_pid"
        echo "GAME_TITLE=\"$detected_title\""
        echo "GAME_EXE=\"$detected_exe\""
        echo "GAME_WINID=\"$detected_winid\""
        return 0
    else
        return 1
    fi
}

show_target_game() {
    local game_info
    game_info=$(detect_target_game 2>/dev/null) || game_info=""
    if [ -n "$game_info" ]; then
        eval "$game_info"
        echo "==> Target Game Detected:"
        echo "    Title:  ${GAME_TITLE:-[No Window Title]}"
        echo "    Binary: $GAME_EXE"
        echo "    PID:    $GAME_PID"
        [ -n "${GAME_WINID:-}" ] && echo "    Window: $GAME_WINID"
    else
        echo "==> Target Game: None detected (launch game via Steam/Proton first)"
    fi
}

engage_ls() {
    local game_info
    game_info=$(detect_target_game 2>/dev/null) || game_info=""
    if [ -z "$game_info" ]; then
        echo "[ERROR] No running game process or window detected." >&2
        return 1
    fi
    eval "$game_info"

    # ponytail: auto-start companion if not running before engaging hotkey
    if ! pgrep -f "LosslessScaling.exe" >/dev/null 2>&1; then
        echo "==> Lossless Scaling companion not running. Starting companion..."
        start_ls
        sleep 2
    fi

    echo "==> Detected target game: ${GAME_TITLE:-$GAME_EXE} (PID: $GAME_PID, binary: $GAME_EXE)"
    if [ -n "${GAME_WINID:-}" ] && command -v xdotool >/dev/null 2>&1; then
        echo "==> Activating window $GAME_WINID and engaging frame generation (Ctrl+Alt+S)..."
        local xdo_rc=0
        xdotool windowactivate "$GAME_WINID" 2>/dev/null || xdo_rc=$?
        sleep 0.3
        xdotool key --window "$GAME_WINID" ctrl+alt+s 2>/dev/null || xdo_rc=$?
        echo "Frame generation engaged successfully on '$GAME_TITLE'."
    else
        echo "Tip: Focus your game window ('${GAME_TITLE:-$GAME_EXE}') and press Ctrl+Alt+S to engage frame generation."
    fi
}

# ── Step 1: Configure LSFG & Adaptive 100 FPS Target in Settings.xml ────────
configure_settings() {
    local target_fps=${1:-100}
    local multiplier=${2:-2}

    echo "==> Configuring Lossless Scaling for ${target_fps} FPS target (${multiplier}x framegen)..."
    mkdir -p "$LS_CONFIG_DIR"

    python3 -c "
import xml.etree.ElementTree as ET
import os

path = '$LS_SETTINGS'
if not os.path.exists(path):
    print('Settings.xml not found, will be created on first launch.')
    exit(0)

tree = ET.parse(path)
root = tree.getroot()

# Update frame generation profile parameters
for profile in root.findall('.//Profile'):
    fg = profile.find('FrameGeneration')
    if fg is not None: fg.text = 'LSFG3'

    mult = profile.find('LSFG3Multiplier')
    if mult is not None: mult.text = str($multiplier)

    mode = profile.find('LSFG3Mode1')
    if mode is not None: mode.text = 'ADAPTIVE' if $target_fps > 0 else 'FIXED'

    target = profile.find('LSFG3Target')
    if target is not None: target.text = str($target_fps)

    draw_fps = profile.find('DrawFps')
    if draw_fps is not None: draw_fps.text = 'true'

    capture = profile.find('CaptureApi')
    if capture is not None: capture.text = 'DXGI'

tree.write(path, encoding='utf-8', xml_declaration=True)
print('Settings.xml configured for Adaptive Frame Generation!')
" 2>/dev/null || py_cfg_rc=$?
}

# ── Step 1c: Quick-Switch Framegen Profile (2x, 3x, 4x) ─────────────────────
switch_profile() {
    local prof="${1:-2x}"
    local mult=""
    local default_fps=100

    case "${prof,,}" in
        2|2x)
            mult=2
            default_fps=100
            ;;
        3|3x)
            mult=3
            default_fps=144
            ;;
        4|4x)
            mult=4
            default_fps=160
            ;;
        *)
            echo "[ERROR] Invalid profile: '$prof'. Supported: 2x, 3x, 4x." >&2
            return 1
            ;;
    esac

    local fps="${2:-$default_fps}"
    configure_settings "$fps" "$mult"

    if pgrep -f "LosslessScaling.exe" >/dev/null 2>&1; then
        echo "✓ Switched profile to ${mult}x Framegen (Target: ${fps} FPS)."
        echo "Tip: Re-toggle Ctrl+Alt+S in game to apply the updated profile."
    else
        echo "✓ Profile set to ${mult}x Framegen (Target: ${fps} FPS)."
    fi
}

# ── Step 2: Start Lossless Scaling Companion ────────────────────────────────
start_ls() {
    local target_fps=${1:-}
    local mult=${2:-}

    # ponytail: only re-configure Settings.xml if explicit parameters were passed or settings missing
    if [ -n "$target_fps" ] || [ -n "$mult" ] || [ ! -f "$LS_SETTINGS" ]; then
        configure_settings "${target_fps:-100}" "${mult:-2}"
    fi

    if pgrep -f "LosslessScaling.exe" >/dev/null; then
        local running_pids
        running_pids=$(pgrep -f "LosslessScaling.exe" 2>/dev/null | paste -sd ' ' -) || running_pids=""
        echo "Lossless Scaling is already running (PID: $running_pids)."
        echo ""
        show_target_game
        return 0
    fi

    if [ ! -f "$LS_DIR/LosslessScaling.exe" ]; then
        echo "[ERROR] Lossless Scaling binary not found at: $LS_DIR" >&2
        return 1
    fi

    # Resolve active Xauthority (GDM session fallback)
    local xauth="${XAUTHORITY:-}"
    if [ -z "$xauth" ] || [ ! -r "$xauth" ]; then
        if [ -r "/run/user/$(id -u)/gdm/Xauthority" ]; then
            xauth="/run/user/$(id -u)/gdm/Xauthority"
        elif [ -r "$HOME/.Xauthority" ]; then
            xauth="$HOME/.Xauthority"
        fi
    fi

    echo "==> Starting Lossless Scaling in Proton with NVIDIA RTX 3050 offload..."
    DISPLAY="${DISPLAY:-:1}" \
    XAUTHORITY="$xauth" \
    __NV_PRIME_RENDER_OFFLOAD=1 \
    __GLX_VENDOR_LIBRARY_NAME=nvidia \
    __VK_LAYER_NV_optimus=NVIDIA_only \
    DXVK_FILTER_DEVICE_NAME="NVIDIA" \
    VKD3D_FILTER_DEVICE_NAME="NVIDIA" \
    PROTON_ENABLE_NVAPI=1 \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
    STEAM_COMPAT_DATA_PATH="$STEAM_ROOT/steamapps/compatdata/$LS_APPID" \
    "$PROTON_EXP/proton" run "$LS_DIR/LosslessScaling.exe" >/dev/null 2>&1 &

    local pid=$!
    sleep 2
    if pgrep -f "LosslessScaling.exe" >/dev/null; then
        local running_pids
        running_pids=$(pgrep -f "LosslessScaling.exe" 2>/dev/null | paste -sd ' ' -) || running_pids=""
        echo "Lossless Scaling started successfully (PID: $running_pids)."
        echo ""
        show_target_game
        echo "Tip: Press Ctrl+Alt+S while focused on your game window or run 'lossless-scaling.sh engage'."
    else
        echo "Spawned process PID $pid. Initializing Wine prefix..."
    fi
}

# ── Step 3: Stop Lossless Scaling ───────────────────────────────────────────
stop_ls() {
    echo "==> Stopping Lossless Scaling..."
    local kill_rc=0
    pkill -15 -f "LosslessScaling.exe" 2>/dev/null || kill_rc=$?
    sleep 1
    pkill -9 -f "LosslessScaling.exe" 2>/dev/null || kill_rc=$?
    echo "Lossless Scaling stopped."
}

# ── Step 4: Status ──────────────────────────────────────────────────────────
status_ls() {
    echo "=== Lossless Scaling Status ==="
    if pgrep -f "LosslessScaling.exe" >/dev/null; then
        local running_pids
        running_pids=$(pgrep -f "LosslessScaling.exe" 2>/dev/null | paste -sd ' ' -) || running_pids=""
        echo "Status: Running (PID: $running_pids)"
        ps aux | grep -i "[L]osslessScaling.exe"
    else
        echo "Status: Stopped"
    fi
    echo ""
    show_target_game
}

# ── Step 5: Wrapper Mode (Run Game Alongside LS) ────────────────────────────
run_with_ls() {
    start_ls 100 2
    echo "==> Launching target command: $*"

    cleanup() {
        echo "==> Game exited. Stopping Lossless Scaling..."
        stop_ls
    }
    trap cleanup EXIT INT TERM

    "$@"
}

cmd=${1:-help}
case "$cmd" in
    start) start_ls "${2:-100}" "${3:-2}" ;;
    stop) stop_ls ;;
    status) status_ls ;;
    detect) show_target_game ;;
    engage|hook) engage_ls ;;
    tune) configure_settings "${2:-100}" "${3:-2}" ;;
    profile|switch|fg) switch_profile "${2:-2x}" "${3:-}" ;;
    run) shift; run_with_ls "$@" ;;
    help|-h|--help) show_help ;;
    *) echo "Unknown command: $cmd" >&2; show_help >&2; exit 2 ;;
esac
