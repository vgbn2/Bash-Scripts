# Firmware inventory and strongly guarded fwupd actions.

show_firmware_status() {
    local device_output

    print_section "System firmware"
    printf 'Vendor: '
    cat /sys/class/dmi/id/bios_vendor 2>/dev/null || echo "unavailable"
    printf 'BIOS version: '
    cat /sys/class/dmi/id/bios_version 2>/dev/null || echo "unavailable"
    printf 'BIOS date: '
    cat /sys/class/dmi/id/bios_date 2>/dev/null || echo "unavailable"
    printf 'Boot mode: '
    [ -d /sys/firmware/efi ] && echo "UEFI" || echo "Legacy BIOS"

    if has_command mokutil; then
        printf 'Secure Boot: '
        mokutil --sb-state 2>/dev/null || echo "unavailable"
    fi

    print_section "fwupd-managed devices"
    if ! has_command fwupdmgr; then
        echo "fwupdmgr is not installed."
        return 127
    fi

    device_output=$(fwupdmgr get-devices 2>&1)
    if [ $? -ne 0 ]; then
        printf '%s\n' "$device_output"
        return 1
    fi

    printf '%s\n' "$device_output" | awk '
        /^[[:space:]│]*[├└]─/ {
            line=$0
            gsub(/^[[:space:]│]*[├└]─/, "", line)
            print line
            next
        }
        /Current version:|Update State:|Problems:/ {
            sub(/^[[:space:]│]*/, "  ")
            print
        }
    '
}

show_firmware_updates() {
    local output
    local status

    print_section "Available firmware updates"

    if ! has_command fwupdmgr; then
        echo "fwupdmgr is not installed."
        return 127
    fi

    output=$(fwupdmgr get-updates 2>&1)
    status=$?
    printf '%s\n' "$output"

    if [ "$status" -ne 0 ] &&
        printf '%s\n' "$output" |
            grep -Eqi 'No updatable devices|No updates available'; then
        return 0
    fi

    return "$status"
}

show_firmware_history() {
    print_section "Firmware update history"

    if ! has_command fwupdmgr; then
        echo "fwupdmgr is not installed."
        return 127
    fi

    fwupdmgr get-history
}

refresh_firmware_metadata() {
    if [ "${1:-}" != "--yes" ]; then
        echo "This downloads current firmware metadata." >&2
        echo "Run: system firmware refresh --yes" >&2
        return 2
    fi

    if ! has_command fwupdmgr; then
        echo "fwupdmgr is not installed." >&2
        return 127
    fi

    fwupdmgr refresh --force
}

firmware_power_is_safe() {
    local supply
    local capacity
    local mains_online=0

    for supply in /sys/class/power_supply/*; do
        [ -d "$supply" ] || continue
        if [ "$(cat "$supply/type" 2>/dev/null)" = "Mains" ] &&
            [ "$(cat "$supply/online" 2>/dev/null)" = "1" ]; then
            mains_online=1
        fi
    done

    if [ "$mains_online" -ne 1 ]; then
        echo "Firmware update refused: connect AC power first." >&2
        return 1
    fi

    for supply in /sys/class/power_supply/BAT*; do
        [ -r "$supply/capacity" ] || continue
        capacity=$(cat "$supply/capacity")
        if [ "$capacity" -lt 40 ]; then
            echo "Firmware update refused: battery is ${capacity}% (minimum 40%)." >&2
            return 1
        fi
    done
}

update_firmware() {
    if [ "${1:-}" != "--yes" ]; then
        echo "Firmware updates can reboot the laptop and must not be interrupted." >&2
        echo "Run only when ready: system firmware update --yes" >&2
        return 2
    fi

    if ! has_command fwupdmgr; then
        echo "fwupdmgr is not installed." >&2
        return 127
    fi

    firmware_power_is_safe || return
    fwupdmgr update
}

install_firmware_tools() {
    if [ "${1:-}" != "--yes" ]; then
        echo "This updates APT metadata and installs firmware inspection tools." >&2
        echo "Run: system firmware install-tools --yes" >&2
        return 2
    fi

    sudo apt update &&
        sudo apt install -y fwupd dmidecode mokutil efibootmgr &&
        echo "Installed firmware tools: fwupd, dmidecode, mokutil, efibootmgr"
}
