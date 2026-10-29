#!/usr/bin/env bash
# wake.sh — Wake-on-LAN utility for homelab cluster nodes
# ponytail: native wakeonlan wrapper with default cluster MAC addresses
set -euo pipefail

TARGET="${1:-hpdesk}"

case "$TARGET" in
  hpdesk|hp)
    # Proxmox host hpdesk (38:22:e2:0c:27:ae)
    exec /usr/bin/wakeonlan 38:22:e2:0c:27:ae
    ;;
  dell|delloptiplex)
    # Proxmox host delloptiplex
    exec /usr/bin/wakeonlan bc:24:11:92:4a:6f
    ;;
  *)
    exec /usr/bin/wakeonlan "$TARGET"
    ;;
esac
