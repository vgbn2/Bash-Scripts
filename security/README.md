# Homelab Cybersecurity & Pentest Toolkit

A non-destructive, CLI-first cybersecurity and reconnaissance toolkit for homelab administration, local host hardening audits, and pentest lab management.

## Capabilities

1. **Host Security & Hardening Audits (`security audit`)**:
   - Inspect listening sockets for exposed databases or unencrypted management ports on `0.0.0.0`.
   - Audit SSH server configuration for root login prevention and key authentication.
   - Verify active firewall rules (`ufw`, `nftables`, `iptables`).
   - Audit privileged accounts (`UID 0`, `sudo`/`wheel` memberships) and SUID binaries.
   - Inspect recent authentication logs for brute-force patterns.

2. **Homelab Reconnaissance (`security scan`, `security ports`)**:
   - Subnet ping discovery to map online devices across local VLANs.
   - Target TCP port exposure audit using `nmap` or native sockets.

3. **Web & TLS Security Inspection (`security headers`, `security ssl`)**:
   - Verify HTTP security response headers (`HSTS`, `CSP`, `X-Frame-Options`, `X-Content-Type-Options`).
   - Validate SSL/TLS certificates, expiry days, modern TLS protocol negotiation, and cipher suites.

4. **Kali Linux Lab Bridge (`security kali`)**:
   - Status, health check, and direct execution connector for Kali Linux VM 210 (`192.168.4.131`).
   - Direct shortcuts for terminal shell (`kali`), Claude Code AI (`kali claude`), or X11 forwarding (`kali x11 <app>`).

5. **Cheatsheets & Educational Guides (`security cheatsheet`, `security learn`)**:
   - Comprehensive references for network discovery, web auditing, TLS, SSH hardening, and capacity testing boundaries.

## Usage

```bash
# Host security audit
security audit host
security audit ports
security audit ssh

# Network discovery
security scan 192.168.0.0/24
security ports 192.168.4.110

# Web & TLS verification
security headers https://myhomelab.local
security ssl myhomelab.local 443

# Kali VM bridge
security kali status
security kali claude

# Cheatsheets & references
security cheatsheet
security cheatsheet web
security learn capacity
```
