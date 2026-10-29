# Host security and hardening audit checks.

audit_ssh_config() {
    print_section "SSH Server Hardening Audit"
    local sshd_active=0

    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        sshd_active=1
        status_tag info "sshd service is active"
    else
        status_tag info "sshd service is not running locally"
        return 0
    fi

    local configs=()
    [ -f /etc/ssh/sshd_config ] && configs+=(/etc/ssh/sshd_config)
    if [ -d /etc/ssh/sshd_config.d ]; then
        for f in /etc/ssh/sshd_config.d/*.conf; do
            [ -f "$f" ] && configs+=("$f")
        done
    fi

    if [ ${#configs[@]} -eq 0 ]; then
        status_tag warn "No sshd_config found"
        return 0
    fi

    # Check PermitRootLogin
    local root_login
    root_login=$(grep -hEi '^\s*PermitRootLogin\s+' "${configs[@]}" 2>/dev/null | tail -n1 | awk '{print $2}')
    case "${root_login:-default}" in
        no|prohibit-password)
            status_tag ok "PermitRootLogin: ${root_login}"
            ;;
        yes)
            status_tag risk "PermitRootLogin is set to YES (password root login enabled)"
            ;;
        *)
            status_tag warn "PermitRootLogin: ${root_login:-unspecified} (default on Debian is prohibit-password)"
            ;;
    esac

    # Check PasswordAuthentication
    local pass_auth
    pass_auth=$(grep -hEi '^\s*PasswordAuthentication\s+' "${configs[@]}" 2>/dev/null | tail -n1 | awk '{print $2}')
    case "${pass_auth:-yes}" in
        no)
            status_tag ok "PasswordAuthentication: no (key-based only)"
            ;;
        yes)
            status_tag warn "PasswordAuthentication: yes (consider disabling once public key auth is verified)"
            ;;
        *)
            status_tag info "PasswordAuthentication: ${pass_auth}"
            ;;
    esac

    # Check PubkeyAuthentication
    local pubkey_auth
    pubkey_auth=$(grep -hEi '^\s*PubkeyAuthentication\s+' "${configs[@]}" 2>/dev/null | tail -n1 | awk '{print $2}')
    if [ "${pubkey_auth:-yes}" = "no" ]; then
        status_tag risk "PubkeyAuthentication: no (public key auth is disabled)"
    else
        status_tag ok "PubkeyAuthentication: ${pubkey_auth:-yes (default)}"
    fi

    # Check MaxAuthTries
    local max_tries
    max_tries=$(grep -hEi '^\s*MaxAuthTries\s+' "${configs[@]}" 2>/dev/null | tail -n1 | awk '{print $2}')
    if [ -n "$max_tries" ] && [ "$max_tries" -le 4 ]; then
        status_tag ok "MaxAuthTries: ${max_tries}"
    else
        status_tag info "MaxAuthTries: ${max_tries:-6 (default)} (recommended: 3-4 to limit brute force)"
    fi
}

audit_listening_ports() {
    print_section "Listening Services & Interface Exposure"

    if ! has_command ss; then
        status_tag warn "ss command not available"
        return 1
    fi

    local lines
    local ss_rc=0
    lines=$(ss -tulpn 2>/dev/null | grep -E 'LISTEN|UNCONN') || ss_rc=$?

    if [ -z "$lines" ]; then
        status_tag ok "No listening TCP/UDP sockets detected"
        return 0
    fi

    printf '%-8s %-22s %-20s %s\n' "PROTO" "LOCAL ADDRESS" "PROCESS" "EXPOSURE"
    printf '%-8s %-22s %-20s %s\n' "------" "-------------" "-------" "--------"

    local sensitive_ports="21 23 25 110 143 445 1433 1521 2375 2376 3306 5432 6379 9200 11211 27017"
    local risks_found=0

    while read -r proto state recv send local_addr rest; do
        [ "$proto" = "Netid" ] && continue
        # parse port
        local port="${local_addr##*:}"
        local ip="${local_addr%:*}"
        local proc
        proc=$(echo "$rest" | grep -o 'users:(("[^"]*"' | sed 's/users:(("//;s/"//' | head -n1)
        proc="${proc:-unknown}"

        local exposure="LOCAL"
        if [[ "$ip" == "*" || "$ip" == "0.0.0.0" || "$ip" == "::" || "$ip" == "[::]" ]]; then
            exposure="ALL INTERFACES (0.0.0.0)"
            # Check if sensitive database or management port
            for sp in $sensitive_ports; do
                if [ "$port" = "$sp" ]; then
                    exposure="RISK: PUBLIC SENSITIVE ($port)"
                    risks_found=$((risks_found + 1))
                    break
                fi
            done
        elif [[ "$ip" =~ ^127\. || "$ip" == "::1" || "$ip" == "[::1]" ]]; then
            exposure="LOOPBACK ONLY"
        else
            exposure="BOUND IP ($ip)"
        fi

        printf '%-8s %-22s %-20s %s\n' "$proto" "$local_addr" "$proc" "$exposure"
    done <<< "$lines"

    if [ "$risks_found" -gt 0 ]; then
        status_tag risk "Detected $risks_found sensitive port(s) listening on all interfaces"
    else
        status_tag ok "No unauthenticated database or sensitive services directly exposed on 0.0.0.0"
    fi
}

audit_firewall_status() {
    print_section "Firewall & Packet Filter Status"

    local fw_detected=0

    if has_command ufw; then
        local ufw_status
        local ufw_rc=0
        ufw_status=$(ufw status 2>/dev/null) || ufw_rc=$?
        if echo "$ufw_status" | grep -q "Status: active"; then
            status_tag ok "UFW is active"
            fw_detected=1
        elif echo "$ufw_status" | grep -q "Status: inactive"; then
            status_tag warn "UFW is installed but INACTIVE"
        fi
    fi

    if has_command nft; then
        local nft_rules
        local nft_rc=0
        nft_rules=$(nft list ruleset 2>/dev/null | grep -c 'table') || nft_rc=$?
        if [ "$nft_rules" -gt 0 ]; then
            status_tag ok "nftables has $nft_rules active table(s)"
            fw_detected=1
        fi
    fi

    if has_command iptables; then
        local ipt_rules
        local ipt_rc=0
        ipt_rules=$(iptables -S 2>/dev/null | grep -c '^-A') || ipt_rc=$?
        if [ "$ipt_rules" -gt 0 ]; then
            status_tag ok "iptables has $ipt_rules filter rule(s)"
            fw_detected=1
        fi
    fi

    if [ "$fw_detected" -eq 0 ]; then
        status_tag warn "No active host firewall rules detected (relying on gateway NAT/firewall)"
    fi
}

audit_privileged_accounts() {
    print_section "Privileged Accounts & Sudo Audit"

    # UID 0 accounts
    local uid_zero
    uid_zero=$(awk -F: '$3 == 0 {print $1}' /etc/passwd 2>/dev/null | tr '\n' ' ')
    if [ "$uid_zero" = "root " ]; then
        status_tag ok "Single UID 0 account present: root"
    else
        status_tag risk "Multiple UID 0 accounts found: $uid_zero"
    fi

    # sudo / wheel group members
    local sudo_users
    sudo_users=$(getent group sudo 2>/dev/null | awk -F: '{print $4}')
    local wheel_users
    wheel_users=$(getent group wheel 2>/dev/null | awk -F: '{print $4}')
    status_tag info "Sudo group users: ${sudo_users:-none} ${wheel_users}"

    # SUID binaries in standard path (check for unusual root SUID)
    local suid_count
    suid_count=$(find /bin /usr/bin /sbin /usr/sbin -perm -4000 2>/dev/null | wc -l)
    status_tag info "System SUID binaries in /usr/bin: $suid_count"
}

audit_failed_authentications() {
    print_section "Authentication & Brute-Force Activity"

    local failed_attempts=0
    if has_command journalctl; then
        local j_rc=0
        failed_attempts=$(journalctl -u ssh -u sshd --since "24 hours ago" 2>/dev/null | grep -ic "failed password") || j_rc=$?
        if [ "$failed_attempts" -gt 50 ]; then
            status_tag warn "High SSH failure rate in last 24h: $failed_attempts attempts"
        elif [ "$failed_attempts" -gt 0 ]; then
            status_tag info "SSH failed login attempts in last 24h: $failed_attempts"
        else
            status_tag ok "Zero SSH failed login attempts in last 24h"
        fi
    elif [ -f /var/log/auth.log ]; then
        local log_rc=0
        failed_attempts=$(grep -ic "failed password" /var/log/auth.log 2>/dev/null) || log_rc=$?
        status_tag info "Recent failed passwords in /var/log/auth.log: $failed_attempts"
    else
        status_tag info "Authentication log inspection skipped (requires journald access)"
    fi
}

audit_kernel_security() {
    print_section "Kernel Security Parameters"

    if [ -f /proc/sys/kernel/yama/ptrace_scope ]; then
        local ptrace_scope
        ptrace_scope=$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo "N/A")
        if [ "$ptrace_scope" -ge 1 ]; then
            status_tag ok "kernel.yama.ptrace_scope: $ptrace_scope (restricted ptrace)"
        else
            status_tag warn "kernel.yama.ptrace_scope: $ptrace_scope (classic ptrace allowed)"
        fi
    fi

    if [ -f /proc/sys/fs/suid_dumpable ]; then
        local suid_dump
        suid_dump=$(cat /proc/sys/fs/suid_dumpable 2>/dev/null || echo "N/A")
        if [ "$suid_dump" -eq 0 ]; then
            status_tag ok "fs.suid_dumpable: 0 (core dumps disabled for SUID)"
        else
            status_tag warn "fs.suid_dumpable: $suid_dump (SUID dumps allowed)"
        fi
    fi
}

audit_host_security() {
    print_section "Comprehensive Host Security Audit"
    audit_listening_ports
    audit_ssh_config
    audit_firewall_status
    audit_privileged_accounts
    audit_failed_authentications
    audit_kernel_security
    print_section "Audit Complete"
}
