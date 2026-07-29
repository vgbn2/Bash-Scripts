#!/usr/bin/env bash
#
# system
# A small local command for checking and controlling this laptop.
#
# Health commands only read information. CPU and network commands change
# settings and will ask for sudo when needed.

set -u


# -----------------------------------------------------------------------------
# Help and small helpers
# -----------------------------------------------------------------------------

show_help() {
    cat <<'HELP'
Usage: system <area> <command> [arguments]

CHECKS (read-only)
  system status
      Show CPU, RAM, GPU, SSD, and network information.

  system cpu status
  system ram status
  system battery status
  system gpu status
  system ssd health
  system storage sections
  system storage home
  system network status
  system internet test

CHANGES (asks for sudo when needed)
  system cpu cool | balanced | game | full
      Apply a CPU/power profile.

  system cpu <GHz>
      Set a CPU frequency cap. Example: system cpu 3.3

  system network limit-download <percent> <max-mbps>
      Limit downloads. Example: system network limit-download 90 100
      This means 90% of 100 Mbps, so the limit is 90 Mbps.

  system network clear-download
      Remove the download limit.

HELP
}

print_section() {
    printf '\n=== %s ===\n' "$1"
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}


# -----------------------------------------------------------------------------
# Read-only health checks
# -----------------------------------------------------------------------------

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
    local current_energy
    local full_energy
    local design_energy

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

    if [ -r "$battery/cycle_count" ]; then
        printf 'Charge cycles: %s\n' "$(cat "$battery/cycle_count")"
    fi

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
    local smart_output
    local smart_health
    local data_read_units
    local data_written_units

    # SMART and NVMe health are read-only, but the kernel requires sudo access.
    smart_health=$(sudo smartctl -H "$device" 2>/dev/null | \
        awk -F: '/SMART overall-health|SMART Health Status/ {gsub(/^ +/, "", $2); print $2; exit}')

    if [ -n "$smart_health" ]; then
        printf 'Health: %s\n' "$smart_health"
    else
        echo "Health: unavailable"
    fi

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
    local output=$1
    local field=$2

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

    # nvme-cli aligns values with spaces; remove those before validating.
    units=${units//[[:space:]]/}

    if [[ ! "$units" =~ ^[0-9]+$ ]]; then
        echo "unavailable"
        return
    fi

    # NVMe data units are 512,000 bytes each.
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

active_network_interface() {
    ip route get 1.1.1.1 2>/dev/null |
        awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}'
}

show_network_status() {
    local interface

    interface=$(active_network_interface)

    print_section "Network"
    printf 'Active interface: %s\n' "${interface:-unknown}"

    printf '\nAddresses:\n'
    ip -br addr

    printf '\nRoutes:\n'
    ip route

    if [ -n "$interface" ] && has_command ethtool; then
        printf '\nEthernet link:\n'
        ethtool "$interface" 2>/dev/null |
            grep -E 'Speed:|Duplex:|Auto-negotiation:|Link detected:' || true
    fi

    printf '\nTCP summary:\n'
    ss -s

    if [ -n "$interface" ]; then
        printf '\nDownload limiter on %s:\n' "$interface"
        tc qdisc show dev "$interface" || true
    fi

    if [ -e /sys/class/net/ifb0 ]; then
        printf '\nIFB limiter details:\n'
        tc -s qdisc show dev ifb0 || true
    fi
}

test_internet() {
    print_section "Internet connection"

    printf 'Ping 1.1.1.1: '
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
    fi

    printf 'HTTPS request: '
    if curl -fsS --max-time 5 https://example.com >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
    fi
}

show_full_status() {
    show_cpu_status
    show_ram_status
    show_battery_status
    show_gpu_status
    show_ssd_health
    show_network_status
}


# -----------------------------------------------------------------------------
# Explicit setting changes
# -----------------------------------------------------------------------------

valid_download_limit() {
    local percent=$1 maximum=$2

    [[ "$percent" =~ ^[0-9]+$ ]] &&
        [[ "$maximum" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
        [ "$percent" -ge 1 ] &&
        [ "$percent" -le 100 ]
}

limit_download() {
    local percent=${1:-}
    local maximum=${2:-}
    local interface
    local rate

    if ! valid_download_limit "$percent" "$maximum"; then
        echo "Usage: system network limit-download <percent> <max-mbps>" >&2
        return 2
    fi

    interface=$(active_network_interface)
    if [ -z "$interface" ]; then
        echo "Could not find the active internet interface." >&2
        return 1
    fi

    rate=$(awk -v percent="$percent" -v maximum="$maximum" \
        'BEGIN {printf "%.3f", percent * maximum / 100}')

    # Downloads arrive on the real interface. IFB lets tc shape that traffic.
    sudo modprobe ifb numifbs=1

    if ! ip link show ifb0 >/dev/null 2>&1; then
        sudo ip link add ifb0 type ifb
    fi
    sudo ip link set ifb0 up

    # Create the ingress hook and redirect only when they are not present yet.
    if ! tc qdisc show dev "$interface" | grep -q 'ingress ffff:'; then
        sudo tc qdisc add dev "$interface" handle ffff: ingress
    fi

    if ! tc filter show dev "$interface" parent ffff: 2>/dev/null | grep -q 'ifb0'; then
        sudo tc filter add dev "$interface" parent ffff: protocol all \
            u32 match u32 0 0 action mirred egress redirect dev ifb0
    fi

    sudo tc qdisc replace dev ifb0 root tbf \
        rate "${rate}mbit" burst 32kbit latency 400ms

    echo "Download limit: ${rate} Mbps (${percent}% of ${maximum} Mbps)"
}

clear_download_limit() {
    local interface

    interface=$(active_network_interface)

    if [ -n "$interface" ]; then
        sudo tc qdisc del dev "$interface" ingress 2>/dev/null || true
    fi

    sudo tc qdisc del dev ifb0 root 2>/dev/null || true
    echo "Download limit cleared."
}


# -----------------------------------------------------------------------------
# Command dispatcher
# -----------------------------------------------------------------------------

area=${1:-help}
action=${2:-}

case "$area" in
    help|-h|--help)
        show_help
        ;;

    status)
        show_full_status
        ;;

    cpu)
        if [ -z "$action" ] || [ "$action" = "help" ]; then
            cpu --help
        elif [[ "$action" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            cpu "$action"
        else
            cpu "$action" "${3:-}"
        fi
        ;;

    ram)
        [ "$action" = "status" ] && show_ram_status || show_help
        ;;

    battery)
        [ "$action" = "status" ] && show_battery_status || show_help
        ;;

    gpu)
        [ "$action" = "status" ] && show_gpu_status || show_help
        ;;

    ssd)
        [ "$action" = "health" ] && show_ssd_health || show_help
        ;;

    storage)
        case "$action" in
            sections)
                show_storage_sections
                ;;
            home)
                show_home_storage
                ;;
            *)
                show_help
                ;;
        esac
        ;;

    internet)
        [ "$action" = "test" ] && test_internet || show_help
        ;;

    network)
        case "$action" in
            status)
                show_network_status
                ;;
            limit-download)
                limit_download "${3:-}" "${4:-}"
                ;;
            clear-download)
                clear_download_limit
                ;;
            *)
                show_help
                ;;
        esac
        ;;

    *)
        show_help
        ;;
esac
