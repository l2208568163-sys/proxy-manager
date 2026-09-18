#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
install_web() { install -d -m 0755 "$WEB_ROOT"; systemctl enable --now nginx; [[ -f "$WEB_ROOT/config.yaml" ]] || "$SCRIPT_DIR/subscription.sh" generate; command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && ufw allow 80/tcp || true; load_node_data; say "已发布：$SUBSCRIPTION_URL"; }
require_root
while true; do clear; say "===== Web 订阅服务 ====="; say "1. 启用 Nginx 并发布配置"; say "2. 查看状态"; say "0. 返回"; read -r -p "请选择: " c; case "$c" in 1) install_web; read -r -p "请按回车继续..." _;;2) systemctl --no-pager status nginx || true; read -r -p "请按回车继续..." _;;0) exit;;*) say "无效选择。";;esac; done
