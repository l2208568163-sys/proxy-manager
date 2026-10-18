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
pause() { read -r -p "请按回车继续..." _ || true; }
# 统一的子命令调用：任何非零退出都只提示、不带走菜单。
# 不加这层的话，模块内的 die / 失败返回在 set -Eeuo pipefail 下会让整个程序直接退出，
# 用户看到的现象是「选完菜单就结束了」，而且错误被下一次 clear 刷掉。
run_cmd() {
  local label="$1"; shift
  if ! "$@"; then
    say "（${label} 未成功完成，原因见上方输出）"
  fi
  pause
}
while true; do
  clear; say "================================"; say " 代理管理器 Proxy Manager v$(<"$BASE_DIR/VERSION")"; say "================================"
  say "服务状态 — Xray:$(svc xray) | Mihomo:$(svc mihomo) | AdGuardDNS:$(svc AdGuardHome) | Web面板:$(svc proxy-web) | Nginx:$(svc nginx)"
  say "1. Xray Reality 节点"; say "2. Clash 订阅"; say "3. Mihomo 客户端"; say "4. DNS 管理"; say "5. 系统优化"; say "6. 安全加固"; say "7. Web 订阅服务"; say "8. 健康检查"; say "9. 查看节点信息"; say "10. 更新程序"; say "11. 卸载 Proxy Manager"; say "12. Web 管理中心 ⭐"; say "0. 退出"
  read -r -p "请选择: " c || exit 0
  case "$c" in
    1) run_cmd "Xray 节点" "$BASE_DIR/modules/xray.sh";;
    2) run_cmd "Clash 订阅" "$BASE_DIR/modules/subscription.sh";;
    3) run_cmd "Mihomo 客户端" "$BASE_DIR/modules/mihomo.sh";;
    4) run_cmd "DNS 管理" "$BASE_DIR/modules/dns.sh";;
    5) run_cmd "系统优化" "$BASE_DIR/modules/system.sh";;
    6) run_cmd "安全加固" "$BASE_DIR/modules/security.sh";;
    7) run_cmd "Web 订阅服务" "$BASE_DIR/modules/web.sh";;
    8) run_cmd "健康检查" "$BASE_DIR/tests/check.sh";;
    9) if load_node_data; then
         say "订阅地址: ${SUBSCRIPTION_URL:-（尚未生成，请运行主菜单 2 重新生成订阅）}"
         say "$VLESS_URI"
       fi
       pause;;
    10) run_cmd "更新程序" "$BASE_DIR/update.sh";;
    11) exec "$BASE_DIR/uninstall.sh";;
    12) run_cmd "Web 管理中心" "$BASE_DIR/modules/webpanel.sh";;
    0) exit;;
    *) say "无效选择。";;
  esac
done
