# Help text and command routing for the security tool.

show_security_help() {
    cat <<'HELP'
Usage: security <command> [arguments]

HOST & HARDENING AUDITS (read-only)
  security audit [host|ssh|ports|firewall|privs|auth]
      Comprehensive or targeted local host security and hardening audit.
  security status
      Quick summary of host listening ports, firewall, and SSH status.

HOMELAB NETWORK RECONNAISSANCE
  security scan [subnet]
      Fast, non-destructive network discovery of active homelab hosts.
      Defaults to current subnet (e.g. 192.168.0.0/24).
  security ports <target>
      Safe top-100 TCP port audit of a target host or lab container.

WEB & TLS INSPECTION
  security headers <url>
      Audit defensive HTTP response headers (HSTS, CSP, X-Frame-Options).
  security ssl <host> [port]
      Inspect TLS certificate validity, expiration days, cipher, and protocol.

CAPACITY & OUTSIDE EXPOSURE
  security capacity <url> [concurrency] [requests]
      Measure server capacity: requests/sec, throughput, average & P95 latency.
  security exposure
      Audit external attack surface: WAN IP, NAT boundaries, ingress listeners, and SSH.

KALI PENTEST VM LAB
  security kali [status|ssh|claude|x11 <app>]
      Status and connection bridge for Kali Linux VM 210 (192.168.4.131).

CHEATSHEETS & GUIDES
  security cheatsheet [recon|web|ssl|ssh|traffic|hardening|capacity]
      Interactive reference covering tools, commands, and security concepts.
  security learn [topic]
      Educational guide on authorized security auditing and defensive controls.
HELP
}

command_name=${1:-help}
action=${2:-}
arg3=${3:-}
arg4=${4:-}

case "$command_name" in
    help|-h|--help)
        show_security_help
        ;;
    status)
        audit_host_security
        ;;
    audit)
        case "${action:-host}" in
            host|all)       audit_host_security ;;
            ssh)            audit_ssh_config ;;
            ports)          audit_listening_ports ;;
            firewall)       audit_firewall_status ;;
            privs|users)    audit_privileged_accounts ;;
            auth|logins)    audit_failed_authentications ;;
            kernel)         audit_kernel_security ;;
            *)
                echo "Unknown audit target: $action" >&2
                echo "Valid targets: host, ssh, ports, firewall, privs, auth, kernel" >&2
                exit 2
                ;;
        esac
        ;;
    scan|discovery)
        scan_homelab_subnet "${action:-}"
        ;;
    ports)
        audit_port_exposure "$action"
        ;;
    headers)
        audit_web_headers "$action"
        ;;
    ssl|tls|cert)
        check_ssl_cert "$action" "${arg3:-443}"
        ;;
    capacity|benchmark|load)
        measure_server_capacity "$action" "${arg3:-10}" "${arg4:-100}"
        ;;
    exposure|external)
        audit_external_exposure "$action"
        ;;
    kali)
        run_kali_bridge "${action:-status}" "$arg3" "$arg4"
        ;;
    cheatsheet|learn|guide)
        show_cheatsheet "${action:-overview}"
        ;;
    *)
        echo "Unknown security command: $command_name" >&2
        show_security_help >&2
        exit 2
        ;;
esac
