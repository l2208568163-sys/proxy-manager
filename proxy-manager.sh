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
# 模块异常退出时的兜底：显示错误并暂停，让用户能看清原因（否则主菜单下一次 clear 会把错误刷掉，
# 且 set -e 会连带把整个程序退出，表现为“选完直接结束”）
module_failed() {
  say "----------------------------------------"
  say "⚠ 上一个功能因错误提前退出，原因见上方输出。"
  read -r -p "按回车返回主菜单..." _
}
while true; do
  clear; say "================================"; say " 代理管理器 Proxy Manager v$(<"$BASE_DIR/VERSION")"; say "================================"
  say "服务状态 — Xray:$(svc xray) | Nginx:$(svc nginx)"
  say "1. Xray Reality 节点"; say "2. Clash 订阅"; say "3. 系统优化"; say "4. 安全加固"; say "5. Web 订阅服务"; say "6. 健康检查"; say "7. 查看节点信息"; say "8. 更新程序"; say "9. 卸载 Proxy Manager"; say "0. 退出"
  read -r -p "请选择: " c
  case "$c" in
    1) "$BASE_DIR/modules/xray.sh" || module_failed;;
    2) "$BASE_DIR/modules/subscription.sh" || module_failed;;
    3) "$BASE_DIR/modules/system.sh" || module_failed;;
    4) "$BASE_DIR/modules/security.sh" || module_failed;;
    5) "$BASE_DIR/modules/web.sh" || module_failed;;
    6) "$BASE_DIR/tests/check.sh" || module_failed;;
    7) if load_node_data; then say "订阅地址: ${SUBSCRIPTION_URL:-（尚未生成，请运行主菜单 2 重新生成订阅）}"; say "${VLESS_URI:-}"; fi; read -r -p "请按回车继续..." _;;
    8) "$BASE_DIR/update.sh" || module_failed;; 9) exec "$BASE_DIR/uninstall.sh";; 0) exit;; *) say "无效选择。";;
  esac
done
