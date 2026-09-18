#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
enable_network_tuning() { cat >/etc/sysctl.d/99-proxy-manager.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
EOF
sysctl --system >/dev/null; say "BBR 与 TCP Fast Open 已配置。"; }
require_root
while true; do clear; say "===== 系统优化 ====="; say "1. 启用 BBR 与 TCP Fast Open"; say "2. 查看状态"; say "0. 返回"; read -r -p "请选择: " c; case "$c" in 1) enable_network_tuning; read -r -p "请按回车继续..." _;;2) sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_fastopen; read -r -p "请按回车继续..." _;;0) exit;;*) say "无效选择。";;esac; done
