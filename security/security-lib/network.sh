# Network discovery, port auditing, web security, and SSL inspection.

get_default_subnet() {
    local default_ip
    default_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    if [ -n "$default_ip" ]; then
        echo "${default_ip%.*}.0/24"
    else
        echo "192.168.0.0/24"
    fi
}

scan_homelab_subnet() {
    local target=${1:-$(get_default_subnet)}
    print_section "Homelab Network Discovery: $target"

    if has_command nmap; then
        run_bounded "$SECURITY_PROBE_SECONDS" nmap -sn -PR "$target" 2>/dev/null | \
            awk '/Nmap scan report for/ {host=$5; ip=$NF; gsub(/[()]/,"",ip); if(ip=="") ip=host}
                 /MAC Address:/ {mac=$3; $1=$2=$3=""; vendor=$0; printf "%-16s %-18s %s\n", ip, mac, vendor}
                 /Nmap done:/ {print $0}'
    elif has_command arp-scan; then
        run_bounded "$SECURITY_PROBE_SECONDS" arp-scan --localnet 2>/dev/null
    else
        status_tag info "nmap not found, checking kernel ARP neighbor table"
        printf '%-18s %-20s %-10s\n' "IP ADDRESS" "MAC ADDRESS" "STATE"
        ip neigh show | awk '{printf "%-18s %-20s %-10s\n", $1, $5, $NF}'
    fi
}

audit_port_exposure() {
    local target=${1:-}
    if [ -z "$target" ]; then
        echo "Usage: security ports <target_ip_or_hostname>" >&2
        return 2
    fi

    print_section "Target Port Exposure Audit: $target"

    if has_command nmap; then
        status_tag info "Running safe top-ports scan via nmap against $target..."
        run_bounded 20 nmap -sT -T4 --top-ports 100 --open "$target" 2>/dev/null | \
            grep -E 'PORT|open' || status_tag ok "No open ports detected in top 100 ports"
    else
        status_tag info "Scanning common ports via netcat / bash sockets..."
        local common_ports=(22 53 80 443 3000 8080 8443 9090)
        for p in "${common_ports[@]}"; do
            if nc -z -w 1 "$target" "$p" 2>/dev/null; then
                status_tag warn "Port $p is OPEN on $target"
            fi
        done
    fi
}

audit_web_headers() {
    local target=${1:-}
    if [ -z "$target" ]; then
        echo "Usage: security headers <url_or_domain>" >&2
        return 2
    fi

    [[ "$target" =~ ^https?:// ]] || target="https://$target"
    print_section "Web Security Headers Audit: $target"

    if ! has_command curl; then
        status_tag fail "curl command is required for header inspection"
        return 1
    fi

    local headers
    local curl_rc=0
    headers=$(run_bounded 10 curl -s -I -L -k --max-time 8 "$target" 2>&1) || curl_rc=$?

    if [ -z "$headers" ]; then
        status_tag fail "Could not connect to $target"
        return 1
    fi

    # Check defensive headers
    local hsts csp xfo xcto rp pp
    local g_rc=0
    hsts=$(echo "$headers" | grep -i '^strict-transport-security:') || g_rc=$?
    csp=$(echo "$headers" | grep -i '^content-security-policy:') || g_rc=$?
    xfo=$(echo "$headers" | grep -i '^x-frame-options:') || g_rc=$?
    xcto=$(echo "$headers" | grep -i '^x-content-type-options:') || g_rc=$?
    rp=$(echo "$headers" | grep -i '^referrer-policy:') || g_rc=$?
    pp=$(echo "$headers" | grep -i '^permissions-policy:') || g_rc=$?

    # Server banner leaks
    local server powered_by
    server=$(echo "$headers" | grep -i '^server:' | tr -d '\r') || g_rc=$?
    powered_by=$(echo "$headers" | grep -i '^x-powered-by:' | tr -d '\r') || g_rc=$?

    if [ -n "$hsts" ]; then
        status_tag ok "HSTS enabled: $(echo "$hsts" | tr -d '\r')"
    else
        status_tag warn "Strict-Transport-Security: MISSING (vulnerable to SSL stripping)"
    fi

    if [ -n "$csp" ]; then
        status_tag ok "Content-Security-Policy: PRESENT"
    else
        status_tag warn "Content-Security-Policy: MISSING (elevated XSS impact risk)"
    fi

    if [ -n "$xfo" ]; then
        status_tag ok "X-Frame-Options: $(echo "$xfo" | tr -d '\r')"
    else
        status_tag warn "X-Frame-Options: MISSING (potential clickjacking exposure)"
    fi

    if [ -n "$xcto" ]; then
        status_tag ok "X-Content-Type-Options: $(echo "$xcto" | tr -d '\r')"
    else
        status_tag warn "X-Content-Type-Options: MISSING (MIME-sniffing risk)"
    fi

    if [ -n "$server" ]; then
        status_tag info "Information Disclosure: $server"
    fi
    if [ -n "$powered_by" ]; then
        status_tag warn "Information Disclosure: $powered_by"
    fi
}

check_ssl_cert() {
    local host=${1:-}
    local port=${2:-443}

    if [ -z "$host" ]; then
        echo "Usage: security ssl <hostname_or_ip> [port]" >&2
        return 2
    fi

    # Strip scheme if user typed https://
    host="${host#https://}"
    host="${host%%/*}"

    print_section "TLS Certificate Audit: $host:$port"

    if ! has_command openssl; then
        status_tag fail "openssl command not available"
        return 1
    fi

    local cert_output
    local ssl_rc=0
    cert_output=$(run_bounded 8 openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null) || ssl_rc=$?

    if [ -z "$cert_output" ]; then
        status_tag fail "Failed to negotiate TLS handshake with $host:$port"
        return 1
    fi

    local cert_text
    local x509_rc=0
    cert_text=$(echo "$cert_output" | openssl x509 -noout -text 2>/dev/null) || x509_rc=$?

    if [ -z "$cert_text" ]; then
        status_tag fail "Could not parse X.509 certificate from server"
        return 1
    fi

    local subject issuer not_after protocol cipher
    subject=$(echo "$cert_text" | grep -m1 'Subject:' | sed 's/^[ \t]*Subject:[ \t]*//')
    issuer=$(echo "$cert_text" | grep -m1 'Issuer:' | sed 's/^[ \t]*Issuer:[ \t]*//')
    not_after=$(echo "$cert_text" | grep -m1 'Not After :' | sed 's/^[ \t]*Not After :[ \t]*//')
    protocol=$(echo "$cert_output" | grep -m1 'Protocol  :' | awk '{print $3}')
    cipher=$(echo "$cert_output" | grep -m1 'Cipher    :' | awk '{print $3}')

    status_tag info "Subject: $subject"
    status_tag info "Issuer: $issuer"
    status_tag info "Protocol: ${protocol:-unknown} | Cipher: ${cipher:-unknown}"

    # Calculate expiry
    if [ -n "$not_after" ] && has_command date; then
        local expiry_epoch now_epoch days_left
        expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        if [ "$expiry_epoch" -gt "$now_epoch" ]; then
            days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
            if [ "$days_left" -lt 15 ]; then
                status_tag risk "Certificate expires in $days_left days ($not_after)"
            elif [ "$days_left" -lt 30 ]; then
                status_tag warn "Certificate expires in $days_left days ($not_after)"
            else
                status_tag ok "Certificate valid for $days_left days ($not_after)"
            fi
        else
            status_tag risk "Certificate is EXPIRED ($not_after)"
        fi
    fi

    # Check for legacy protocol risks
    case "$protocol" in
        TLSv1|TLSv1.1|SSLv3)
            status_tag risk "Deprecated insecure protocol: $protocol"
            ;;
        TLSv1.2)
            status_tag ok "Standard protocol: TLSv1.2"
            ;;
        TLSv1.3)
            status_tag ok "Modern protocol: TLSv1.3"
            ;;
    esac
}
