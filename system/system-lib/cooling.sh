# Fan and thermal-profile inspection.
# Raw fan RPM/PWM control is used only when the kernel exposes it.

show_cooling_status() {
    local hwmon
    local fan_file
    local found_fan=0
    local profile
    local choices
    local fan_mode

    print_section "Cooling and temperatures"
    sensors 2>/dev/null |
        grep -E 'Package id 0:|Core [0-9]+:|Composite:|edge:|temp[0-9]+:' ||
        echo "Temperature sensors are unavailable."

    print_section "Fan interfaces"
    for hwmon in /sys/class/hwmon/hwmon*; do
        [ -d "$hwmon" ] || continue
        for fan_file in "$hwmon"/fan*_input "$hwmon"/pwm[0-9]; do
            [ -e "$fan_file" ] || continue
            found_fan=1
            printf '%s: ' "${fan_file##*/}"
            cat "$fan_file" 2>/dev/null || echo unavailable
        done
    done
    if [ "$found_fan" -eq 0 ]; then
        echo "No standard fan RPM/PWM interface is exposed by the kernel."
        echo "Fan speed is controlled by Lenovo firmware profiles."
    fi

    print_section "Firmware cooling profile"
    profile=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || true)
    choices=$(cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null || true)
    printf 'Profile: %s\n' "${profile:-unavailable}"
    printf 'Choices: %s\n' "${choices:-unavailable}"

    for fan_mode in /sys/devices/platform/*/fan_mode /sys/devices/platform/*/*/fan_mode; do
        [ -e "$fan_mode" ] || continue
        printf 'Firmware fan mode (%s): ' "$fan_mode"
        cat "$fan_mode" 2>/dev/null || echo unavailable
    done
}

set_cooling_profile() {
    local profile=${1:-}
    local choices

    if [ ! -r /sys/firmware/acpi/platform_profile_choices ]; then
        echo "Firmware cooling profiles are unavailable." >&2
        return 1
    fi

    choices=$(cat /sys/firmware/acpi/platform_profile_choices)
    case " $choices " in
        *" $profile "*)
            printf '%s\n' "$profile" |
                sudo tee /sys/firmware/acpi/platform_profile >/dev/null &&
                echo "Cooling profile set to: $profile"
            ;;
        *)
            echo "Invalid cooling profile: $profile" >&2
            echo "Available profiles: $choices" >&2
            return 2
            ;;
    esac
}

install_cooling_tools() {
    if [ "${1:-}" != "--yes" ]; then
        echo "This installs fan/temperature inspection tools; it does not create fan control." >&2
        echo "Run: system cooling install-tools --yes" >&2
        return 2
    fi

    sudo apt update &&
        sudo apt install -y lm-sensors fancontrol &&
        echo "Installed cooling tools: lm-sensors, fancontrol"
}
