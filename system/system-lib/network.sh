# Network and internet checks.

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

show_network_processes() {
    local interface

    interface=$(active_network_interface)
    print_section "Live bandwidth by process"

    if [ -z "$interface" ]; then
        echo "No active network interface was detected."
        return 1
    fi

    if ! has_command nethogs; then
        echo "nethogs is not installed. It measures live upload and download"
        echo "speed for each process."
        echo
        echo "Install it once with: sudo apt install nethogs"
        echo "Then run: system network processes"
        return 127
    fi

    echo "Interface: $interface"
    echo "Live monitor; press q to quit. sudo is needed only to read"
    echo "per-process network accounting."
    sudo nethogs -d 2 "$interface"
}

show_network_connections() {
    local interface

    interface=$(active_network_interface)
    print_section "Live bandwidth by remote connection"

    if [ -z "$interface" ]; then
        echo "No active network interface was detected."
        return 1
    fi

    if ! has_command iftop; then
        echo "iftop is not installed. It measures live traffic for each remote"
        echo "connection."
        echo
        echo "Install it with: system network install-tools --yes"
        return 127
    fi

    echo "Interface: $interface"
    echo "Live monitor; press q to quit."
    sudo iftop -i "$interface"
}

install_network_tools() {
    if [ "${1:-}" != "--yes" ]; then
        echo "This updates APT metadata and installs network tools." >&2
        echo "Run: system network install-tools --yes" >&2
        return 2
    fi

    sudo apt update &&
        sudo apt install -y nethogs iftop dnsutils iperf3 ethtool &&
        echo "Installed network tools: nethogs, iftop, dnsutils, iperf3, ethtool"
}

test_internet() {
    print_section "Internet connection"
    printf 'Ping 1.1.1.1: '
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && echo "OK" || echo "FAILED"
    printf 'HTTPS request: '
    curl -fsS --max-time 5 https://example.com >/dev/null 2>&1 && echo "OK" || echo "FAILED"
}

show_wifi_status() {
    print_section "Wi-Fi"

    if ! has_command nmcli; then
        echo "NetworkManager command (nmcli) is not installed."
        return
    fi

    nmcli -f DEVICE,TYPE,STATE,CONNECTION device status

    if has_command iw; then
        printf '\nWireless link details:\n'
        iw dev 2>/dev/null || true
    fi
}
