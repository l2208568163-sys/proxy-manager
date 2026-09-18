#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"
case "${1:-}" in
  update) exec "$BASE_DIR/update.sh";; check) exec "$BASE_DIR/tests/check.sh";; version) cat "$BASE_DIR/VERSION"; exit;;
  --help|-h) echo "Usage: proxy [update|check|version]"; exit;; "") ;; *) die "Unknown command: $1";;
esac
require_root
# 服务状态简写：运行中 / 未运行（供菜单顶部状态行使用）
svc() { if service_is_active "$1" 2>/dev/null; then printf '运行中'; else printf '未运行'; fi; }
while true; do
  clear; say "================================"; say " 代理管理器 Proxy Manager v$(<"$BASE_DIR/VERSION")"; say "================================"
  say "服务状态 — Xray:$(svc xray) | Mihomo:$(svc mihomo) | AdGuardDNS:$(svc AdGuardHome) | Web面板:$(svc proxy-web) | Nginx:$(svc nginx)"
  say "1. Xray Reality 节点"; say "2. Clash 订阅"; say "3. Mihomo 客户端"; say "4. DNS 管理"; say "5. 系统优化"; say "6. 安全加固"; say "7. Web 订阅服务"; say "8. 健康检查"; say "9. 查看节点信息"; say "10. 更新程序"; say "11. 卸载 Proxy Manager"; say "12. Web 管理面板"; say "0. 退出"
  read -r -p "请选择: " c
  case "$c" in
    1) "$BASE_DIR/modules/xray.sh";;
    2) "$BASE_DIR/modules/subscription.sh";;
    3) "$BASE_DIR/modules/mihomo.sh";;
    4) "$BASE_DIR/modules/dns.sh";;
    5) "$BASE_DIR/modules/system.sh";;
    6) "$BASE_DIR/modules/security.sh";;
    7) "$BASE_DIR/modules/web.sh";;
    8) "$BASE_DIR/tests/check.sh"; read -r -p "请按回车继续..." _;;
    9) load_node_data; say "订阅地址: ${SUBSCRIPTION_URL:-http://$SERVER/clash/config.yaml}"; say "$VLESS_URI"; read -r -p "请按回车继续..." _;;
    10) "$BASE_DIR/update.sh"; read -r -p "请按回车继续..." _;; 11) exec "$BASE_DIR/uninstall.sh";; 12) "$BASE_DIR/modules/webpanel.sh";; 0) exit;; *) say "无效选择。";;
  esac
done
