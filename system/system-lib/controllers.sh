# Game-controller inventory and joystick-only testing.

show_controller_status() {
    local controllers
    local device
    local found=0

    print_section "Game controllers"

    if [ ! -r /proc/bus/input/devices ]; then
        echo "Kernel input inventory is unavailable."
        return 1
    fi

    controllers=$(awk '
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
            if (handlers ~ /(^| )js[0-9]+( |$)/) {
                printf "%-40s %s\n", name, handlers
            }
        }
    ' /proc/bus/input/devices)

    if [ -n "$controllers" ]; then
        printf '%s\n' "$controllers"
    else
        echo "No joystick/gamepad handler was found."
    fi

    printf '\nJoystick device permissions:\n'
    for device in /dev/input/js*; do
        [ -e "$device" ] || continue
        found=1
        ls -l "$device"
    done
    if [ "$found" -eq 0 ]; then
        echo "No /dev/input/jsN device is accessible from this shell."
    fi
}

test_controller() {
    local requested=${1:-}
    local device

    if [[ "$requested" =~ ^js[0-9]+$ ]]; then
        device="/dev/input/$requested"
    elif [[ "$requested" =~ ^/dev/input/js[0-9]+$ ]]; then
        device="$requested"
    else
        echo "Usage: system controllers test <jsN|/dev/input/jsN>" >&2
        return 2
    fi

    if [ ! -e "$device" ]; then
        echo "Controller device not found: $device" >&2
        return 1
    fi

    if ! has_command jstest; then
        echo "jstest is not installed." >&2
        echo "Run: system controllers install-tools --yes" >&2
        return 127
    fi

    echo "Testing only $device; press Ctrl+C to quit."
    jstest "$device"
}

install_controller_tools() {
    if [ "${1:-}" != "--yes" ]; then
        echo "This updates APT metadata and installs joystick tools." >&2
        echo "Run: system controllers install-tools --yes" >&2
        return 2
    fi

    sudo apt update &&
        sudo apt install -y joystick &&
        echo "Installed controller tools: joystick"
}
