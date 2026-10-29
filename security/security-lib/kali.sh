# Integration bridge for Kali Linux Pentest VM 210.

KALI_VM_IP="192.168.4.131"
KALI_JUMP_HOST="root@100.115.226.69"

check_kali_status() {
    print_section "Kali Linux VM 210 Pentest Lab Status"

    printf '%-20s: %s\n' "Target IP" "$KALI_VM_IP"
    printf '%-20s: %s\n' "Proxmox Host" "$KALI_JUMP_HOST"

    # Ping check
    if ping -c 1 -W 2 "$KALI_VM_IP" >/dev/null 2>&1; then
        status_tag ok "VM IP is directly reachable from this host"
    else
        status_tag info "VM IP not directly pingable (may require JumpHost)"
    fi

    # SSH check via JumpHost
    export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-/run/user/1000/gcr/ssh}"
    if ssh -o BatchMode=yes -o ConnectTimeout=3 -J "$KALI_JUMP_HOST" "kali@$KALI_VM_IP" "true" 2>/dev/null; then
        status_tag ok "SSH authentication verified via $KALI_JUMP_HOST"
        # Check Claude Code inside VM
        local claude_ver
        claude_ver=$(ssh -o BatchMode=yes -o ConnectTimeout=3 -J "$KALI_JUMP_HOST" "kali@$KALI_VM_IP" "zsh -c 'claude --version'" 2>/dev/null || echo "not installed")
        status_tag info "Claude Code version on Kali: $claude_ver"
    else
        status_tag warn "SSH connection to Kali VM currently unavailable"
    fi

    printf '\nQuick access helpers:\n'
    printf '  kali               - Open interactive terminal session\n'
    printf '  kali claude        - Launch AI pentest agent inside VM\n'
    printf '  kali x11 <app>     - Launch GUI tool (burpsuite, wireshark, etc.)\n'
}

run_kali_bridge() {
    local action=${1:-status}
    [ $# -gt 0 ] && shift

    case "$action" in
        status)
            check_kali_status
            ;;
        ssh)
            if [ -x "$HOME/.local/bin/kali" ]; then
                exec "$HOME/.local/bin/kali" "$@"
            else
                export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-/run/user/1000/gcr/ssh}"
                exec ssh -J "$KALI_JUMP_HOST" "kali@$KALI_VM_IP" "$@"
            fi
            ;;
        claude)
            if [ -x "$HOME/.local/bin/kali" ]; then
                exec "$HOME/.local/bin/kali" claude "$@"
            else
                export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-/run/user/1000/gcr/ssh}"
                exec ssh -t -J "$KALI_JUMP_HOST" "kali@$KALI_VM_IP" "zsh -i -c 'claude $*'"
            fi
            ;;
        x11)
            if [ -x "$HOME/.local/bin/kali" ]; then
                exec "$HOME/.local/bin/kali" x11 "$@"
            else
                export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-/run/user/1000/gcr/ssh}"
                exec ssh -X -J "$KALI_JUMP_HOST" "kali@$KALI_VM_IP" "$@"
            fi
            ;;
        *)
            echo "Usage: security kali [status|ssh|claude|x11 <app>]" >&2
            return 2
            ;;
    esac
}
