# Capacity testing, concurrency benchmarking, and external exposure auditing.

measure_server_capacity() {
    local target_url=${1:-}
    local concurrency=${2:-10}
    local total_requests=${3:-100}

    if [ -z "$target_url" ]; then
        echo "Usage: security capacity <url> [concurrency=10] [requests=100]" >&2
        return 2
    fi

    [[ "$target_url" =~ ^https?:// ]] || target_url="http://$target_url"
    if [[ "$target_url" =~ ^https?://[^/]+$ ]]; then
        target_url="$target_url/"
    fi

    print_section "Server Capacity & Throughput Benchmark: $target_url"
    printf '%-20s: %s\n' "Target Endpoint" "$target_url"
    printf '%-20s: %d\n' "Concurrency Level" "$concurrency"
    printf '%-20s: %d\n' "Total Requests" "$total_requests"

    # Prefer native specialized tools if available
    if has_command hey; then
        status_tag info "Running capacity benchmark using 'hey'..."
        run_bounded 60 hey -n "$total_requests" -c "$concurrency" "$target_url"
        return 0
    elif has_command wrk; then
        status_tag info "Running capacity benchmark using 'wrk'..."
        run_bounded 30 wrk -t2 -c"$concurrency" -d10s "$target_url"
        return 0
    elif has_command ab; then
        status_tag info "Running capacity benchmark using ApacheBench 'ab'..."
        run_bounded 60 ab -n "$total_requests" -c "$concurrency" -k "$target_url"
        return 0
    fi

    # Native curl multi-worker capacity benchmark
    status_tag info "Running native parallel curl benchmark (zero external dependencies)..."
    local tmp_dir="$TMPFS_DIR/capacity_bench_$$"
    mkdir -p "$tmp_dir"
    trap 'rm -rf -- "$tmp_dir"' EXIT

    local start_time
    start_time=$(date +%s%N 2>/dev/null || date +%s)

    # Dispatch requests in batches matching concurrency
    seq 1 "$total_requests" | xargs -n 1 -P "$concurrency" -I {} bash -c "
        res=\$(curl -s -o /dev/null -w '%{http_code} %{time_total}\n' --max-time 5 '$target_url' 2>/dev/null || echo '000 5.0')
        echo \"\$res\" >> '$tmp_dir/results.log'
    "

    local end_time
    end_time=$(date +%s%N 2>/dev/null || date +%s)

    local duration_ms=0
    if [ ${#start_time} -gt 10 ]; then
        duration_ms=$(( (end_time - start_time) / 1000000 ))
    else
        duration_ms=$(( (end_time - start_time) * 1000 ))
    fi
    [ "$duration_ms" -le 0 ] && duration_ms=1

    local total_completed=0
    local success_count=0
    local error_count=0
    local total_lat_ms=0

    if [ -f "$tmp_dir/results.log" ]; then
        total_completed=$(wc -l < "$tmp_dir/results.log")
        success_count=$(awk '$1 >= 200 && $1 < 400 {c++} END {print c+0}' "$tmp_dir/results.log")
        error_count=$(awk '$1 < 200 || $1 >= 400 {c++} END {print c+0}' "$tmp_dir/results.log")
        total_lat_ms=$(awk '{sum += $2 * 1000} END {printf "%.0f", sum}' "$tmp_dir/results.log")
    fi

    local rps
    rps=$(awk -v req="$total_completed" -v ms="$duration_ms" 'BEGIN {printf "%.1f", (req * 1000) / ms}')

    local avg_latency=0
    if [ "$total_completed" -gt 0 ]; then
        avg_latency=$(awk -v lat="$total_lat_ms" -v req="$total_completed" 'BEGIN {printf "%.2f", lat / req}')
    fi

    # Calculate P95 latency
    local p95_latency="N/A"
    if [ "$total_completed" -ge 10 ]; then
        local p95_idx=$(( (total_completed * 95) / 100 ))
        [ "$p95_idx" -lt 1 ] && p95_idx=1
        p95_latency=$(sort -k2 -n "$tmp_dir/results.log" | sed -n "${p95_idx}p" | awk '{printf "%.2f ms", $2 * 1000}')
    fi

    rm -rf -- "$tmp_dir"
    trap - EXIT

    printf '\n=== Capacity Benchmark Results ===\n'
    printf '%-24s: %d\n' "Requests Completed" "$total_completed"
    printf '%-24s: %d (%.1f%%)\n' "Successful (2xx/3xx)" "$success_count" "$(awk -v s="$success_count" -v t="$total_completed" 'BEGIN {if(t>0) printf "%.1f", (s*100)/t; else print 0}')"
    printf '%-24s: %d\n' "Failed / Timeouts" "$error_count"
    printf '%-24s: %s req/sec\n' "Throughput" "$rps"
    printf '%-24s: %s ms\n' "Average Latency" "$avg_latency"
    printf '%-24s: %s\n' "P95 Latency" "$p95_latency"
    printf '%-24s: %.2f s\n' "Total Wall-Clock Time" "$(awk -v ms="$duration_ms" 'BEGIN {printf "%.2f", ms / 1000}')"

    # Diagnostic assessment
    echo
    if [ "$error_count" -eq 0 ]; then
        status_tag ok "Server handled $concurrency concurrent requests with 0 dropped connections."
    elif [ "$error_count" -gt "$((total_completed / 4))" ]; then
        status_tag fail "High error rate ($error_count errors). Server reached concurrency saturation or connection throttling."
    else
        status_tag warn "Moderate error rate ($error_count errors). Investigate worker thread pool or socket limits."
    fi
}

audit_external_exposure() {
    local target_host=${1:-}
    print_section "External Attack Surface & Exposure Audit"

    # Step 1: Detect Public WAN IP
    status_tag info "Detecting public WAN IP..."
    local public_ip
    public_ip=$(run_bounded 5 curl -s https://api.ipify.org 2>/dev/null || run_bounded 5 curl -s https://ifconfig.me 2>/dev/null || echo "unavailable")
    printf '%-22s: %s\n' "Public WAN IP" "$public_ip"

    # Step 2: Gateway / Router NAT status
    local gateway_ip
    gateway_ip=$(ip route show default 2>/dev/null | awk '/default/ {print $3}' | head -n1)
    printf '%-22s: %s\n' "Local Default Gateway" "${gateway_ip:-unknown}"

    # Step 3: Local Port Ingress Surface
    print_section "Host Ingress Exposure Analysis"
    if has_command ss; then
        local wildcard_listeners
        local ss_rc=0
        wildcard_listeners=$(ss -tulpn -H 2>/dev/null | awk '$5 ~ /^(0\.0\.0\.0|\*:|\[::\]:)/ {print "  -", $1, $5, $NF}') || ss_rc=$?
        if [ -n "$wildcard_listeners" ]; then
            printf 'Services listening on 0.0.0.0 / ALL INTERFACES (Exposed to local LAN and forwarded WAN):\n'
            echo "$wildcard_listeners"
        else
            status_tag ok "No wildcard listeners detected (all services bound to loopback or specific IPs)"
        fi
    fi

    # Step 4: Vulnerability to Common Outside Attack Vectors
    print_section "Attack Surface Risk Assessment"

    # SSH Vector
    local ssh_pw_auth
    local ssh_rc=0
    ssh_pw_auth=$(grep -hEi '^\s*PasswordAuthentication\s+yes' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tail -n1) || ssh_rc=$?
    if [ -n "$ssh_pw_auth" ]; then
        status_tag risk "SSH PasswordAuthentication is ENABLED: Vulnerable to credential stuffing / brute-force if port 22 is port-forwarded."
    else
        status_tag ok "SSH PasswordAuthentication is disabled (key-only authentication mitigates credential brute-force)."
    fi

    # Host Firewall Vector
    if has_command ufw && ufw status 2>/dev/null | grep -q "Status: active"; then
        status_tag ok "Host firewall (UFW) is ACTIVE, rejecting unsolicited inbound connections."
    elif has_command nft && [ "$(nft list ruleset 2>/dev/null | grep -c 'table')" -gt 0 ]; then
        status_tag ok "Host firewall (nftables) has active filtering rules."
    elif has_command iptables && [ "$(iptables -S 2>/dev/null | grep -c '^-A')" -gt 0 ]; then
        status_tag ok "Host firewall (iptables) has active filtering rules."
    else
        status_tag warn "No active host firewall detected: Host relies 100% on router NAT to prevent outside ingress."
    fi

    # Web & TLS exposure guidance
    printf '\nRecommended Outside Hardening Checklist:\n'
    printf '  1. Router NAT: Ensure sensitive management ports (22, 8006, 3000, 8080) are NOT forwarded on router.\n'
    printf '  2. VPN Ingress: Route all remote access via Tailscale or WireGuard instead of opening WAN ports.\n'
    printf '  3. Rate Limiting: Apply fail2ban or Nginx limit_req to prevent connection exhaustion.\n'
    printf '  4. Reverse Proxy: Put public web services behind Cloudflare or HAProxy with TLS termination.\n'
}
