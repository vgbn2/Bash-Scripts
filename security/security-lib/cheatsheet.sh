# Educational security references, pentest cheatsheets, and defensive guides.

show_cheatsheet_overview() {
    cat <<'HELP'
=== Homelab Cybersecurity & Pentest Reference ===

Available topics:
  recon          Network discovery, ARP scanning, and port auditing
  web            Web application security, header auditing, and discovery
  ssl            TLS/SSL inspection, cipher testing, and certificate checks
  ssh            SSH server hardening, key auditing, and connection debugging
  traffic        Network packet capture, tcpdump, and tshark filters
  hardening      Host hardening checklist, SUID checks, and least privilege
  capacity       Capacity/stress testing benchmarks vs DoS defense patterns

Usage:
  security cheatsheet <topic>
  security learn <topic>
HELP
}

show_cheatsheet_recon() {
    cat <<'RECON'
=== Topic: Network Discovery & Port Auditing ===

1. Local Subnet Discovery (Non-destructive ping sweeps)
   nmap -sn -PR 192.168.0.0/24        # ARP scan on local broadcast domain
   arp-scan --localnet                 # Fast ARP discovery on active NIC
   ip neigh show                       # Check current kernel neighbor cache

2. Target Port Auditing (Authorized hosts only)
   nmap -sT -T4 --top-ports 100 <ip>   # Safe TCP connect scan of top ports
   nmap -sV -p 22,80,443,8080 <ip>     # Service banner detection
   nc -zv -w 2 <ip> 22 80 443          # Quick netcat socket probe

3. DNS & Domain Recon
   dig +short A <domain>               # Fast IPv4 resolution
   dig -t AXFR @<ns> <domain>          # Test for unauthorized DNS zone transfer
   nslookup -type=ptr <ip> <dns_ip>    # Reverse DNS lookup
RECON
}

show_cheatsheet_web() {
    cat <<'WEB'
=== Topic: Web Application Security Auditing ===

1. HTTP Response Header Inspection
   curl -s -I https://target.lab
   # Defensive headers checklist:
   # - Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
   # - Content-Security-Policy: default-src 'self'
   # - X-Frame-Options: DENY or SAMEORIGIN
   # - X-Content-Type-Options: nosniff
   # - Referrer-Policy: strict-origin-when-cross-origin

2. Directory & Endpoint Discovery (In authorized lab)
   gobuster dir -u http://target.lab -w /usr/share/wordlists/dirb/common.txt
   ffuf -u http://target.lab/FUZZ -w /usr/share/wordlists/dirbuster/directory-list-2.3-small.txt

3. Method & Banner Checking
   curl -X OPTIONS -i https://target.lab
   # Verify that dangerous HTTP methods (PUT, DELETE, TRACE) are disabled.
WEB
}

show_cheatsheet_ssl() {
    cat <<'SSL'
=== Topic: TLS/SSL Certificate & Cipher Inspection ===

1. Certificate Expiry & Details
   openssl s_client -connect target.lab:443 -servername target.lab </dev/null 2>/dev/null | openssl x509 -noout -text

2. Protocol Support Testing
   openssl s_client -connect target.lab:443 -tls1_2    # Test TLS 1.2
   openssl s_client -connect target.lab:443 -tls1_3    # Test TLS 1.3
   # Note: SSLv2, SSLv3, TLS 1.0, and TLS 1.1 should always negotiate rejection.

3. Automated Cipher & Vulnerability Audit
   testssl.sh https://target.lab                      # Comprehensive cipher analysis
SSL
}

show_cheatsheet_ssh() {
    cat <<'SSH'
=== Topic: SSH Security & Hardening Checklist ===

1. Recommended /etc/ssh/sshd_config Settings:
   PermitRootLogin prohibit-password   # Or 'no' to prevent root password access
   PasswordAuthentication no           # Enforce public-key authentication
   PubkeyAuthentication yes
   MaxAuthTries 3                      # Mitigate brute-force attempts
   X11Forwarding no                    # Set to no unless explicitly required
   KexAlgorithms curve25519-sha256...  # Modern elliptic curve algorithms only

2. Key Verification & Host Key Fingerprints:
   ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub
   ssh-audit target.lab                # Automated SSH cipher/kex auditor
SSH
}

show_cheatsheet_traffic() {
    cat <<'TRAFFIC'
=== Topic: Packet Capture & Traffic Forensics ===

1. tcpdump Essentials:
   sudo tcpdump -i any -n "port 53 or port 80" -c 50
   sudo tcpdump -i eth0 -n "host 192.168.4.110 and not port 22" -w /dev/shm/capture.pcap

2. tshark Filter Examples:
   tshark -r capture.pcap -Y "http.request" -T fields -e http.request.method -e http.host -e http.request.uri
   tshark -r capture.pcap -Y "dns.flags.response == 0" -T fields -e dns.qry.name
TRAFFIC
}

show_cheatsheet_hardening() {
    cat <<'HARDENING'
=== Topic: Host Security Hardening Checklist ===

1. Privilege Boundary & SUID Auditing:
   find / -perm -4000 -type f 2>/dev/null              # Audit SUID binaries
   awk -F: '$3 == 0 {print $1}' /etc/passwd            # Verify only root has UID 0

2. Kernel Memory & Core Dump Protection:
   sysctl -w fs.suid_dumpable=0                        # Prevent sensitive core dumps
   sysctl -w kernel.yama.ptrace_scope=1                # Restrict cross-process ptrace

3. Unattended Upgrades & Automatic Security Patching:
   sudo apt install unattended-upgrades
   sudo dpkg-reconfigure --priority=low unattended-upgrades
HARDENING
}

show_cheatsheet_capacity() {
    cat <<'CAPACITY'
=== Topic: Capacity Testing vs DoS Defense ===

1. Educational Axiom: Authorized Benchmarking vs DoS:
   - Denial of Service (DoS/DDoS) aims to impair availability by exhausting bandwidth,
     CPU, or memory. It causes real-world disruption and is strictly illegal without
     explicit authorization and out-of-scope for general security testing.
   - Capacity testing (load testing / benchmarking) evaluates RFC compliance, latency percentiles
     (P50, P95, P99), and throughput limits using structured, rate-controlled tooling.

2. Legitimate Capacity Benchmarking Tools:
   hey -n 1000 -c 10 -q 50 http://localhost:8080/      # Rate-limited request generator
   wrk -t4 -c50 -d10s http://localhost:8080/           # Multi-threaded HTTP benchmark

3. Defensive Measures Against Traffic Exhaustion:
   - Nginx Rate Limiting:
     limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
     limit_req zone=api_limit burst=20 nodelay;
   - Fail2ban SSH Protection:
     Monitors journald for repeated failed authentications and bans offensive IPs.
   - iptables / nftables Rate Limiting:
     iptables -A INPUT -p tcp --dport 80 -m connlimit --connlimit-above 50 -j REJECT
     iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
     iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
CAPACITY
}

show_cheatsheet() {
    local topic=${1:-overview}

    case "$topic" in
        recon|discovery|nmap)
            show_cheatsheet_recon
            ;;
        web|http|headers)
            show_cheatsheet_web
            ;;
        ssl|tls|cert)
            show_cheatsheet_ssl
            ;;
        ssh)
            show_cheatsheet_ssh
            ;;
        traffic|tcpdump|pcap)
            show_cheatsheet_traffic
            ;;
        hardening|linux)
            show_cheatsheet_hardening
            ;;
        capacity|dos|ddos|load)
            show_cheatsheet_capacity
            ;;
        overview|all|help)
            show_cheatsheet_overview
            ;;
        *)
            echo "Unknown cheatsheet topic: $topic" >&2
            show_cheatsheet_overview >&2
            return 2
            ;;
    esac
}
