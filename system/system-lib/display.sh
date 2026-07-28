# Display inventory, backlight control, and external-monitor checks.

display_backlight_device() {
    local device

    for device in /sys/class/backlight/*; do
        [ -d "$device" ] || continue
        basename -- "$device"
        return
    done
}

show_display_brightness() {
    local device
    local path
    local current
    local maximum
    local percent

    print_section "Laptop display brightness"
    device=$(display_backlight_device)

    if [ -z "$device" ]; then
        echo "No Linux display-backlight interface was detected."
        return 1
    fi

    path="/sys/class/backlight/$device"
    current=$(cat "$path/actual_brightness" 2>/dev/null ||
        cat "$path/brightness" 2>/dev/null)
    maximum=$(cat "$path/max_brightness" 2>/dev/null)
    percent=$(awk -v current="$current" -v maximum="$maximum" \
        'BEGIN {if (maximum > 0) printf "%.0f", current * 100 / maximum; else print 0}')

    printf 'Device: %s\n' "$device"
    printf 'Brightness: %s of %s (%s%%)\n' "$current" "$maximum" "$percent"
}

show_display_status() {
    print_section "Display session"
    printf 'Session type: %s\n' "${XDG_SESSION_TYPE:-unknown}"

    print_section "Connected displays"
    if has_command xrandr; then
        if ! xrandr --current 2>/dev/null | grep ' connected'; then
            echo "Display server is not accessible from this shell."
        fi
    else
        echo "xrandr is not installed."
    fi

    show_display_brightness || true

    print_section "Graphics adapters"
    lspci | grep -Ei 'VGA|3D|Display' || true
}

show_external_displays() {
    print_section "External monitor controls"

    if ! has_command ddcutil; then
        echo "ddcutil is not installed."
        echo "Run: system display install-tools --yes"
        return 127
    fi

    ddcutil detect
}

valid_ddc_display() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

set_external_contrast() {
    local contrast=${1:-}
    local display=${2:-1}

    if ! [[ "$contrast" =~ ^[0-9]+$ ]] ||
        [ "$contrast" -lt 1 ] ||
        [ "$contrast" -gt 100 ] ||
        ! valid_ddc_display "$display"; then
        echo "Usage: system display contrast <1-100> [display-number]" >&2
        return 2
    fi

    if ! has_command ddcutil; then
        echo "ddcutil is not installed." >&2
        echo "Run: system display install-tools --yes" >&2
        return 127
    fi

    ddcutil setvcp 12 "$contrast" --display "$display"
}

show_external_contrast() {
    local display=${1:-1}

    print_section "External monitor contrast"

    if ! valid_ddc_display "$display"; then
        echo "Display number must be a positive integer." >&2
        return 2
    fi

    if ! has_command ddcutil; then
        echo "ddcutil is not installed." >&2
        return 127
    fi

    ddcutil getvcp 12 --display "$display"
}

show_display_color() {
    local display=${1:-1}
    local preset_output

    print_section "Desktop color temperature"
    if has_command gsettings; then
        printf 'Night Light enabled: '
        gsettings get org.gnome.settings-daemon.plugins.color \
            night-light-enabled 2>/dev/null || echo "unavailable"
        printf 'Night Light temperature: '
        gsettings get org.gnome.settings-daemon.plugins.color \
            night-light-temperature 2>/dev/null || echo "unavailable"
    else
        echo "gsettings is unavailable."
    fi

    print_section "External monitor color preset"
    if has_command ddcutil && valid_ddc_display "$display"; then
        preset_output=$(ddcutil getvcp 14 --display "$display" 2>&1 || true)
        if printf '%s\n' "$preset_output" | grep -q 'UNABLE TO FORMAT'; then
            echo "Monitor preset: vendor-specific value (ddcutil cannot decode it)."
            echo "Supported writes remain: 6500, 7500, 9300, and user1."
        else
            printf '%s\n' "$preset_output"
        fi
    else
        echo "DDC display information is unavailable."
    fi
}

set_display_warmth() {
    local temperature=${1:-}

    if ! [[ "$temperature" =~ ^[0-9]+$ ]] ||
        [ "$temperature" -lt 1700 ] ||
        [ "$temperature" -gt 4700 ]; then
        echo "Usage: system display color warm <1700-4700>" >&2
        return 2
    fi

    if ! has_command gsettings; then
        echo "gsettings is unavailable." >&2
        return 127
    fi

    gsettings set org.gnome.settings-daemon.plugins.color \
        night-light-temperature "uint32 $temperature" &&
        gsettings set org.gnome.settings-daemon.plugins.color \
            night-light-enabled true &&
        printf 'Display warmth set to %s K through GNOME Night Light.\n' \
            "$temperature"
}

disable_display_warmth() {
    if ! has_command gsettings; then
        echo "gsettings is unavailable." >&2
        return 127
    fi

    gsettings set org.gnome.settings-daemon.plugins.color \
        night-light-enabled false &&
        echo "GNOME Night Light disabled."
}

set_external_color_preset() {
    local preset=${1:-}
    local display=${2:-1}
    local value

    case "$preset" in
        6500) value="0x05" ;;
        7500) value="0x06" ;;
        9300) value="0x08" ;;
        user1) value="0x0b" ;;
        *)
            echo "Preset must be: 6500, 7500, 9300, or user1." >&2
            return 2
            ;;
    esac

    if ! valid_ddc_display "$display"; then
        echo "Display number must be a positive integer." >&2
        return 2
    fi

    if ! has_command ddcutil; then
        echo "ddcutil is not installed." >&2
        return 127
    fi

    ddcutil setvcp 14 "$value" --display "$display"
}

run_display_color() {
    local color_action=${1:-status}

    case "$color_action" in
        status) show_display_color "${2:-1}" ;;
        warm) set_display_warmth "${2:-}" ;;
        normal) disable_display_warmth ;;
        preset) set_external_color_preset "${2:-}" "${3:-1}" ;;
        *)
            echo "Usage: system display color [status|warm|normal|preset]" >&2
            return 2
            ;;
    esac
}

set_display_brightness() {
    local percent=${1:-}
    local device

    if ! [[ "$percent" =~ ^[0-9]+$ ]] ||
        [ "$percent" -lt 1 ] ||
        [ "$percent" -gt 100 ]; then
        echo "Usage: system display brightness <1-100>" >&2
        return 2
    fi

    device=$(display_backlight_device)
    if [ -z "$device" ]; then
        echo "No Linux display-backlight interface was detected." >&2
        return 1
    fi

    if ! has_command brightnessctl; then
        echo "brightnessctl is not installed." >&2
        echo "Run: system display install-tools --yes" >&2
        return 127
    fi

    brightnessctl --device="$device" set "${percent}%"
}

install_display_tools() {
    if [ "${1:-}" != "--yes" ]; then
        echo "This updates APT metadata and installs display tools." >&2
        echo "Run: system display install-tools --yes" >&2
        return 2
    fi

    sudo apt update &&
        sudo apt install -y brightnessctl ddcutil edid-decode &&
        echo "Installed display tools: brightnessctl, ddcutil, edid-decode"
}
