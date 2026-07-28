# Commands that change CPU or network settings.

valid_network_limit() {
    local percent=$1 maximum=$2
    [[ "$percent" =~ ^[0-9]+$ ]] &&
        [[ "$maximum" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
        [ "$percent" -ge 1 ] &&
        [ "$percent" -le 100 ]
}

valid_download_limit() {
    valid_network_limit "$@"
}

limit_download() {
    local percent=${1:-} maximum=${2:-} interface rate

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

    # IFB lets tc shape download traffic arriving on the real interface.
    sudo modprobe ifb numifbs=1
    if ! ip link show ifb0 >/dev/null 2>&1; then
        sudo ip link add ifb0 type ifb
    fi
    sudo ip link set ifb0 up

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
    [ -n "$interface" ] && sudo tc qdisc del dev "$interface" ingress 2>/dev/null || true
    sudo tc qdisc del dev ifb0 root 2>/dev/null || true
    echo "Download limit cleared."
}

limit_upload() {
    local percent=${1:-} maximum=${2:-} interface rate

    if ! valid_network_limit "$percent" "$maximum"; then
        echo "Usage: system network limit-upload <percent> <max-mbps>" >&2
        return 2
    fi

    interface=$(active_network_interface)
    if [ -z "$interface" ]; then
        echo "Could not find the active internet interface." >&2
        return 1
    fi

    rate=$(awk -v percent="$percent" -v maximum="$maximum" \
        'BEGIN {printf "%.3f", percent * maximum / 100}')

    # The root qdisc shapes traffic leaving the real interface.
    # This affects all outgoing traffic, including rsync and SSH.
    sudo tc qdisc replace dev "$interface" root tbf \
        rate "${rate}mbit" burst 32kbit latency 400ms
    echo "Upload limit: ${rate} Mbps (${percent}% of ${maximum} Mbps)"
}

clear_upload_limit() {
    local interface
    interface=$(active_network_interface)
    [ -n "$interface" ] && sudo tc qdisc del dev "$interface" root 2>/dev/null || true
    echo "Upload limit cleared."
}
