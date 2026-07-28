# CPU, memory, battery, GPU, SSD, and storage checks.

show_cpu_status() {
    print_section "CPU and temperature"
    if has_command cpu; then
        cpu status
    else
        echo "CPU control command not found."
    fi
    if has_command sensors; then
        sensors 2>/dev/null | grep -E 'Package id 0:|Core [0-9]+:' || true
    fi
}

show_ram_status() {
    print_section "RAM and swap"
    free -h
    swapon --show 2>/dev/null || true
}

show_battery_status() {
    local battery=/sys/class/power_supply/BAT1
    local mains=/sys/class/power_supply/ACAD
    local current_energy full_energy design_energy

    print_section "Battery"
    if [ ! -d "$battery" ]; then
        echo "Battery information is unavailable."
        return
    fi

    printf 'Charge: %s%%\n' "$(cat "$battery/capacity")"
    printf 'State: %s\n' "$(cat "$battery/status")"

    if [ -r "$mains/online" ]; then
        if [ "$(cat "$mains/online")" = "1" ]; then
            echo "AC power: connected"
        else
            echo "AC power: disconnected"
        fi
    fi

    [ -r "$battery/cycle_count" ] && printf 'Charge cycles: %s\n' "$(cat "$battery/cycle_count")"

    current_energy=$(cat "$battery/energy_now" 2>/dev/null || true)
    full_energy=$(cat "$battery/energy_full" 2>/dev/null || true)
    design_energy=$(cat "$battery/energy_full_design" 2>/dev/null || true)

    if [[ "$current_energy" =~ ^[0-9]+$ && "$full_energy" =~ ^[0-9]+$ ]]; then
        awk -v current="$current_energy" -v full="$full_energy" \
            'BEGIN {printf "Energy: %.1f / %.1f Wh\n", current / 1000000, full / 1000000}'
    fi
    if [[ "$full_energy" =~ ^[0-9]+$ && "$design_energy" =~ ^[0-9]+$ ]]; then
        awk -v full="$full_energy" -v design="$design_energy" \
            'BEGIN {printf "Battery health: %.0f%% of original capacity\n", 100 * full / design}'
    fi
}

show_gpu_status() {
    print_section "GPU"
    if has_command nvidia-smi; then
        nvidia-smi 2>&1
    else
        echo "nvidia-smi is not installed."
    fi
    if has_command vulkaninfo; then
        printf '\nVulkan summary:\n'
        vulkaninfo --summary 2>&1 | sed -n '1,40p'
    fi
}

show_ssd_health() {
    local device
    print_section "Physical SSDs"
    lsblk -d -o NAME,MODEL,SIZE,TYPE | grep -E '^(NAME|nvme|sd)'

    for device in /dev/nvme*n1; do
        [ -e "$device" ] || continue
        printf '\n--- %s ---\n' "$device"
        show_nvme_summary "$device"
    done
    show_filesystem_space
}

show_nvme_summary() {
    local device=$1
    local smart_output smart_health data_read_units data_written_units

    smart_health=$(sudo smartctl -H "$device" 2>/dev/null | \
        awk -F: '/SMART overall-health|SMART Health Status/ {gsub(/^ +/, "", $2); print $2; exit}')

    [ -n "$smart_health" ] && printf 'Health: %s\n' "$smart_health" || echo "Health: unavailable"

    if ! smart_output=$(sudo nvme smart-log "$device" 2>/dev/null); then
        echo "NVMe details: unavailable"
        return
    fi

    printf 'Temperature: %s\n' "$(nvme_value "$smart_output" temperature)"
    printf 'Wear used: %s\n' "$(nvme_value "$smart_output" percentage_used)"
    printf 'Power-on hours: %s\n' "$(nvme_value "$smart_output" power_on_hours)"
    printf 'Media errors: %s\n' "$(nvme_value "$smart_output" media_errors)"

    data_read_units=$(nvme_value "$smart_output" data_units_read)
    data_written_units=$(nvme_value "$smart_output" data_units_written)
    printf 'Data read: %s\n' "$(nvme_data_units_to_tb "$data_read_units")"
    printf 'Data written: %s\n' "$(nvme_data_units_to_tb "$data_written_units")"
}

nvme_value() {
    local output=$1 field=$2
    awk -F: -v field="$field" '$1 ~ "^[[:space:]]*" field "[[:space:]]*$" {
        value=$2
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        print value
        exit
    }' <<<"$output"
}

nvme_data_units_to_tb() {
    local units=${1//,/}
    units=${units//[[:space:]]/}
    if [[ ! "$units" =~ ^[0-9]+$ ]]; then
        echo "unavailable"
        return
    fi
    awk -v units="$units" 'BEGIN {printf "%.2f TB", units * 512000 / 1000000000000}'
}

show_filesystem_space() {
    print_section "Mounted storage"
    df -hT -x tmpfs -x devtmpfs | \
        awk 'NR == 1 || $7 == "/" || $7 == "/boot" || $7 == "/boot/efi" {print}'
}

show_storage_sections() {
    print_section "Storage by system section"
    echo "This scans the root filesystem and can take a moment."
    sudo du -xhd1 / 2>/dev/null | sort -h
}

show_home_storage() {
    print_section "Storage by home-folder section"
    du -xhd1 "$HOME" 2>/dev/null | sort -h
}
