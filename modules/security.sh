#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
install_security() { apt-get update; apt-get install -y fail2ban unattended-upgrades; systemctl enable --now fail2ban; say "Fail2ban 与自动安全更新已启用。"; }
require_root
while true; do clear; say "===== 安全加固 ====="; say "1. 安装 Fail2ban 与自动安全更新"; say "2. 查看状态"; say "0. 返回"; read -r -p "请选择: " c; case "$c" in 1) install_security; read -r -p "请按回车继续..." _;;2) systemctl --no-pager status fail2ban || true; read -r -p "请按回车继续..." _;;0) exit;;*) say "无效选择。";;esac; done
