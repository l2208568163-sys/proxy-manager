#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
enable_network_tuning() { cat >/etc/sysctl.d/99-proxy-manager.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
EOF
sysctl --system >/dev/null; say "BBR and TCP Fast Open configured."; }
require_root
while true; do clear; say "===== System Optimisation ====="; say "1. Enable BBR and TCP Fast Open"; say "2. Show status"; say "0. Back"; read -r -p "Select: " c; case "$c" in 1) enable_network_tuning; read -r -p "Press Enter..." _;;2) sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_fastopen; read -r -p "Press Enter..." _;;0) exit;;*) say "Invalid selection.";;esac; done
