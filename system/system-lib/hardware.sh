# Hardware inventory and focused status commands.

show_thermals() {
    local device smart_output temperature

    print_section "CPU and motherboard temperatures"
    sensors 2>/dev/null | grep -E 'Package id 0:|Core [0-9]+:|edge:|temp[0-9]+:' || true

    print_section "GPU temperature and power"
    if has_command nvidia-smi; then
        nvidia-smi --query-gpu=name,temperature.gpu,power.draw,utilization.gpu \
            --format=csv,noheader 2>&1 || true
    fi

    print_section "SSD temperatures"
    for device in /dev/nvme*n1; do
        [ -e "$device" ] || continue
        if smart_output=$(sudo nvme smart-log "$device" 2>/dev/null); then
            temperature=$(nvme_value "$smart_output" temperature)
            printf '%s: %s\n' "$device" "$temperature"
        else
            printf '%s: unavailable\n' "$device"
        fi
    done
}

show_memory_hardware() {
    print_section "Memory summary"
    free -h

    print_section "Installed memory modules"
    if has_command dmidecode; then
        sudo dmidecode -t 17 2>/dev/null | \
            grep -E 'Memory Device$|Size:|Locator:|Type:|Speed:|Configured Memory Speed:' || true
    fi
}

show_hardware_summary() {
    print_section "Laptop and firmware"
    printf 'Vendor: '; cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true
    printf 'Model: '; cat /sys/class/dmi/id/product_name 2>/dev/null || true
    printf 'BIOS version: '; cat /sys/class/dmi/id/bios_version 2>/dev/null || true
    printf 'BIOS date: '; cat /sys/class/dmi/id/bios_date 2>/dev/null || true

    print_section "CPU"
    lscpu | grep -E 'Model name:|CPU\(s\):|Thread\(s\) per core:|Core\(s\) per socket:' || true

    print_section "Graphics and network adapters"
    lspci | grep -Ei 'VGA|3D|Display|Ethernet|Network' || true

    print_section "Physical storage"
    lsblk -d -o NAME,MODEL,SIZE,TYPE | grep -E '^(NAME|nvme|sd)'
}

show_devices() {
    print_section "USB devices"
    lsusb

    print_section "Bluetooth devices"
    if has_command bluetoothctl; then
        bluetoothctl devices 2>/dev/null || true
    fi

    print_section "Input devices"
    find /dev/input -maxdepth 1 -type c -name 'event*' -printf '%f\n' 2>/dev/null || true
}

show_kernel_matches() {
    local title=$1
    local pattern=$2
    local matches

    print_section "$title"

    matches=$(journalctl -k -b --no-pager 2>&1 | grep -Ei "$pattern" || true)
    if [ -n "$matches" ]; then
        printf '%s\n' "$matches"
    else
        echo "No matching kernel events in this boot."
    fi
}

show_kernel_error_summary() {
    print_section "Kernel error summary for this boot"

    # Keep this short: show the key line, not every stack-trace frame.
    show_kernel_matches "Out-of-memory events" \
        'out of memory|oom-kill|killed process|oom_reaper'
    show_kernel_matches "GPU errors" \
        'nvrm|xid|gpu.*(error|fail|timeout)|drm.*(error|fail)'
    show_kernel_matches "SSD and filesystem errors" \
        'nvme.*(error|fail|timeout|reset)|i/o error|buffer i/o|ext4-fs error|blk_update_request'
    show_kernel_matches "Network errors" \
        'iwlwifi.*(error|fail|timeout)|r8169.*(error|fail|timeout)|network.*(error|fail|timeout)'
}

show_oom_errors() {
    show_kernel_matches "Out-of-memory events" \
        'out of memory|oom-kill|killed process|oom_reaper'
}

show_gpu_errors() {
    show_kernel_matches "GPU errors" \
        'nvrm|xid|gpu.*(error|fail|timeout)|drm.*(error|fail)'
}

show_storage_errors() {
    show_kernel_matches "SSD and filesystem errors" \
        'nvme.*(error|fail|timeout|reset)|i/o error|buffer i/o|ext4-fs error|blk_update_request'
}

show_network_errors() {
    show_kernel_matches "Network errors" \
        'iwlwifi.*(error|fail|timeout)|r8169.*(error|fail|timeout)|network.*(error|fail|timeout)'
}

show_full_kernel_errors() {
    print_section "Raw kernel warnings and errors for this boot"
    journalctl -k -b -p warning..alert --no-pager -n 100 2>&1 || \
        echo "Cannot read the kernel journal. Run: sudo system errors full"
}
