# Keyboard, mouse, touchpad, and keyboard-backlight tools.
# Raw key-event monitoring is intentionally excluded.

show_input_status() {
    local devices

    print_section "Keyboard, mouse, and touchpad devices"

    if [ ! -r /proc/bus/input/devices ]; then
        echo "Kernel input inventory is unavailable."
        return 1
    fi

    devices=$(awk '
        BEGIN {RS=""; FS="\n"}
        {
            name=""; handlers=""
            for (i=1; i<=NF; i++) {
                if ($i ~ /^N: Name=/) {
                    name=$i
                    sub(/^N: Name="/, "", name)
                    sub(/"$/, "", name)
                }
                if ($i ~ /^H: Handlers=/) {
                    handlers=$i
                    sub(/^H: Handlers=/, "", handlers)
                }
            }
            lower=tolower(name)
            if (lower ~ /keyboard|mouse|touchpad|gaming kb|extra buttons/) {
                printf "%-48s %s\n", name, handlers
            }
        }
    ' /proc/bus/input/devices)

    if [ -n "$devices" ]; then
        printf '%s\n' "$devices"
    else
        echo "No keyboard, mouse, or touchpad entries were found."
    fi

    if has_command libinput; then
        print_section "libinput summary"
        libinput list-devices 2>/dev/null |
            grep -E '^(Device:|Kernel:|Group:|Capabilities:|Tap-to-click:|Natural Scrolling:)' ||
            echo "libinput could not read the current devices."
    else
        echo
        echo "Detailed libinput capabilities need: system input install-tools --yes"
    fi
}

show_input_settings() {
    print_section "GNOME input settings"

    if ! has_command gsettings; then
        echo "gsettings is unavailable."
        return 127
    fi

    printf 'Mouse speed: '
    gsettings get org.gnome.desktop.peripherals.mouse speed 2>/dev/null ||
        echo "unavailable"
    printf 'Mouse natural scrolling: '
    gsettings get org.gnome.desktop.peripherals.mouse natural-scroll 2>/dev/null ||
        echo "unavailable"
    printf 'Touchpad speed: '
    gsettings get org.gnome.desktop.peripherals.touchpad speed 2>/dev/null ||
        echo "unavailable"
    printf 'Touchpad tap-to-click: '
    gsettings get org.gnome.desktop.peripherals.touchpad tap-to-click 2>/dev/null ||
        echo "unavailable"
    printf 'Touchpad natural scrolling: '
    gsettings get org.gnome.desktop.peripherals.touchpad natural-scroll 2>/dev/null ||
        echo "unavailable"
}

set_mouse_speed() {
    local speed=${1:-}

    if ! [[ "$speed" =~ ^-?(0([.][0-9]+)?|1([.]0+)?)$ ]]; then
        echo "Usage: system input mouse-speed <-1.0 to 1.0>" >&2
        return 2
    fi

    if ! has_command gsettings; then
        echo "gsettings is unavailable." >&2
        return 127
    fi

    gsettings set org.gnome.desktop.peripherals.mouse speed "$speed" &&
        printf 'Mouse speed set to %s (-1 slow, 0 default, 1 fast).\n' "$speed"
}

show_mouse_speed() {
    print_section "Mouse sensitivity"

    if ! has_command gsettings; then
        echo "gsettings is unavailable."
        return 127
    fi

    printf 'Speed: '
    gsettings get org.gnome.desktop.peripherals.mouse speed 2>/dev/null ||
        echo "unavailable"
    echo "Range: -1.0 (slow) to 1.0 (fast); 0 is the default."
}

keyboard_backlight_device() {
    local device

    for device in /sys/class/leds/*kbd_backlight*; do
        [ -d "$device" ] || continue
        basename -- "$device"
        return
    done
}

show_keyboard_backlight() {
    local device
    local path

    print_section "Keyboard backlight"
    device=$(keyboard_backlight_device)

    if [ -z "$device" ]; then
        echo "No Linux keyboard-backlight interface was detected."
        return 1
    fi

    path="/sys/class/leds/$device"
    printf 'Device: %s\n' "$device"
    printf 'Level: %s of %s\n' \
        "$(cat "$path/brightness" 2>/dev/null || echo unavailable)" \
        "$(cat "$path/max_brightness" 2>/dev/null || echo unavailable)"
}

set_keyboard_backlight() {
    local level=${1:-}
    local device
    local maximum

    device=$(keyboard_backlight_device)
    if [ -z "$device" ]; then
        echo "No Linux keyboard-backlight interface was detected." >&2
        return 1
    fi

    maximum=$(cat "/sys/class/leds/$device/max_brightness" 2>/dev/null)
    if ! [[ "$level" =~ ^[0-9]+$ ]] ||
        [ "$level" -gt "$maximum" ]; then
        echo "Usage: system input backlight <0-$maximum>" >&2
        return 2
    fi

    if ! has_command brightnessctl; then
        echo "brightnessctl is not installed." >&2
        echo "Run: system input install-tools --yes" >&2
        return 127
    fi

    brightnessctl --device="$device" set "$level"
}

install_input_tools() {
    if [ "${1:-}" != "--yes" ]; then
        echo "This updates APT metadata and installs input inspection tools." >&2
        echo "Run: system input install-tools --yes" >&2
        return 2
    fi

    sudo apt update &&
        sudo apt install -y libinput-tools evtest brightnessctl &&
        echo "Installed input tools: libinput-tools, evtest, brightnessctl"
}

show_keyboard_rgb() {
    print_section "Keyboard RGB"

    if has_command lsusb; then
        lsusb 2>/dev/null | grep -Ei 'keyboard|SINO WEALTH|258a:002a' ||
            echo "No USB keyboard identity was visible."
    fi

    if [ -d /sys/class/leds/platform::kbd_backlight ]; then
        echo "Internal Lenovo keyboard: brightness levels only; no RGB interface."
    fi

    if ! has_command openrgb; then
        echo "OpenRGB is not installed, so USB keyboard RGB compatibility"
        echo "has not been confirmed."
        echo "Install it with: system input install-rgb --yes"
        return 127
    fi

    openrgb --list-devices
}

set_keyboard_rgb() {
    local device=${1:-}
    local pattern=${2:-}
    local color=${3:-}
    local confirmation=${4:-}
    local mode

    if ! [[ "$device" =~ ^[0-9]+$ ]] ||
        ! [[ "$color" =~ ^[0-9A-Fa-f]{6}$ ]]; then
        echo "Usage: system input rgb set <device> <pattern> <RRGGBB> --yes" >&2
        return 2
    fi

    case "$pattern" in
        static) mode="Static" ;;
        breathing) mode="Breathing" ;;
        rainbow) mode="Rainbow" ;;
        spectrum) mode="Spectrum Cycle" ;;
        wave) mode="Rainbow Wave" ;;
        *)
            echo "Pattern must be: static, breathing, rainbow, spectrum, or wave." >&2
            return 2
            ;;
    esac

    if [ "$confirmation" != "--yes" ]; then
        echo "This changes RGB state on OpenRGB device $device." >&2
        echo "Repeat the command with --yes." >&2
        return 2
    fi

    if ! has_command openrgb; then
        echo "OpenRGB is not installed." >&2
        echo "Run: system input install-rgb --yes" >&2
        return 127
    fi

    openrgb --device "$device" --mode "$mode" --color "${color^^}"
}

install_rgb_tools() {
    if [ "${1:-}" != "--yes" ]; then
        echo "This updates APT metadata and installs OpenRGB." >&2
        echo "Run: system input install-rgb --yes" >&2
        return 2
    fi

    sudo apt update &&
        sudo apt install -y openrgb &&
        echo "OpenRGB installed. Run: system input rgb status"
}
