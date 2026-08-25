# Lightweight foreground hardware monitor.

monitor_usage() {
    cat <<'HELP'
Usage: system monitor [all|cpu|gpu|ram|disk|network|battery|processes|once] [interval]

Examples:
  system monitor              Live dashboard; refresh every 2 seconds.
  system monitor all 5        Live dashboard; refresh every 5 seconds.
  system monitor network      Live network view.
  system monitor once         Print one snapshot and exit.

Press Ctrl+C to stop the monitor.
HELP
}

monitor_cpu_snapshot() {
    print_section "CPU"
    printf 'Load average: %s\n' "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo unavailable)"
    if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        printf 'Current frequency: %s MHz\n' \
            "$(awk '{printf "%.0f", $1 / 1000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
    fi
    sensors 2>/dev/null | grep -E 'Package id 0:|Tctl:|CPU Temperature:|Core [0-9]+:' | head -n 8 ||
        echo 'Temperature sensors unavailable.'
}

monitor_gpu_snapshot() {
    print_section "GPU"
    if has_command nvidia-smi && nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu \
        --format=csv,noheader,nounits 2>/dev/null; then
        return
    fi
    lspci 2>/dev/null | grep -Ei 'vga|3d|display' || echo 'GPU telemetry unavailable.'
}

monitor_ram_snapshot() {
    print_section "RAM and swap"
    free -h
}

monitor_disk_snapshot() {
    print_section "Storage"
    df -h / 2>/dev/null | sed -n '1,3p'
    if has_command iostat; then
        iostat -dx 1 1 2>/dev/null | awk 'NF && ($1 == "Device:" || $1 ~ /^(nvme|sd|vd|mmcblk)/) {print}' | head -n 12
    else
        echo 'Install sysstat for live disk read/write rates: sudo apt install sysstat'
    fi
}

monitor_network_snapshot() {
    local interface rx tx
    interface=$(active_network_interface)
    print_section "Network"
    printf 'Interface: %s\n' "${interface:-unknown}"
    if [ -n "$interface" ] && [ -d "/sys/class/net/$interface/statistics" ]; then
        rx=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)
        tx=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo 0)
        printf 'Totals: received %s, sent %s\n' \
            "$(numfmt --to=iec "$rx" 2>/dev/null || echo "${rx} bytes")" \
            "$(numfmt --to=iec "$tx" 2>/dev/null || echo "${tx} bytes")"
        ip -s link show dev "$interface" 2>/dev/null | sed -n '1,8p'
    else
        echo 'Network statistics unavailable.'
    fi
}

monitor_battery_snapshot() {
    print_section "Battery"
    local battery
    battery=$(find /sys/class/power_supply -maxdepth 1 -type l -name 'BAT*' | head -n 1)
    if [ -z "$battery" ]; then
        echo 'No battery detected.'
        return
    fi
    printf 'State: %s\n' "$(cat "$battery/status" 2>/dev/null || echo unknown)"
    printf 'Capacity: %s%%\n' "$(cat "$battery/capacity" 2>/dev/null || echo unknown)"
}

monitor_process_snapshot() {
    print_section "Top processes"
    ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -n 8
}

monitor_snapshot() {
    local section=$1
    case "$section" in
        all)
            monitor_cpu_snapshot
            monitor_gpu_snapshot
            monitor_ram_snapshot
            monitor_disk_snapshot
            monitor_network_snapshot
            monitor_battery_snapshot
            monitor_process_snapshot
            ;;
        cpu) monitor_cpu_snapshot ;;
        gpu) monitor_gpu_snapshot ;;
        ram|memory) monitor_ram_snapshot ;;
        disk|ssd|storage) monitor_disk_snapshot ;;
        network|net) monitor_network_snapshot ;;
        battery) monitor_battery_snapshot ;;
        processes|process) monitor_process_snapshot ;;
        *)
            monitor_usage >&2
            return 2
            ;;
    esac
}

run_monitor() {
    local section=${1:-all}
    local interval=${2:-2}
    local once=0

    if [ "$section" = "help" ] || [ "$section" = "-h" ] || [ "$section" = "--help" ]; then
        monitor_usage
        return
    fi
    if [ "$section" = "once" ]; then
        section=all
        once=1
    fi
    if ! [[ "$interval" =~ ^[1-9][0-9]*$ ]] || [ "$interval" -gt 3600 ]; then
        echo 'Interval must be a whole number from 1 to 3600 seconds.' >&2
        return 2
    fi

    if [ "$once" -eq 1 ] || [ ! -t 1 ]; then
        monitor_snapshot "$section"
        return $?
    fi

    trap 'printf "\nMonitor stopped.\n"; trap - INT TERM; return 130' INT TERM
    while true; do
        printf '\033[H\033[2J'
        printf 'System monitor | %s | refresh: %ss | Ctrl+C to stop\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$interval"
        monitor_snapshot "$section" || return $?
        sleep "$interval"
    done
}
