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
        sudo apt install -y nethogs iftop bind9-dnsutils iperf3 ethtool &&
        echo "Installed network tools: nethogs, iftop, bind9-dnsutils, iperf3, ethtool"
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

show_network_ports() {
    print_section "Listening Ports & Firewall Audit"
    if has_command ss; then
        printf 'Listening sockets (TCP/UDP):\n'
        ss -tulpn 2>/dev/null || ss -tuln
    else
        echo "ss command is not available."
    fi

    printf '\nFirewall status:\n'
    if has_command ufw; then
        sudo ufw status 2>/dev/null || ufw status 2>/dev/null || echo "ufw is installed but requires elevated permissions to query status."
    elif has_command nft; then
        sudo nft list ruleset 2>/dev/null || echo "nftables is present (run with sudo to view ruleset)."
    elif has_command iptables; then
        sudo iptables -L -n -v 2>/dev/null || echo "iptables is present (run with sudo to view rules)."
    else
        echo "No standard firewall management tool (ufw, nft, iptables) detected."
    fi
}

show_network_dns() {
    local target=${1:-example.com}
    print_section "DNS Diagnostics & Latency"

    if has_command resolvectl; then
        printf 'Systemd Resolver Status:\n'
        resolvectl status 2>/dev/null | grep -E 'Link|DNS Servers|DNS Domain' || resolvectl status 2>/dev/null || true
        printf '\n'
    elif [ -f /etc/resolv.conf ]; then
        printf 'Configured nameservers (/etc/resolv.conf):\n'
        grep '^nameserver' /etc/resolv.conf || true
        printf '\n'
    fi

    printf 'DNS Resolution & Latency for %s:\n' "$target"
    if has_command dig; then
        dig "$target" +stats | grep -E ';|QUERY|ANSWER|SECTION|Query time|SERVER' || dig "$target"
    elif has_command nslookup; then
        nslookup "$target"
    elif has_command getent; then
        getent hosts "$target"
    else
        echo "No DNS query tool (dig, nslookup, getent) is available."
        return 1
    fi
}

scan_wifi() {
    print_section "Wi-Fi Network Scan"
    if ! has_command nmcli; then
        echo "NetworkManager command (nmcli) is not installed." >&2
        return 1
    fi
    nmcli --fields IN-USE,SSID,BSSID,MODE,CHAN,RATE,SIGNAL,BARS,SECURITY device wifi list --rescan yes
}

connect_wifi() {
    local ssid=${1:-} password=${2:-}
    if ! has_command nmcli; then
        echo "NetworkManager command (nmcli) is not installed." >&2
        return 1
    fi
    if [ -z "$ssid" ]; then
        echo "Usage: system wifi connect <ssid> [password]" >&2
        return 2
    fi

    echo "Connecting to Wi-Fi SSID: $ssid..."
    if [ -n "$password" ]; then
        nmcli device wifi connect "$ssid" password "$password"
    else
        nmcli --ask device wifi connect "$ssid"
    fi
}

test_network_speed() {
    local iperf_server=${1:-}
    if [ -n "$iperf_server" ]; then
        if ! has_command iperf3; then
            echo "iperf3 is not installed. Run: system network install-tools --yes" >&2
            return 127
        fi
        print_section "iperf3 Speed Test ($iperf_server)"
        iperf3 -c "$iperf_server"
        return
    fi

    print_section "Network Speed Test"
    if ! has_command curl; then
        echo "curl is required for download speed test." >&2
        return 1
    fi
    echo "Testing download throughput via Cloudflare CDN..."
    local speed_bps speed_mbps
    speed_bps=$(curl -s -w "%{speed_download}" -o /dev/null --max-time 15 "https://speed.cloudflare.com/__down?bytes=25000000" 2>/dev/null || true)
    if [ -n "$speed_bps" ] && [[ "$speed_bps" =~ ^[0-9]+([.][0-9]+)?$ ]] && [ "$speed_bps" != "0" ]; then
        speed_mbps=$(awk -v bps="$speed_bps" 'BEGIN {printf "%.2f", (bps * 8) / 1000000}')
        echo "Download Speed: ${speed_mbps} Mbps (${speed_bps} bytes/sec)"
    else
        echo "Download speed test failed or timed out."
    fi
}

show_network_proxy() {
    print_section "Proxy Configuration & Connectivity"
    printf 'Environment proxy variables:\n'
    printf '  http_proxy:  %s\n' "${http_proxy:-${HTTP_PROXY:-none}}"
    printf '  https_proxy: %s\n' "${https_proxy:-${HTTPS_PROXY:-none}}"
    printf '  all_proxy:   %s\n' "${all_proxy:-${ALL_PROXY:-none}}"
    printf '  no_proxy:    %s\n' "${no_proxy:-${NO_PROXY:-none}}"

    if has_command gsettings; then
        printf '\nGNOME System Proxy Settings:\n'
        gsettings get org.gnome.system.proxy mode 2>/dev/null | xargs -I{} printf '  Mode: %s\n' "{}" || true
    fi

    printf '\nProxy Egress Verification:\n'
    if [ -n "${http_proxy:-${HTTP_PROXY:-}}" ] || [ -n "${https_proxy:-${HTTPS_PROXY:-}}" ]; then
        printf 'Testing request via proxy... '
        if curl -fsS --max-time 5 https://example.com >/dev/null 2>&1; then
            echo "OK"
        else
            echo "FAILED (Check proxy address/port)"
        fi
    else
        echo "No environment proxy configured (direct connection)."
    fi
}

show_network_vpn() {
    print_section "VPN Connections & Tunnel Interfaces"
    if has_command nmcli; then
        printf 'Active NetworkManager VPN / Tunnel Connections:\n'
        nmcli connection show --active | grep -E 'vpn|wireguard|tun|tap|ppp|type' || echo "No active NetworkManager VPN connections."
        printf '\n'
    fi

    printf 'Tunnel & Virtual Interfaces (ip link):\n'
    ip -br link show | grep -E 'tun|tap|wg|ppp|tailscale|zerotier' || echo "No virtual VPN interfaces (tun/tap/wg) active."

    if has_command wg; then
        printf '\nWireGuard Status:\n'
        sudo wg show 2>/dev/null || wg show 2>/dev/null || echo "WireGuard CLI available (run with sudo for full status)."
    fi

    if has_command tailscale; then
        printf '\nTailscale Status:\n'
        tailscale status 2>/dev/null | head -n 10 || true
    fi
}

show_network_arp() {
    print_section "ARP / Neighbor Table (Layer 2 - MAC Resolution)"
    if has_command ip; then
        ip neighbor show
    elif has_command arp; then
        arp -an
    else
        echo "No ARP/neighbor tool (ip neighbor, arp) available."
        return 1
    fi
}

show_network_routes() {
    print_section "Routing Table & Metric Details (Layer 3)"
    printf 'IPv4 Unicast Routes:\n'
    ip route show
    printf '\nIPv6 Unicast Routes:\n'
    ip -6 route show 2>/dev/null || true
}

test_network_pmtud() {
    local target=${1:-1.1.1.1}
    local size=${2:-1472}
    print_section "Path MTU Discovery (PMTUD) Test"
    printf 'Testing ICMP payload size %s bytes (DF bit set) to %s...\n' "$size" "$target"
    if ping -M do -s "$size" -c 3 "$target"; then
        echo "PMTUD Test SUCCESS: MTU supports payload size $size without fragmentation."
    else
        echo "PMTUD Test FAILED: Packet size $size exceeds Path MTU or ICMP blocked."
        return 1
    fi
}
