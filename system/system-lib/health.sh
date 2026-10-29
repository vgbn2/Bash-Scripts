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
    local device name rota
    print_section "Physical SSDs"
    lsblk -d -o NAME,MODEL,SIZE,ROTA,TYPE | grep -E '^(NAME|nvme|sd)'

    # NVMe drives
    for device in /dev/nvme*n1; do
        [ -e "$device" ] || continue
        printf '\n--- %s (NVMe) ---\n' "$device"
        show_nvme_summary "$device"
    done

    # SATA SSDs (non-rotational block devices)
    for device in /dev/sd[a-z]; do
        [ -e "$device" ] || continue
        name="${device##*/}"
        rota=$(cat "/sys/block/${name}/queue/rotational" 2>/dev/null || echo "1")
        [ "$rota" = "0" ] || continue
        printf '\n--- %s (SATA SSD) ---\n' "$device"
        show_sata_ssd_summary "$device"
    done

    show_filesystem_space
}

show_sata_ssd_summary() {
    local device=$1
    local smart_health attrs wear_val lba written_tb power_on

    smart_health=$(sudo smartctl -H "$device" 2>/dev/null | \
        awk -F: '/SMART overall-health|SMART Health Status/ {gsub(/^ +/, "", $2); print $2; exit}')

    [ -n "$smart_health" ] && printf 'Health: %s\n' "$smart_health" || echo "Health: unavailable"

    attrs=$(sudo smartctl -A "$device" 2>/dev/null)
    if [ -z "$attrs" ]; then
        echo "SMART attributes: unavailable"
        return
    fi

    # ponytail: wear percentage from standard SATA SSD indicators (177, 233, 231)
    wear_val=$(awk '
        $1=="233" || $2=="Media_Wearout_Indicator" || $1=="177" || $2=="Wear_Leveling_Count" || $1=="231" || $2=="SSD_Life_Left" {
            val = $4 + 0
            if (val > 0 && val <= 100) { printf "%d%%", 100 - val; exit }
        }' <<<"$attrs")
    printf 'Wear used: %s\n' "${wear_val:-unavailable}"

    # Power-on hours (attribute 9)
    power_on=$(awk '$1=="9" || $2=="Power_On_Hours" || $2=="Power_On_Hours_and_Msec" { print $10; exit }' <<<"$attrs")
    printf 'Power-on hours: %s\n' "${power_on:-unavailable}"

    # Total LBAs written (attribute 241, 1 LBA = 512 bytes)
    lba=$(awk '$1=="241" || $2=="Total_LBAs_Written" { print $10; exit }' <<<"$attrs")
    if [[ "$lba" =~ ^[0-9]+$ ]]; then
        written_tb=$(awk -v lba="$lba" 'BEGIN { printf "%.2f TB", (lba * 512) / 10^12 }')
    fi
    printf 'Data written: %s\n' "${written_tb:-unavailable}"
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

    printf 'Critical warning: %s\n' "$(nvme_value "$smart_output" critical_warning)"
    printf 'Temperature: %s\n' "$(format_temperature_c "$(nvme_value "$smart_output" temperature)")"
    printf 'Available spare: %s\n' "$(nvme_value_first "$smart_output" available_spare avail_spare)"
    printf 'Spare threshold: %s\n' "$(nvme_value_first "$smart_output" available_spare_threshold spare_threshold spare_thresh)"
    printf 'Wear used: %s\n' "$(nvme_value_first "$smart_output" percentage_used percent_used)"
    printf 'Power-on hours: %s\n' "$(nvme_value "$smart_output" power_on_hours)"
    printf 'Power cycles: %s\n' "$(nvme_value "$smart_output" power_cycles)"
    printf 'Unsafe shutdowns: %s\n' "$(nvme_value "$smart_output" unsafe_shutdowns)"
    printf 'Media errors: %s\n' "$(nvme_value "$smart_output" media_errors)"
    printf 'Error log entries: %s\n' "$(nvme_value "$smart_output" num_err_log_entries)"

    data_read_units=$(nvme_value "$smart_output" data_units_read)
    data_written_units=$(nvme_value "$smart_output" data_units_written)
    printf 'Data read: %s\n' "$(nvme_data_units_to_tb "$data_read_units")"
    printf 'Data written: %s\n' "$(nvme_data_units_to_tb "$data_written_units")"
    printf 'Host read commands: %s\n' "$(format_command_count "$(nvme_value "$smart_output" host_read_commands)")"
    printf 'Host write commands: %s\n' "$(format_command_count "$(nvme_value "$smart_output" host_write_commands)")"
    printf 'Controller busy time: %s\n' "$(nvme_value "$smart_output" controller_busy_time)"
    printf 'Warning temperature time: %s\n' \
        "$(nvme_value_first "$smart_output" warning_temp_time warning_temperature_time)"
    printf 'Critical temperature time: %s\n' \
        "$(nvme_value_first "$smart_output" critical_comp_time critical_temperature_time critical_composite_temperature_time)"

    local t1 t2 t3
    t1=$(nvme_value "$smart_output" temperature_sensor_1)
    t2=$(nvme_value "$smart_output" temperature_sensor_2)
    t3=$(nvme_value "$smart_output" temperature_sensor_3)
    local t_sensors=()
    [ -n "$t1" ] && t_sensors+=("S1: $t1")
    [ -n "$t2" ] && t_sensors+=("S2: $t2")
    [ -n "$t3" ] && t_sensors+=("S3: $t3")
    if [ ${#t_sensors[@]} -gt 0 ]; then
        local IFS=" | "
        printf 'Temperature sensors: %s\n' "${t_sensors[*]}"
    fi
}

show_nvme_raw() {
    local device=${1:-}

    if ! [[ "$device" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
        echo "Usage: system ssd raw /dev/nvmeNnM" >&2
        return 2
    fi

    print_section "Raw NVMe SMART log: $device"
    sudo nvme smart-log "$device"
}

nvme_value() {
    local output=$1 field=$2
    awk -F: -v wanted="$field" '
        function normalize(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/[^[:alnum:]]+/, "_", value)
            gsub(/^_+|_+$/, "", value)
            return tolower(value)
        }
        normalize($1) == wanted {
            value=$2
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            print value
            exit
        }' <<<"$output"
}

nvme_value_first() {
    local output=$1 field value
    shift
    for field in "$@"; do
        value=$(nvme_value "$output" "$field")
        if [ -n "$value" ]; then
            printf '%s\n' "$value"
            return
        fi
    done
    echo "unavailable"
}

nvme_data_units_to_tb() {
    local raw=$1 units
    units=$(awk '{print $1}' <<<"$raw")
    units=${units//,/}
    units=${units//[[:space:]]/}
    if [[ ! "$units" =~ ^[0-9]+$ ]]; then
        if [[ "$raw" =~ \(([0-9.]+[[:space:]]*[A-Za-z]+)\) ]] || [[ "$raw" =~ \[([0-9.]+[[:space:]]*[A-Za-z]+)\] ]]; then
            echo "${BASH_REMATCH[1]}"
            return
        fi
        echo "unavailable"
        return
    fi
    # ponytail: NVMe spec Log 02h: 1 data unit = 1000 * 512-byte blocks (512 KB); 1 TB = 10^12 bytes
    awk -v units="$units" 'BEGIN {
        unit_bytes = 1000 * 512
        bytes_per_tb = 10^12
        printf "%.2f TB", (units * unit_bytes) / bytes_per_tb
    }'
}

format_command_count() {
    local raw=$1 num
    num=$(awk '{print $1}' <<<"$raw")
    num=${num//,/}
    num=${num//[[:space:]]/}
    if [[ ! "$num" =~ ^[0-9]+$ ]]; then
        echo "${raw:-unavailable}"
        return
    fi
    awk -v n="$num" 'BEGIN {
        billion = 10^9
        million = 10^6
        thousand = 10^3
        if (n >= billion) printf "%\x27d (%.2fB)", n, n / billion;
        else if (n >= million) printf "%\x27d (%.2fM)", n, n / million;
        else if (n >= thousand) printf "%\x27d (%.2fK)", n, n / thousand;
        else printf "%d", n;
    }'
}

format_temperature_c() {
    local raw=$1
    [ -z "$raw" ] && { echo "unavailable"; return; }

    # If contains Kelvin in parentheses e.g. "163 °F (346 K)"
    if [[ "$raw" =~ \(([0-9]+)[[:space:]]*K\) ]]; then
        local kelvin="${BASH_REMATCH[1]}"
        printf "%d °C\n" "$(( kelvin - 273 ))"
        return
    fi

    # If contains Celsius in parentheses e.g. "(73 °C / 163 °F)"
    if [[ "$raw" =~ \(([0-9]+)[[:space:]]*°?C ]]; then
        printf "%d °C\n" "${BASH_REMATCH[1]}"
        return
    fi

    # If Fahrenheit e.g. "163 °F"
    if [[ "$raw" =~ ^([0-9]+)[[:space:]]*°?F ]]; then
        local f="${BASH_REMATCH[1]}"
        local c=$(( (f - 32) * 5 / 9 ))
        printf "%d °C\n" "$c"
        return
    fi

    # If pure number or "X Celsius" / "X C"
    if [[ "$raw" =~ ^([0-9]+)[[:space:]]*(Celsius|C|°C)?$ ]]; then
        local val="${BASH_REMATCH[1]}"
        if [ "$val" -gt 200 ]; then
            printf "%d °C\n" "$(( val - 273 ))"
        else
            printf "%d °C\n" "$val"
        fi
        return
    fi

    echo "$raw"
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
